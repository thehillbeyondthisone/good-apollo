/* SPDX-License-Identifier: GPL-2.0-or-later
 * Peripheral/time/checkpoint adapter. Upstream CPU C and fixed rope are unchanged.
 * Exact hidden-state linker symbols are checked by build-stepped.ps1.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include "yaAGC.h"
#include <windows.h>
#include <bcrypt.h>
#include "agc_engine.h"
#include "aquarius-agc.h"
#include "aquarius-build.h"

#define CHECKPOINT_VERSION 1
#define HEADER_BYTES 152
#define EVENT_LIMIT 262144
#define QUARTER_NS_PER_CYCLE 46875ULL
static const char rope_hash[]="ae4f9e51ac9491c3da6462233936daeffc16277cd302c43a70b8459ebcd6cca5";
typedef struct {uint32_t channel,value;uint64_t cycle;} Event;
typedef struct {int ptr,size,interval;uint64_t next_update;int32_t counts[128];} CduFifo;
_Static_assert(sizeof(CduFifo)==536,"Pinned CDU FIFO layout mismatch");
extern CduFifo native_fifos[3] __asm__("CduFifos");
extern int native_checker __asm__("CduChecker");
extern int native_trap __asm__("TrapPIPA");
extern unsigned native_gyro_count __asm__("GyroCount");
extern unsigned native_old14 __asm__("OldChannel14");
extern unsigned native_gyro_timer __asm__("GyroTimer");
extern uint64_t native_imu_count __asm__("ImuCduCount");
extern unsigned native_imu14 __asm__("ImuChannel14");
extern int native_cdux __asm__("BurstOutput.CountCDUX");
extern int native_cduy __asm__("BurstOutput.CountCDUY");
extern int native_cduz __asm__("BurstOutput.CountCDUZ");
extern int DebuggerInterruptMasks[11],CoverageCounts;
extern FILE* CduLog;
typedef struct {
    CduFifo fifos[3];int checker,trap,cdu[3],rhc[3];
    uint32_t gyro_count,old14,gyro_timer,imu14;uint64_t imu_count;
} Extras;
typedef struct {
    agc_t cpu;Extras extras;uint32_t remainder;
    Event* events;uint32_t count,read,capacity;int fault;DWORD thread;
} Context;
static Context* active;
static char error_text[256];
static int fail(const char* text){snprintf(error_text,sizeof(error_text),"%s",text);return -1;}
static Context* context(void* handle){
    if(!handle||handle!=active){fail("Invalid or inactive AGC handle");return NULL;}
    if(active->thread!=GetCurrentThreadId()){fail("AGC calls must use their creating thread");return NULL;}
    return active;
}
static int sha256(const void* data,uint32_t size,unsigned char out[32]){
    BCRYPT_ALG_HANDLE alg=NULL;BCRYPT_HASH_HANDLE hash=NULL;DWORD needed=0,object_size=0;
    unsigned char* object=NULL;NTSTATUS status=BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,NULL,0);
    if(status>=0)status=BCryptGetProperty(alg,BCRYPT_OBJECT_LENGTH,(PUCHAR)&object_size,sizeof(object_size),&needed,0);
    if(status>=0){object=malloc(object_size);if(!object)status=-1;}
    if(status>=0)status=BCryptCreateHash(alg,&hash,object,object_size,NULL,0,0);
    if(status>=0)status=BCryptHashData(hash,(PUCHAR)data,size,0);
    if(status>=0)status=BCryptFinishHash(hash,out,32,0);
    if(hash)BCryptDestroyHash(hash);if(alg)BCryptCloseAlgorithmProvider(alg,0);free(object);
    return status>=0;
}
static void unhex(const char* hex,unsigned char out[32]){
    for(int i=0;i<32;i++){unsigned value=0;sscanf(hex+2*i,"%2x",&value);out[i]=(unsigned char)value;}
}
static void capture(Extras* e){
    memcpy(e->fifos,native_fifos,sizeof(e->fifos));e->checker=native_checker;e->trap=native_trap;
    e->gyro_count=native_gyro_count;e->old14=native_old14;e->gyro_timer=native_gyro_timer;
    e->imu_count=native_imu_count;e->imu14=native_imu14;
    e->cdu[0]=native_cdux;e->cdu[1]=native_cduy;e->cdu[2]=native_cduz;
    e->rhc[0]=LastRhcPitch;e->rhc[1]=LastRhcYaw;e->rhc[2]=LastRhcRoll;
}
static void restore(const Extras* e){
    memcpy(native_fifos,e->fifos,sizeof(e->fifos));native_checker=e->checker;native_trap=e->trap;
    native_gyro_count=e->gyro_count;native_old14=e->old14;native_gyro_timer=e->gyro_timer;
    native_imu_count=e->imu_count;native_imu14=e->imu14;
    native_cdux=e->cdu[0];native_cduy=e->cdu[1];native_cduz=e->cdu[2];
    LastRhcPitch=e->rhc[0];LastRhcYaw=e->rhc[1];LastRhcRoll=e->rhc[2];
}
static int push(Context* h,int channel,int value){
    if(h->count==h->capacity&&h->read){
        memmove(h->events,h->events+h->read,(h->count-h->read)*sizeof(Event));
        h->count-=h->read;h->read=0;
    }
    if(h->count==h->capacity){
        if(h->count==EVENT_LIMIT){h->fault=1;return fail("Output queue full; drain outputs before stepping");}
        uint32_t cap=h->capacity?h->capacity*2:1024;
        if(cap>EVENT_LIMIT)cap=EVENT_LIMIT;
        Event* next=realloc(h->events,cap*sizeof(Event));
        if(!next){h->fault=1;return fail("Output event allocation failed");}
        h->events=next;h->capacity=cap;
    }
    h->events[h->count++]=(Event){(uint32_t)channel,(uint32_t)value,h->cpu.CycleCounter};return 0;
}
FILE* rfopen(const char* name,const char* mode){
    int count=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,name,-1,NULL,0);
    wchar_t wide_mode[16];
    if(!count||!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,mode,-1,wide_mode,16))return NULL;
    wchar_t* wide_name=malloc((size_t)count*sizeof(wchar_t));if(!wide_name)return NULL;
    if(!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,name,-1,wide_name,count)){free(wide_name);return NULL;}
    FILE* file=_wfopen(wide_name,wide_mode);free(wide_name);return file;
}
void BacktraceAdd(agc_t* s,int cause){(void)s;(void)cause;}
int ChannelInput(agc_t* s){(void)s;return 0;}
void ChannelRoutine(agc_t* s){(void)s;}
void ShiftToDeda(agc_t* s,int data){(void)s;(void)data;}
void RequestRadarData(agc_t* s){(void)s;}
void ChannelOutput(agc_t* s,int channel,int value){
    if(channel==7){s->InputChannel[7]=s->OutputChannel7=value&0160;return;}
    if(channel==013&&(value&0600)==0600&&!CmOrLm){
        s->Erasable[0][042]=LastRhcPitch;s->Erasable[0][043]=LastRhcYaw;s->Erasable[0][044]=LastRhcRoll;
    }
    Context* h=s->agc_clientdata;if(h&&channel>=0&&channel<NUM_CHANNELS)push(h,channel,value&077777);
}
AAGC_API uint32_t Aagc_GetAbiVersion(void){return 1;}
AAGC_API const char* Aagc_LastError(void){return error_text;}
AAGC_API void* Aagc_Create(const char* path){
    if(active){fail("Only one active CPU context is supported");return NULL;}
    if(!path){fail("A rope path is required");return NULL;}
    FILE* f=rfopen(path,"rb");if(!f){fail("Rope file cannot be opened");return NULL;}
    unsigned char* bytes=malloc(73729);unsigned char digest[32],expected[32];
    size_t n=bytes?fread(bytes,1,73729,f):0;fclose(f);unhex(rope_hash,expected);
    int valid=n==73728&&sha256(bytes,(uint32_t)n,digest)&&!memcmp(digest,expected,32);free(bytes);
    if(!valid){fail("Exact pinned LM131R1 rope hash/size check failed");return NULL;}
    Context* h=calloc(1,sizeof(*h));if(!h){fail("CPU allocation failed");return NULL;}
    h->thread=GetCurrentThreadId();DebugDsky=DebugMode=InhibitAlarms=ShowAlarms=CoverageCounts=DedaMonitor=0;
    initializeSunburst37=0;SingleStepCounter=-2;CmOrLm=0;CduLog=NULL;
    for(int i=0;i<11;i++)DebuggerInterruptMasks[i]=1;
    restore(&h->extras);
    if(agc_engine_init(&h->cpu,path,NULL,0)){free(h);fail("Upstream CPU initialization failed");return NULL;}
    h->cpu.agc_clientdata=h;active=h;error_text[0]=0;return h;
}
AAGC_API void Aagc_Destroy(void* handle){Context* h=context(handle);if(h){active=NULL;free(h->events);free(h);}}
AAGC_API int Aagc_ColdRestart(void* handle){
    Context* h=context(handle);
    if(!h)return -1;
    agc_t* next=calloc(1,sizeof(*next));
    if(!next)return fail("AGC restart allocation failed");
    if(agc_engine_init(next,NULL,NULL,0)){
        free(next);
        return fail("Upstream AGC restart initialization failed");
    }

    memcpy(next->Fixed,h->cpu.Fixed,sizeof(next->Fixed));
    memcpy(next->Parities,h->cpu.Parities,sizeof(next->Parities));
    next->CheckParity=h->cpu.CheckParity;
    /* R-700 Table 3-IV: E0 0000–0007 address central registers, while
     * 0010 onward, including the interrupt storage words, is erasable core. */
    memcpy(&next->Erasable[0][RegARUPT],&h->cpu.Erasable[0][RegARUPT],
        sizeof(next->Erasable[0])-RegARUPT*sizeof(next->Erasable[0][0]));
    memcpy(next->Erasable+1,h->cpu.Erasable+1,sizeof(next->Erasable)-sizeof(next->Erasable[0]));
    next->agc_clientdata=h;
    h->cpu=*next;
    free(next);

    memset(&h->extras,0,sizeof(h->extras));
    restore(&h->extras);
    h->remainder=0;
    h->count=h->read=0;
    h->fault=0;
    return 0;
}
AAGC_API int Aagc_StepCycles(void* handle,uint64_t cycles){
    Context* h=context(handle);if(!h)return -1;
    if(cycles>UINT64_MAX-h->cpu.CycleCounter)return fail("Cycle counter would overflow");
    for(uint64_t i=0;i<cycles;i++){if(h->fault)return fail("AGC output queue fault; checkpoint/load or recreate required");agc_engine(&h->cpu);}
    return h->fault?fail("AGC output queue fault"):0;
}
AAGC_API int Aagc_StepNanoseconds(void* handle,uint64_t ns){
    Context* h=context(handle);if(!h)return -1;
    if(ns>(UINT64_MAX-h->remainder)/4)return fail("Time delta exceeds integer range");
    uint64_t quarter_ns=ns*4+h->remainder,cycles=quarter_ns/QUARTER_NS_PER_CYCLE;
    if(Aagc_StepCycles(h,cycles))return -1;
    h->remainder=(uint32_t)(quarter_ns%QUARTER_NS_PER_CYCLE);return 0;
}
AAGC_API int Aagc_StepSeconds(void* handle,double seconds){
    if(!isfinite(seconds)||seconds<0||seconds>3600)return fail("Seconds must be finite and within0..3600");
    double ns=seconds*1e9;
    return Aagc_StepNanoseconds(handle,(uint64_t)llround(ns));
}
AAGC_API int Aagc_SetInput(void* handle,uint32_t channel,uint32_t value,uint32_t mask){
    Context* h=context(handle);if(!h)return -1;
    if(h->fault)return fail("AGC output fault; restore a valid checkpoint or recreate before input");
    if(channel>=NUM_CHANNELS||value>077777||mask>077777)return fail("Input channel/value/mask out of range");
    value=(value&mask)|(ReadIO(&h->cpu,channel)&~mask);WriteIO(&h->cpu,channel,value);
    if(channel==015)h->cpu.InterruptRequests[5]=1;
    else if(channel==0173){h->cpu.Erasable[0][RegINLINK]=value&077777;h->cpu.InterruptRequests[7]=1;}
    else if(channel>=0166&&channel<=0170){
        if(channel==0166)LastRhcPitch=value;else if(channel==0167)LastRhcYaw=value;else LastRhcRoll=value;
        ChannelOutput(&h->cpu,channel,value);
    }
    return h->fault?-1:0;
}
AAGC_API int Aagc_SetKey(void* handle,uint32_t code,uint32_t pressed){
    if(pressed>1||code>31)return fail("Invalid key code/pressed value");
    if(code==0)return Aagc_SetInput(handle,032,pressed?0:020000,020000);
    if(!context(handle))return -1;
    return pressed?Aagc_SetInput(handle,015,code,077777):0;
}
AAGC_API int Aagc_IncrementCounter(void* handle,uint32_t counter,uint32_t type){
    Context* h=context(handle);if(!h)return -1;
    if(h->fault)return fail("AGC output fault; restore a valid checkpoint or recreate before input");
    if(counter>0177||!(type<=6||type==021||type==023))return fail("Invalid counter increment");
    UnprogrammedIncrement(&h->cpu,counter,type);return 0;
}
AAGC_API int Aagc_PollOutputAt(void* handle,uint32_t* channel,uint32_t* value,uint64_t* cycle){
    Context* h=context(handle);if(!h)return -1;
    if(!channel||!value)return fail("Output pointers are required");
    if(h->read==h->count)return 0;
    Event e=h->events[h->read++];*channel=e.channel;*value=e.value;if(cycle)*cycle=e.cycle;
    if(h->read==h->count)h->read=h->count=0;return 1;
}
AAGC_API int Aagc_PollOutput(void* handle,uint32_t* channel,uint32_t* value){return Aagc_PollOutputAt(handle,channel,value,NULL);}
AAGC_API int Aagc_GetDsky(void* handle,uint32_t* rows,uint32_t* ch11,uint32_t* ch13,uint32_t* ch163,uint64_t* cycles){
    Context* h=context(handle);if(!h)return -1;
    if(!rows||!ch11||!ch13||!ch163||!cycles)return fail("Snapshot pointers are required");
    for(int i=0;i<16;i++)rows[i]=(uint16_t)h->cpu.OutputChannel10[i];
    *ch11=(uint16_t)h->cpu.InputChannel[011];*ch13=(uint16_t)h->cpu.InputChannel[013];
    *ch163=h->cpu.DskyChannel163;*cycles=h->cpu.CycleCounter;return 0;
}
AAGC_API int Aagc_GetTiming(void* handle,uint64_t* cycles,uint32_t* remainder){
    Context* h=context(handle);if(!h)return -1;if(!cycles||!remainder)return fail("Timing pointers are required");
    *cycles=h->cpu.CycleCounter;*remainder=h->remainder;return 0;
}
AAGC_API int Aagc_GetInput(void* handle,uint32_t channel,uint32_t* value){
    Context* h=context(handle);if(!h)return -1;
    if(!value||channel>=NUM_CHANNELS)return fail("Input channel/output pointer is invalid");
    *value=ReadIO(&h->cpu,channel)&077777;return 0;
}

/* Explicit little-endian codec: no agc_t padding, pointers or compiler bitfield layout. */
typedef struct {unsigned char* data;uint32_t size,pos;int read,error;} Codec;
static void raw(Codec* c,void* bytes,uint32_t size){
    if(c->error||size>c->size-c->pos){c->error=1;return;}
    if(c->data){if(c->read)memcpy(bytes,c->data+c->pos,size);else memcpy(c->data+c->pos,bytes,size);}c->pos+=size;
}
static void u32(Codec* c,uint32_t* value){
    unsigned char b[4];if(!c->read)for(int i=0;i<4;i++)b[i]=(unsigned char)(*value>>(i*8));raw(c,b,4);
    if(c->read&&!c->error){*value=0;for(int i=0;i<4;i++)*value|=(uint32_t)b[i]<<(i*8);}
}
static void u64(Codec* c,uint64_t* value){
    uint32_t low=(uint32_t)*value,high=(uint32_t)(*value>>32);u32(c,&low);u32(c,&high);
    if(c->read)*value=(uint64_t)low|((uint64_t)high<<32);
}
static void word(Codec* c,int16_t* value){
    unsigned char b[2];if(!c->read){b[0]=(unsigned char)*value;b[1]=(unsigned char)((uint16_t)*value>>8);}raw(c,b,2);
    if(c->read&&!c->error)*value=(int16_t)((uint16_t)b[0]|((uint16_t)b[1]<<8));
}
#define SCALAR(field) do{uint32_t v=(uint32_t)(field);u32(c,&v);if(c->read)(field)=v;}while(0)
#define BITS(field,max) do{uint32_t v=(uint32_t)(field);u32(c,&v);if(v>(max))c->error=1;if(c->read)(field)=v;}while(0)
static void body(Codec* c,Context* h){
    agc_t* s=&h->cpu;Extras* e=&h->extras;
    u64(c,&s->CycleCounter);
    for(int b=0;b<8;b++)for(int j=0;j<0400;j++)word(c,&s->Erasable[b][j]);
    for(int b=0;b<40;b++)for(int j=0;j<02000;j++)word(c,&s->Fixed[b][j]);
    for(int i=0;i<40*(02000/32);i++)u32(c,&s->Parities[i]);
    for(int i=0;i<NUM_CHANNELS;i++)word(c,&s->InputChannel[i]);
    word(c,&s->OutputChannel7);for(int i=0;i<16;i++)word(c,&s->OutputChannel10[i]);word(c,&s->IndexValue);
    raw(c,s->InterruptRequests,sizeof(s->InterruptRequests));
    BITS(s->ExtraCode,1);BITS(s->AllowInterrupt,1);BITS(s->InIsr,1);BITS(s->SubstituteInstruction,1);
    BITS(s->PendFlag,1);BITS(s->PendDelay,7);BITS(s->ExtraDelay,7);BITS(s->DownruptTimeValid,1);
    BITS(s->NightWatchman,1);BITS(s->NightWatchmanTripped,1);BITS(s->RuptLock,1);BITS(s->NoRupt,1);
    BITS(s->TCTrap,1);BITS(s->NoTC,1);BITS(s->Standby,1);BITS(s->SbyPressed,1);BITS(s->SbyStillPressed,1);
    BITS(s->ParityFail,1);BITS(s->CheckParity,1);BITS(s->RestartLight,1);BITS(s->TookBZF,1);BITS(s->TookBZMF,1);
    BITS(s->GeneratedWarning,1);BITS(s->Trap31A,1);BITS(s->Trap31B,1);BITS(s->Trap32,1);BITS(s->RadarGateCounter,15);
    u32(c,&s->WarningFilter);u64(c,&s->DownruptTime);SCALAR(s->Downlink);SCALAR(s->NextZ);
    SCALAR(s->ScalerCounter);SCALAR(s->ChannelRoutineCount);u32(c,&s->DskyTimer);u32(c,&s->DskyFlash);u32(c,&s->DskyChannel163);
    for(int k=0;k<3;k++){
        CduFifo* f=&e->fifos[k];SCALAR(f->ptr);SCALAR(f->size);SCALAR(f->interval);u64(c,&f->next_update);
        for(int j=0;j<128;j++)SCALAR(f->counts[j]);
        if(f->ptr<0||f->ptr>=128||f->size<0||f->size>128||f->interval<0||f->interval>2)c->error=1;
    }
    SCALAR(e->checker);SCALAR(e->trap);for(int i=0;i<3;i++){SCALAR(e->cdu[i]);SCALAR(e->rhc[i]);}
    u32(c,&e->gyro_count);u32(c,&e->old14);u32(c,&e->gyro_timer);u32(c,&e->imu14);u64(c,&e->imu_count);
    u32(c,&h->remainder);SCALAR(h->fault);
    uint32_t count=h->count-h->read;u32(c,&count);
    if(count>EVENT_LIMIT){c->error=1;return;}
    if(c->read){h->events=count?calloc(count,sizeof(Event)):NULL;h->count=h->capacity=count;h->read=0;if(count&&!h->events){c->error=1;return;}}
    for(uint32_t i=0;i<count;i++){
        Event* event=&h->events[h->read+i];u32(c,&event->channel);u32(c,&event->value);u64(c,&event->cycle);
        if(event->channel>=NUM_CHANNELS||event->value>077777||event->cycle>s->CycleCounter)c->error=1;
    }
    if(e->checker<0||e->checker>=3||h->remainder>=QUARTER_NS_PER_CYCLE||h->fault<0||h->fault>1)c->error=1;
    /* Pending instructions, extra delay and CDU servicing return before scaler
     * servicing, so a valid inter-cycle checkpoint can have ScalerCounter>=80.
     * Preserve safe nonnegative integer states rather than invent a bound. */
    if(s->ScalerCounter<0||s->ScalerCounter>INT_MAX-3||s->ChannelRoutineCount<0||s->ChannelRoutineCount>017777)c->error=1;
    if(s->DskyFlash>=4||s->DskyTimer>81920||s->DskyChannel163>077777)c->error=1;
    /* A full/allocation fault can have lost an output. Save remains available
     * for diagnostics, but such a state cannot be committed as a usable CPU. */
    if(c->read&&h->fault)c->error=1;
}
static uint32_t payload_size(Context* h){
    capture(&h->extras);Codec c={NULL,UINT32_MAX,0,0,0};body(&c,h);return c.error?0:c.pos;
}
AAGC_API uint32_t Aagc_CheckpointSize(void* handle){Context* h=context(handle);if(!h)return 0;uint32_t n=payload_size(h);return n?n+HEADER_BYTES:0;}
AAGC_API int Aagc_Save(void* handle,void* destination,uint32_t size){
    Context* h=context(handle);if(!h)return -1;uint32_t n=payload_size(h);
    if(!n||!destination||size!=n+HEADER_BYTES)return fail("Checkpoint output size is incorrect");
    unsigned char* out=destination;Codec p={out+HEADER_BYTES,n,0,0,0};body(&p,h);
    if(p.error)return fail("CPU state cannot be serialized");
    unsigned char digest[32];if(!sha256(out+HEADER_BYTES,n,digest))return fail("Checkpoint hashing failed");
    Codec c={out,HEADER_BYTES,0,0,0};unsigned char magic[8]={'A','Q','A','G','C','0','1',0};raw(&c,magic,8);
    uint32_t version=CHECKPOINT_VERSION,abi=1,reserved=0;u32(&c,&version);u32(&c,&abi);u32(&c,&n);u32(&c,&reserved);
    unsigned char fingerprint[32];unhex(rope_hash,fingerprint);raw(&c,fingerprint,32);
    unhex(AAGC_SOURCE_HASH,fingerprint);raw(&c,fingerprint,32);unhex(AAGC_BUILD_HASH,fingerprint);raw(&c,fingerprint,32);raw(&c,digest,32);
    return 0;
}
static Context* stage(Context* live,const void* bytes,uint32_t size){
    if(!bytes||size<HEADER_BYTES||size>HEADER_BYTES+200000+EVENT_LIMIT*sizeof(Event)){fail("Checkpoint size is invalid");return NULL;}
    Codec c={(unsigned char*)bytes,HEADER_BYTES,0,1,0};unsigned char magic[8],fingerprints[128],expected[32],digest[32];
    uint32_t version=0,abi=0,n=0,reserved=0;
    raw(&c,magic,8);u32(&c,&version);u32(&c,&abi);u32(&c,&n);u32(&c,&reserved);
    if(memcmp(magic,"AQAGC01",8)||version!=CHECKPOINT_VERSION||abi!=1||n!=size-HEADER_BYTES||reserved){fail("Checkpoint format/version is invalid");return NULL;}
    raw(&c,fingerprints,128);
    if(c.error||memcmp(magic,"AQAGC01",8)||version!=CHECKPOINT_VERSION||abi!=1||reserved||n!=size-HEADER_BYTES){fail("Checkpoint header/version is incompatible");return NULL;}
    const char* hashes[]={rope_hash,AAGC_SOURCE_HASH,AAGC_BUILD_HASH};
    for(int i=0;i<3;i++){unhex(hashes[i],expected);if(memcmp(fingerprints+32*i,expected,32)){fail("Checkpoint rope/source/adapter build fingerprint mismatch");return NULL;}}
    if(!sha256((const unsigned char*)bytes+HEADER_BYTES,n,digest)||memcmp(digest,fingerprints+96,32)){fail("Checkpoint checksum mismatch");return NULL;}
    Context* next=calloc(1,sizeof(*next));if(!next){fail("Checkpoint staging allocation failed");return NULL;}
    Codec payload={(unsigned char*)bytes+HEADER_BYTES,n,0,1,0};body(&payload,next);
    if(payload.error||payload.pos!=n||memcmp(next->cpu.Fixed,live->cpu.Fixed,sizeof(live->cpu.Fixed))||
       memcmp(next->cpu.Parities,live->cpu.Parities,sizeof(live->cpu.Parities))){
        free(next->events);free(next);fail("Checkpoint CPU/peripheral data is invalid");return NULL;
    }
    return next;
}
AAGC_API int Aagc_ValidateCheckpoint(void* handle,const void* bytes,uint32_t size){
    Context* h=context(handle);if(!h)return -1;Context* next=stage(h,bytes,size);if(!next)return -1;
    free(next->events);free(next);return 0;
}
AAGC_API int Aagc_GetCheckpointTiming(void* handle,const void* bytes,uint32_t size,uint64_t* cycles,uint32_t* remainder){
    Context* h=context(handle);if(!h)return -1;
    if(!cycles||!remainder)return fail("Checkpoint timing output pointers are required");
    Context* next=stage(h,bytes,size);if(!next)return -1;
    *cycles=next->cpu.CycleCounter;*remainder=next->remainder;
    free(next->events);free(next);return 0;
}
AAGC_API int Aagc_Load(void* handle,const void* bytes,uint32_t size){
    Context* h=context(handle);if(!h)return -1;Context* next=stage(h,bytes,size);if(!next)return -1;
    /* Nothing above this point mutates the live CPU, globals, queue or time. */
    free(h->events);DWORD thread=h->thread;*h=*next;h->thread=thread;h->cpu.agc_clientdata=h;
    restore(&h->extras);free(next);return 0;
}

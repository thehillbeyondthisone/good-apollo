"""Test unchanged CPU equivalence, full checkpoints, exact clock carry and power restart."""
from pathlib import Path
import argparse
import csv
import ctypes as C
import hashlib
import json
import struct

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--data-root',type=Path,default=Path('D:/apollo-ref'))
parser.add_argument('--build-root',type=Path)
parser.add_argument('--report',type=Path)
args=parser.parse_args()
root=Path(__file__).resolve().parents[2]
fixtures=args.data_root/'build/agc'
build=(args.build_root or fixtures).resolve()
report_path=args.report or (build/'stepped/power-cycle-test.json' if args.build_root else root/'reference/agc-stepped-test.json')
dll=C.CDLL(str(build/'AquariusAgc.dll'))
ptr=C.c_void_p;u32=C.c_uint32;u64=C.c_uint64
def bind(name,restype,args):
    fn=getattr(dll,'Aagc_'+name);fn.restype=restype;fn.argtypes=args;return fn
create=bind('Create',ptr,[C.c_char_p]);destroy=bind('Destroy',None,[ptr])
restart=bind('ColdRestart',C.c_int,[ptr])
error=bind('LastError',C.c_char_p,[])
cycles=bind('StepCycles',C.c_int,[ptr,u64]);nanos=bind('StepNanoseconds',C.c_int,[ptr,u64])
key=bind('SetKey',C.c_int,[ptr,u32,u32]);input_=bind('SetInput',C.c_int,[ptr,u32,u32,u32])
get_input=bind('GetInput',C.c_int,[ptr,u32,C.POINTER(u32)])
increment=bind('IncrementCounter',C.c_int,[ptr,u32,u32])
poll=bind('PollOutputAt',C.c_int,[ptr,C.POINTER(u32),C.POINTER(u32),C.POINTER(u64)])
timing=bind('GetTiming',C.c_int,[ptr,C.POINTER(u64),C.POINTER(u32)])
size=bind('CheckpointSize',u32,[ptr]);save_=bind('Save',C.c_int,[ptr,ptr,u32])
validate=bind('ValidateCheckpoint',C.c_int,[ptr,ptr,u32]);load=bind('Load',C.c_int,[ptr,ptr,u32])
checkpoint_timing=bind('GetCheckpointTiming',C.c_int,[ptr,ptr,u32,C.POINTER(u64),C.POINTER(u32)])
checks=[];h=None
def check(condition,message):
    checks.append({'name':message,'passed':bool(condition)})
    if not condition:raise AssertionError(message+': '+error().decode())
def ok(code):
    if code:raise AssertionError(error().decode())
def new():
    handle=create(str(build/'LM131R1/MAIN.agc.bin').encode())
    check(bool(handle),'Pinned exact rope context created');return handle
def save():
    n=size(h);check(n>0,'Full checkpoint size available');buf=C.create_string_buffer(n);ok(save_(h,buf,n));return buf.raw
def state_time():
    c=u64();r=u32();ok(timing(h,C.byref(c),C.byref(r)));return c.value,r.value
def drain():
    result=[];channel=u32();value=u32();cycle=u64()
    while True:
        status=poll(h,C.byref(channel),C.byref(value),C.byref(cycle))
        if status<0:raise AssertionError(error().decode())
        if not status:return result
        result.append((cycle.value,channel.value,value.value))
def press(code):ok(key(h,code,1));ok(cycles(h,21333));ok(key(h,code,0))
def replay():
    ok(nanos(h,50000001));ok(key(h,17,1));ok(nanos(h,250000007));ok(key(h,3,1))
    ok(increment(h,0o33,0o21));ok(nanos(h,250000009));ok(key(h,0,0));ok(nanos(h,650000013))

# Inspect the canonical little-endian checkpoint, not the DLL's in-memory layout.
CORE_START=152+8  # Header and u64 cycle count.
CENTRAL_BYTES=8*2
CORE_END=CORE_START+8*0o400*2
def erasable_word(checkpoint, bank, address):
    return struct.unpack_from('<H', checkpoint, CORE_START+2*(bank*0o400+address))[0]

try:
    h=new()
    check(not create(str(build/'LM131R1/MAIN.agc.bin').encode()),'Second simultaneous CPU is rejected')
    ok(cycles(h,255999))
    for code in [17,3,7,28,16,16,28]:press(code)
    ok(cycles(h,85333))
    for code in [17,3,5,28]:press(code)
    ok(cycles(h,597331))
    events=drain()
    trace=[event for event in events if event[1] in (0o10,0o11,0o13,0o163,0o77)]
    with (fixtures/'lamp-test.csv').open() as file:
        expected=[(int(x['cycle']),int(x['channel_octal'],8),int(x['value_octal'],8)) for x in csv.DictReader(file)]
    check(trace==expected,'Every DSKY/alarm output cycle/channel/value equals deterministic unchanged-core fixture')
    rows=[0]*16;channels={};frame=None
    for cycle,channel,value in trace:
        channels[channel]=value
        if channel==0o10:rows[(value>>11)&15]=value
        all_eights=all((rows[row]&31)==29 if row==8 else (rows[row]&1023)==957 for row in range(1,12))
        if frame is None and all_eights and channels.get(0o13,0)&0o1000 and channels.get(0o11,0)&0o175==0o175:
            frame={'cycle':cycle,'rows':rows.copy(),'channel11':channels.get(0o11,0),'channel13':channels.get(0o13,0),'channel163':channels.get(0o163,0)}
    check(frame is not None,'Native adapter emits authentic V35 all-eight frame')
    cli=json.loads((fixtures/'cli-lamp-result.json').read_text(encoding='utf-8-sig'))['lampFrame']
    check(frame['rows']==cli['rows'] and all(frame[name]==cli['channels'][str(ch)] for name,ch in [('channel11',0o11),('channel13',0o13),('channel163',0o163)]),
          'Lamp digits and hardware status equal genuine upstream CLI/TCP frame')
    check(not channels[0o13]&0o1000,'Lamp-test alarm clears on actual CPU schedule')
    destroy(h);h=None

    h=new();ok(nanos(h,250000000));ok(nanos(h,250000000));ok(nanos(h,250000000))
    check(state_time()==(64000,0),'Three quarter-second steps equal exactly64000 physical machine cycles')
    ok(nanos(h,1));check(state_time()==(64000,4),'Subcycle quarter-nanosecond remainder is retained')
    ok(key(h,0,1))
    for counter,kind in [(0o32,1),(0o32,1),(0o32,3),(0o33,0o21),(0o34,0o23)]:ok(increment(h,counter,kind))
    checkpoint=save()
    replay();final=save();first_events=drain()
    live_before_timing=save();saved_cycles=u64();saved_remainder=u32()
    ok(checkpoint_timing(h,checkpoint,len(checkpoint),C.byref(saved_cycles),C.byref(saved_remainder)))
    check((saved_cycles.value,saved_remainder.value)==(64000,4) and state_time()!=(64000,4),
          'Checkpoint timing comes from validated staged payload rather than current live clock or wrapper metadata')
    check(save()==live_before_timing,'Authoritative checkpoint timing inspection cannot mutate CPU/globals/queue/time')
    ok(load(h,checkpoint,len(checkpoint)))
    check(save()==checkpoint,'Restore and immediate save reproduce complete canonical bytes including pending queue/remainder')
    held=u32();ok(get_input(h,0o32,C.byref(held)))
    check(not held.value&0o20000,'Held PRO state survives native checkpoint without implicit normalization')
    replay();replayed=save();second_events=drain()
    check(final==replayed,'Restored CPU/hidden peripheral state replays bit-exact full checkpoint')
    check(first_events==second_events,'Queued and subsequent output events replay identically with exact cycle timestamps')
    ok(load(h,checkpoint,len(checkpoint)))
    before=save();bad=bytearray(before);bad[-1]^=1
    saved_cycles.value=123;saved_remainder.value=456
    check(checkpoint_timing(h,bytes(bad),len(bad),C.byref(saved_cycles),C.byref(saved_remainder))<0 and
          (saved_cycles.value,saved_remainder.value)==(123,456),
          'Corrupt timing inspection rejects payload and leaves output pointers unchanged')
    check(validate(h,bytes(bad),len(bad))<0 and load(h,bytes(bad),len(bad))<0,'Corrupt checksum rejected by validate and load')
    check(save()==before,'Rejected checkpoint leaves live CPU/globals/queue/clock unchanged')
    bad=bytearray(before);bad[8:12]=struct.pack('<I',999)
    check(load(h,bytes(bad),len(bad))<0,'Unknown checkpoint schema rejected')
    check(save()==before,'Unknown schema cannot partially mutate live state')
    bad=bytearray(before);bad[88]^=1
    check(load(h,bytes(bad),len(bad))<0,'Different adapter build rejected')
    check(save()==before,'Incompatible build cannot partially mutate live state')
    destroy(h);h=None;h=new()
    # Synthetic counter/drive inputs exercise the function-local coarse CDU
    # accumulators and gyro state that upstream's text core dump omits. These
    # are native peripheral test fixtures, never a mission padload.
    for counter,count in [(0o50,200),(0o51,100),(0o52,80),(0o47,1200)]:
        for _ in range(count):ok(increment(h,counter,1))
    ok(input_(h,0o14,0o71000,0o77777));ok(cycles(h,1))
    stress=save();pending_stress=drain()
    check(all(any(event[1]==channel and event[2] for event in pending_stress) for channel in [0o174,0o175,0o176,0o177]),
          'Synthetic coarse XYZ and gyro peripheral outputs are active before hidden-state checkpoint')
    ok(load(h,stress,len(stress)))
    for _ in range(37):ok(increment(h,0o47,1))
    ok(cycles(h,16001));stress_final=save();stress_events=drain()
    ok(load(h,stress,len(stress)))
    for _ in range(37):ok(increment(h,0o47,1))
    ok(cycles(h,16001));stress_repeat=save();stress_replay=drain()
    check(stress_final==stress_repeat and stress_events==stress_replay,
          'Nonzero coarse/gyro hidden accumulators replay byte-exact state and output event schedule')
    # A synthetic erasable image distinguishes central registers, physical
    # interrupt storage, unswitched core and a switched bank. No padload is used.
    ok(load(h,stress,len(stress)));ok(nanos(h,1));ok(key(h,0,1))
    dirty=bytearray(save())
    for bank,address,value in [(0,0,0o123),(0,0o10,0o245),(0,0o320,9),(7,0o377,0o325)]:
        struct.pack_into('<H',dirty,CORE_START+2*(bank*0o400+address),value)
    dirty[120:152]=hashlib.sha256(dirty[152:]).digest()
    ok(load(h,bytes(dirty),len(dirty)))
    check(state_time()==(1,4) and drain()==pending_stress,'Restart fixture has prior time, fractional carry and real queued outputs')
    ok(load(h,bytes(dirty),len(dirty)))
    ok(restart(h));restarted=save()
    check(state_time()==(0,0) and drain()==[],'Power restart zeros native timing and discards old output events')
    ok(get_input(h,0o32,C.byref(held)))
    check(bool(held.value&0o20000),'Power restart releases old PRO input')
    check(restarted[CORE_START+CENTRAL_BYTES:CORE_END]==dirty[CORE_START+CENTRAL_BYTES:CORE_END],
          'Power restart retains all physical erasable, including E0 interrupt storage and switched core')
    check(erasable_word(restarted,0,0)==0 and erasable_word(restarted,0,5)==0o4000,
          'Power restart clears the old accumulator and enters the octal 4000 hardware restart vector')
    check(validate(h,restarted,len(restarted))==0,'Power restart snapshot passes native validation')
    ok(cycles(h,12));after_restart=save()
    check(erasable_word(after_restart,0,0o320)==10,'Unchanged LM131R1 restart code increments the retained REDOCTR')
    # A new context in the same DLL must reset shared upstream peripheral statics.
    destroy(h);h=None;h=new();fresh=save()
    check(restarted[152:CORE_START+CENTRAL_BYTES]==fresh[152:CORE_START+CENTRAL_BYTES] and restarted[CORE_END:]==fresh[CORE_END:],
          'Power restart resets all serialized volatile state and preserves the exact fixed rope and parity')
    ok(cycles(h,1234));destroy(h);h=None;h=new()
    check(save()==fresh,'Destroy/create resets the shared upstream static peripheral state')
    # Save at every machine boundary, including early-return phases where the
    # unchanged CPU legitimately has an unserviced ScalerCounter>=80.
    startup_cycles=4096
    for current in range(1,startup_cycles+1):
        ok(cycles(h,1));n=size(h)
        if not n:raise AssertionError(f'Valid state at cycle{current} cannot be saved: '+error().decode())
        buf=C.create_string_buffer(n);ok(save_(h,buf,n));saved=buf.raw
        ok(validate(h,saved,n));ok(load(h,saved,n));check_buffer=C.create_string_buffer(n);ok(save_(h,check_buffer,n))
        if check_buffer.raw!=saved:raise AssertionError(f'Startup cycle{current} did not restore canonically')
    check(True,'Every startup machine-cycle boundary saves/validates/loads canonically across4096 cycles')
    destroy(h);h=None;h=new()
    backlog_count=196609;limit=262144
    for i in range(backlog_count):ok(input_(h,0o166,i&0o77777,0o77777))
    backlog=save();ok(load(h,backlog,len(backlog)))
    for i in range(backlog_count,limit):ok(input_(h,0o166,i&0o77777,0o77777))
    check(True,'Restored non-power-of-two backlog grows to the exact262144-event limit')
    check(input_(h,0o166,123,0o77777)<0,'One event beyond the declared queue limit reports a fault')
    faulted=save()
    check(validate(h,faulted,len(faulted))<0 and load(h,faulted,len(faulted))<0,
          'Faulted diagnostic checkpoints are rejected before usable-state restore')
    check(save()==faulted,'Rejected faulted checkpoint leaves live diagnostic state unchanged')
    check(key(h,0,0)<0,'Input mutations are rejected on a faulted live context')
    ok(load(h,backlog,len(backlog)));ok(key(h,0,0))
    check(True,'A valid pre-fault checkpoint restores and PRO release succeeds')
    report={'schemaVersion':1,'result':'PASS','checks':checks,'checkCount':len(checks),'flightPadloadApplied':False,
        'cyclePeriodNanoseconds':'11718.75','cliFrameEquivalent':True,'deterministicTraceEvents':len(trace),
        'lampFrame':frame,'checkpointBytes':len(checkpoint),'checkpointSha256':hashlib.sha256(checkpoint).hexdigest(),
        'replayedCheckpointSha256':hashlib.sha256(final).hexdigest(),'replayOutputEvents':len(first_events),
        'syntheticPeripheralStressEvents':len(stress_events),'syntheticPeripheralStressReplayPassed':True,
        'startupCycleBoundaryCheckpointCount':startup_cycles,'restoredQueueLimitTested':limit,'faultedCheckpointLoadRejected':True,
        'authoritativeCheckpointTimingValidated':True,
        'powerRestartRetainsPhysicalErasable':True,'powerRestartExecutesLm131r1Vector':True,
        'build':json.loads((build/'stepped/build.json').read_text(encoding='utf-8-sig'))}
    report_path.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'result':'PASS','checks':len(checks),'traceEvents':len(trace),'checkpointBytes':len(checkpoint),'replayEvents':len(first_events)}))
finally:
    if h:destroy(h)

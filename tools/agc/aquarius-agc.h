/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef AQUARIUS_AGC_H
#define AQUARIUS_AGC_H
#include <stdint.h>
#ifdef _WIN32
#define AAGC_API __declspec(dllexport)
#else
#define AAGC_API
#endif
#ifdef __cplusplus
extern "C" {
#endif
/* ABI1. Cdecl. One active context, on its creating thread. No mission padload.
 * Mutations return0 on success, negative on failure. PollOutput returns1/0.
 * Error text is borrowed until the next call. Validate/Load stage all data.
 * A machine cycle is46875 quarter-nanoseconds (12/1024000 seconds).
 */
AAGC_API uint32_t Aagc_GetAbiVersion(void);
AAGC_API const char* Aagc_LastError(void);
AAGC_API void* Aagc_Create(const char* rope_path_utf8);
AAGC_API void Aagc_Destroy(void* handle);
/* Start a new power epoch at 04000, retaining the exact rope and erasable core.
 * The caller accounts for time spent without power and the startup inhibit. */
AAGC_API int Aagc_ColdRestart(void* handle);
AAGC_API int Aagc_StepCycles(void* handle,uint64_t cycles);
AAGC_API int Aagc_StepNanoseconds(void* handle,uint64_t nanoseconds);
AAGC_API int Aagc_StepSeconds(void* handle,double seconds);
AAGC_API int Aagc_SetInput(void* handle,uint32_t channel,uint32_t value,uint32_t mask);
AAGC_API int Aagc_GetInput(void* handle,uint32_t channel,uint32_t* value);
/* code0=PRO (active-low, held); other codes are ordinary DSKY codes.
 * Ordinary release changes no CPU input, matching upstream yaDSKY. */
AAGC_API int Aagc_SetKey(void* handle,uint32_t code,uint32_t pressed);
AAGC_API int Aagc_PollOutput(void* handle,uint32_t* channel,uint32_t* value);
AAGC_API int Aagc_PollOutputAt(void* handle,uint32_t* channel,uint32_t* value,uint64_t* cycle);
AAGC_API int Aagc_GetDsky(void* handle,uint32_t* rows16,uint32_t* channel11,
                        uint32_t* channel13,uint32_t* channel163,uint64_t* cycles);
AAGC_API int Aagc_GetTiming(void* handle,uint64_t* cycles,uint32_t* quarter_ns_remainder);
AAGC_API uint32_t Aagc_CheckpointSize(void* handle);
AAGC_API int Aagc_Save(void* handle,void* destination,uint32_t size);
AAGC_API int Aagc_ValidateCheckpoint(void* handle,const void* bytes,uint32_t size);
/* Returns authoritative staged payload timing, never wrapper metadata/live time.
 * On failure neither output nor any live state is changed. */
AAGC_API int Aagc_GetCheckpointTiming(void* handle,const void* bytes,uint32_t size,
                                     uint64_t* cycles,uint32_t* quarter_ns_remainder);
AAGC_API int Aagc_Load(void* handle,const void* bytes,uint32_t size);
/* Same upstream unprogrammed-counter interface, useful for future IMU models. */
AAGC_API int Aagc_IncrementCounter(void* handle,uint32_t counter,uint32_t increment_type);
#ifdef __cplusplus
}
#endif
#endif

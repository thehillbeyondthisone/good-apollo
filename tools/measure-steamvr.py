"""Read SteamVR compositor timing as a background client; never change settings.

ABI: Valve openvr_capi.h, IVRCompositor_029 (read-only slots10,11,13,24).
https://github.com/ValveSoftware/openvr/blob/master/headers/openvr_capi.h
"""
import argparse
import ctypes as c
import datetime as dt
import json
import math
from pathlib import Path
import time

class Pose(c.Structure):
    _fields_ = [('matrix', c.c_float * 12), ('velocity', c.c_float * 3),
                ('angular_velocity', c.c_float * 3), ('tracking_result', c.c_int32),
                ('valid', c.c_uint8), ('connected', c.c_uint8)]

class Timing(c.Structure):
    _fields_ = [(name, c.c_uint32) for name in
                ['size', 'index', 'presents', 'mispresented', 'dropped', 'reprojection_flags']]
    _fields_ += [('system_seconds', c.c_double)]
    _fields_ += [(name, c.c_float) for name in
                ['pre_gpu', 'post_gpu', 'total_gpu', 'compositor_gpu', 'compositor_cpu',
                 'compositor_idle_cpu', 'client_interval', 'present_cpu', 'wait_present_cpu',
                 'submit_ms', 'wait_poses_ms', 'poses_ready_ms', 'frame_ready_ms',
                 'update_start_ms', 'update_end_ms', 'render_start_ms']]
    _fields_ += [('head_pose', Pose), ('vsyncs_ready', c.c_uint32),
                ('vsyncs_first_view', c.c_uint32), ('transfer_latency_ms', c.c_float)]

COUNTERS = ['pid', 'presents', 'dropped', 'reprojected', 'startup_presents',
            'startup_dropped', 'startup_reprojected', 'loading_events', 'loading_presents',
            'loading_dropped', 'loading_reprojected', 'timeout_events', 'timeout_presents',
            'timeout_dropped', 'timeout_reprojected', 'submits']
SUMS = ['compositor_cpu_ms', 'compositor_gpu_ms', 'target_frame_time_sum_raw', 'application_cpu_ms',
        'application_gpu_ms']

class Stats(c.Structure):
    _fields_ = [(name, c.c_uint32) for name in COUNTERS]
    _fields_ += [(name, c.c_double) for name in SUMS]
    _fields_ += [('depth_frames', c.c_uint32)]

def describe(values):
    values = sorted(v for v in values if math.isfinite(v) and v >= 0)
    return dict(samples=len(values), mean=sum(values)/len(values),
                p95=values[min(len(values)-1, int(.95*len(values)))], max=values[-1]) if values else dict(samples=0)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--duration', type=float, default=60)
    parser.add_argument('--pid', type=int, required=True, help='Expected Aquarius scene process')
    parser.add_argument('--output', type=Path, default=Path('output/steamvr-compositor.json'))
    parser.add_argument('--dll', default=r'C:\Program Files (x86)\Steam\steamapps\common\SteamVR\bin\win64\openvr_api.dll')
    args = parser.parse_args()
    assert c.sizeof(Pose) == 80 and c.sizeof(Timing) == 192 and c.sizeof(Stats) == 112
    if not 0 <= args.duration <= 600: raise ValueError('Duration must be within0..600seconds')
    lib = c.WinDLL(args.dll)
    lib.VR_InitInternal2.argtypes = [c.POINTER(c.c_int), c.c_int, c.c_char_p]
    lib.VR_InitInternal2.restype = c.c_uint32
    lib.VR_GetGenericInterface.argtypes = [c.c_char_p, c.POINTER(c.c_int)]
    lib.VR_GetGenericInterface.restype = c.c_void_p
    error = c.c_int(0)
    lib.VR_InitInternal2(c.byref(error), 3, None)  # Background, no graphics/focus.
    if error.value: raise RuntimeError(f'OpenVR background initialization failed:{error.value}')
    try:
        table = lib.VR_GetGenericInterface(b'FnTable:IVRCompositor_029', c.byref(error))
        if not table or error.value: raise RuntimeError(f'Compositor029 unavailable:{error.value}')
        def slot(index, result, *parameters):
            pointer = c.c_void_p.from_address(table + index*c.sizeof(c.c_void_p)).value
            return c.WINFUNCTYPE(result, *parameters)(pointer)
        get_timings = slot(11, c.c_uint32, c.POINTER(Timing), c.c_uint32)
        get_stats = slot(13, None, c.POINTER(Stats), c.c_uint32)
        get_pid = slot(24, c.c_uint32)
        def read_stats():
            stats = Stats()
            get_stats(c.byref(stats), c.sizeof(stats))
            if stats.pid != args.pid or get_pid() != args.pid:
                raise RuntimeError(f'Compositor scene changed: expected{args.pid},stats{stats.pid},focus{get_pid()}')
            return stats
        read_stats()  # Validate the scene before collecting any history.
        history = (Timing * 120)()
        for timing in history: timing.size = c.sizeof(Timing)
        initial_count = get_timings(history, len(history))
        initial_indices = {timing.index for timing in history[:initial_count]}
        before = read_stats()
        frames = {}
        started = time.monotonic()
        started_utc = dt.datetime.now(dt.timezone.utc).isoformat()
        while True:
            buffer = (Timing * 120)()
            for timing in buffer: timing.size = c.sizeof(Timing)
            count = get_timings(buffer, len(buffer))
            for timing in buffer[:count]:
                if timing.index in initial_indices: continue
                frames[timing.index] = dict(index=timing.index, gpuMs=timing.total_gpu,
                    compositorGpuMs=timing.compositor_gpu, clientIntervalMs=timing.client_interval,
                    presents=timing.presents, dropped=timing.dropped,
                    mispresented=timing.mispresented, reprojectionFlags=timing.reprojection_flags,
                    headPoseValid=bool(timing.head_pose.valid))
            elapsed = time.monotonic() - started
            if elapsed >= args.duration: break
            time.sleep(min(.25, args.duration-elapsed))
        after = read_stats()
        deltas = {key: getattr(after,key)-getattr(before,key) for key in COUNTERS[1:]+SUMS+['depth_frames']}
        report = dict(schemaVersion=1, kind='SteamVR compositor read-only background measurement',
            interface='IVRCompositor_029', startedUtc=started_utc, durationSeconds=elapsed,
            scenePid=args.pid, counters=deltas, sampledFrames=len(frames),
            gpuMs=describe([f['gpuMs'] for f in frames.values()]),
            compositorGpuMs=describe([f['compositorGpuMs'] for f in frames.values()]),
            clientIntervalMs=describe([f['clientIntervalMs'] for f in frames.values()]),
            submittedFramesPerSecond=deltas['submits']/elapsed if elapsed else 0,
            reprojectedFraction=deltas['reprojected']/deltas['presents'] if deltas['presents'] else None,
            droppedFraction=deltas['dropped']/deltas['presents'] if deltas['presents'] else None,
            scope='Compositor counters for the validated Aquarius PID; does not measure wireless transport quality or every physical control.',
            source='https://github.com/ValveSoftware/openvr/blob/master/headers/openvr_capi.h')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
        print(json.dumps(report, indent=2))
    finally:
        lib.VR_ShutdownInternal()

if __name__ == '__main__': main()

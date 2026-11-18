"""Check shipped PCM, loop seams, radio provenance and engine audition levels."""
from pathlib import Path
import hashlib
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
PALETTE = ROOT / "assets/audio/cabin"
manifest = json.loads((PALETTE / "manifest.json").read_text())
checks = []


def check(condition, description):
    checks.append({"pass": bool(condition), "check": description})


def read(path):
    with wave.open(str(path), "rb") as audio:
        rate = audio.getframerate()
        width = audio.getsampwidth()
        channels = audio.getnchannels()
        assert width == 2
        x = np.frombuffer(audio.readframes(audio.getnframes()), "<i2").reshape(-1, channels).astype(np.float64) / 32768
    return x, rate


def db(x):
    return round(float(20 * np.log10(max(x, 1e-9))), 2)


loops = []
for name, asset in manifest["assets"].items():
    path = PALETTE / asset["file"]
    check(hashlib.sha256(path.read_bytes()).hexdigest() == asset["sha256"], f"Manifest bytes: {name}")
    x, rate = read(path)
    check(rate == 48000 and x.shape[1] == 1 and np.max(np.abs(x)) < .72 and np.max(np.abs(x)) > .01, f"Usable mono PCM and unclipped headroom: {name}")
    if asset["loop"]:
        join = abs(float(x[-1, 0] - x[0, 0]))
        ordinary = float(np.quantile(np.abs(np.diff(x[:, 0])), .995))
        check(join < ordinary * 2, f"Loop join is within ordinary signal changes: {name}")
        loops.append({"name": name, "boundaryStep": round(join, 7), "ordinary995Step": round(ordinary, 7)})

for directory in ["kerwin-co2", "mcc5", "odyssey"]:
    folder = PALETTE.parent / directory
    original = json.loads((folder / "manifest.json").read_text())
    for cue in original["clips"].values():
        check(hashlib.sha256((folder / cue["file"]).read_bytes()).hexdigest() == cue["sha256"], f"Original radio recording unchanged: {directory}/{cue['file']}")

demo, rate = read(ROOT / "output/aquarius-audio-comparison.wav")
check(demo.shape[1] == 2 and len(demo) / rate > 37.9, "Complete stereo engine audition")
check(np.max(np.abs(demo)) < .9, "Engine mix does not clip")
segments = []
for title, start, end in [("Original procedural", 0, 4.8), ("New cabin", 5, 17),
                           ("CAPCOM with cabin", 18, 25.5), ("Spin-down", 30, 32),
                           ("Unpowered cabin", 35, 37.5)]:
    x = demo[int(start * rate):int(end * rate)]
    segments.append({"name": title, "rmsDbfs": db(np.sqrt(np.mean(x*x))), "peakDbfs": db(np.max(np.abs(x)))})
check(segments[-1]["rmsDbfs"] < -70, "Unpowered room becomes silent after coast-down")
# Use isolated left/right mechanisms after shutdown; a continuously running
# right-side fan would bias a whole-window stereo RMS comparison.
for start, end, louder in [(33.00, 33.4, 0), (34.20, 34.7, 1)]:
    x = demo[int(start*rate):int(end*rate)]
    rms = np.sqrt(np.mean(x*x, axis=0))
    check(rms[louder] > rms[1-louder]*1.1, f"Physical click is heard on correct stereo side at {start}s")
report = {"result": "PASS" if all(c["pass"] for c in checks) else "FAIL", "checks": len(checks),
          "failures": [c["check"] for c in checks if not c["pass"]], "loops": loops,
          "audition": {"durationSeconds": round(len(demo)/rate, 3), "sampleRate": rate,
                       "peakDbfs": db(np.max(np.abs(demo))), "segments": segments},
          "headsetListeningVerified": False,
          "scope": "Signal and runtime evidence; not a subjective listening review"}
(ROOT / "reference/audio-signal-quality.json").write_text(json.dumps(report, indent=2)+"\n")
print(json.dumps(report, indent=2))
raise SystemExit(0 if report["result"] == "PASS" else 1)

"""Build Aquarius' CC0 sound palette. Requires numpy and ffmpeg; no network.

Source archives/previews live in tmp/audio-sources. The manifest records the
exact source bytes, edits and output hashes. These are designed proxies, not
recordings of flight hardware. Run --inspect to inspect transient locations.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tmp/audio-sources"
OUT = ROOT / "assets/audio/cabin"
RATE = 48000


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decode(path):
    result = subprocess.run([str(FFMPEG), "-v", "error", "-i", str(path),
                             "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"],
                            check=True, capture_output=True)
    return np.frombuffer(result.stdout, dtype="<f4").astype(np.float64)


def bandlimit(x, high=70, low=9000):
    # Smooth spectral filters; loop signals stay periodic through filtering.
    freq = np.fft.rfftfreq(len(x), 1 / RATE)
    response = (freq / np.maximum(freq + high, 1)) ** 2
    response *= 1 / np.sqrt(1 + (freq / low) ** 8)
    return np.fft.irfft(np.fft.rfft(x - np.mean(x)) * response, n=len(x))


def fade(x, attack=.002, release=.025):
    x = x.copy()
    for count, beginning in [(min(int(attack * RATE), len(x)//2), True),
                              (min(int(release * RATE), len(x)//2), False)]:
        if count:
            ramp = np.sin(np.linspace(0, np.pi/2, count)) ** 2
            if beginning:
                x[:count] *= ramp
            else:
                x[-count:] *= ramp[::-1]
    return x


def seamless(x, overlap=.5):
    count = min(int(overlap * RATE), len(x)//4)
    # Remove the overlapped tail. End of the output joins the beginning of the
    # unchanged middle, avoiding a boundary fade or a level dip each cycle.
    ramp = np.linspace(0, 1, count, endpoint=False)
    join = x[-count:] * (1-ramp) + x[:count] * ramp
    return np.concatenate([x[count:-count], join])


def events(x):
    windows = np.array([np.max(np.abs(x[i:i+480])) for i in range(0, len(x), 480)])
    indices = np.where(windows > max(windows)*.28)[0]
    groups = []
    for i in indices:
        if not groups or i-groups[-1][-1] > 12:
            groups.append([i])
        else:
            groups[-1].append(i)
    return [(round(g[0]*.01, 2), round(g[-1]*.01+.01, 2)) for g in groups]


def make(name, source, start=0, duration=None, high=70, low=9000,
         peak=-3, rms=None, loop=False, speed=1.0):
    path = SOURCE / source
    x = decode(path)
    end = len(x) if duration is None else int((start+duration)*RATE)
    x = x[int(start*RATE):end]
    if speed != 1:
        x = np.interp(np.arange(0, len(x)-1, speed), np.arange(len(x)), x)
    x = bandlimit(x, high, low)
    if loop:
        x = seamless(x)
    else:
        # Preserve the preattack but discard encoder padding/silent handles.
        active = np.where(np.abs(x) > max(np.max(np.abs(x)) * .008, .0001))[0]
        if len(active):
            x = x[max(0, active[0]-240):min(len(x), active[-1]+1200)]
        x = fade(x)
    gain = 10 ** (peak/20) / max(np.max(np.abs(x)), 1e-9)
    if rms is not None:
        gain = min(gain, 10 ** (rms/20) / max(np.sqrt(np.mean(x*x)), 1e-9))
    x *= gain
    target = OUT / (name + ".wav")
    with wave.open(str(target), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(RATE)
        audio.writeframes(np.round(x*32767).astype("<i2").tobytes())
    entry = {"file": target.name, "source": source, "sourceSha256": sha(path),
             "sha256": sha(target), "durationSeconds": round(len(x)/RATE, 6),
             "peakDbfs": round(20*np.log10(max(np.max(np.abs(x)), 1e-9)), 2),
             "rmsDbfs": round(20*np.log10(max(np.sqrt(np.mean(x*x)), 1e-9)), 2),
             "loop": loop, "edit": {"startSeconds": start, "durationSeconds": duration,
             "highpassHz": high, "lowpassHz": low, "speed": speed,
             "seamCrossfadeSeconds": .5 if loop else 0,
             "mono": True, "sampleRate": RATE}}
    ASSETS[name] = entry


def radio_gains():
    gains = {}
    for folder in ["kerwin-co2", "mcc5", "odyssey"]:
        for path in sorted((OUT.parent / folder).glob("*.wav")):
            x = decode(path)
            # Speech gating keeps pauses and archival tape silence from causing
            # aggressive makeup gain. Preserve source files byte for byte.
            blocks = np.array([np.sqrt(np.mean(x[i:i+2400]**2))
                               for i in range(0, len(x), 2400)])
            active = blocks[blocks > np.max(blocks)*.12]
            level = 20*np.log10(max(np.sqrt(np.mean(active**2)), 1e-9))
            peak = 20*np.log10(max(np.max(np.abs(x)), 1e-9))
            gains[f"{folder}/{path.name}"] = round(float(min(8, -19-level, -3-peak)), 2)
    return gains


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--ffmpeg", type=Path)
parser.add_argument("--inspect", action="store_true")
args = parser.parse_args()
FFMPEG = args.ffmpeg or next((ROOT / "tmp/kerwin-ffmpeg").rglob("ffmpeg.exe"))
if args.inspect:
    for name in ["toggles", "water", "velcro"]:
        x = decode(SOURCE / (name+".mp3"))
        print(name, len(x)/RATE, events(x))
    raise SystemExit()
OUT.mkdir(parents=True, exist_ok=True)
ASSETS = {}

# Four independently recorded switches, selected from the denoised close-mic
# recording. Each remains a complete mechanical impulse, with a short tail.
toggle_events = events(decode(SOURCE / "toggles.mp3"))
for i, (start, end) in enumerate(toggle_events[:4]):
    make(f"toggle_{i+1}", "toggles.mp3", max(0, start-.015), end-start+.075, low=7600)

for name, prefix, numbers in [
    ("button", "click", [1, 2, 4]), ("detent", "tick", [1, 2, 4]),
    ("breaker", "switch", [1, 3, 4]), ("release", "switch", [2, 5]),
]:
    for i, number in enumerate(numbers):
        make(f"{name}_{i+1}", f"interface-sounds/Audio/{prefix}_{number:03}.ogg", low=6500)
for i in range(3):
    make(f"latch_{i+1}", f"impact-sounds/Audio/impactMetal_light_{i:03}.ogg", low=4800, speed=.85)
    make(f"body_{i+1}", f"impact-sounds/Audio/impactPlate_light_{i:03}.ogg", high=95, low=2300, peak=-9, speed=.84)
    make(f"fabric_{i+1}", f"impact-sounds/Audio/footstep_carpet_{i:03}.ogg", high=160, low=4800, peak=-7)
make("fastener", "velcro.mp3", high=150, low=6400, peak=-6)
make("ventilation", "fan.mp3", 12, 21, high=100, low=4800, rms=-20, loop=True)
make("pump", "fan.mp3", 42, 19, high=70, low=650, rms=-23, speed=.76, loop=True)
make("water", "dispenser.mp3", 1.6, 2.8, high=450, low=6500, rms=-23, loop=True)

manifest = {
    "schemaVersion": 1,
    "title": "Aquarius cabin sound design — CC0 palette",
    "qualification": "Designed acoustic proxies; not Apollo hardware recordings. Existing archival radio retains its own source licenses.",
    "license": "CC0-1.0", "licenseUrl": "https://creativecommons.org/publicdomain/zero/1.0/",
    "sources": [
        {"creator": "Kenney", "title": "Interface Sounds", "url": "https://kenney.nl/assets/interface-sounds", "archive": "interface-sounds.zip", "sha256": sha(SOURCE / "interface-sounds.zip")},
        {"creator": "Kenney", "title": "Impact Sounds", "url": "https://kenney.nl/assets/impact-sounds", "archive": "impact-sounds.zip", "sha256": sha(SOURCE / "impact-sounds.zip")},
        {"creator": "loganzsound", "title": "Small Toggle Switch", "url": "https://freesound.org/people/loganzsound/sounds/877305/", "download": "https://cdn.freesound.org/previews/877/877305_16682330-hq.mp3"},
        {"creator": "giddster", "title": "Fan, setting 3", "url": "https://freesound.org/people/giddster/sounds/437340/", "download": "https://cdn.freesound.org/previews/437/437340_1738686-hq.mp3"},
        {"creator": "Rudmer_Rotteveel", "title": "Velcro Pull 01", "url": "https://freesound.org/people/Rudmer_Rotteveel/sounds/536231/", "download": "https://cdn.freesound.org/previews/536/536231_4921277-hq.mp3"},
        {"creator": "COSP_LCS13", "title": "Water dispenser-16.wav", "url": "https://freesound.org/people/COSP_LCS13/sounds/186235/", "download": "https://cdn.freesound.org/previews/186/186235_3444872-hq.mp3"},
    ],
    "assets": ASSETS, "radioGainDb": radio_gains(),
}
(OUT / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
print(json.dumps({"assets": len(ASSETS), "radioClips": len(manifest["radioGainDb"]),
                  "bytes": sum(p.stat().st_size for p in OUT.glob("*.wav"))}))

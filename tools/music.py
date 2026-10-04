#!/usr/bin/env python3
"""Synthesises Silly Kitty's two chiptune music loops and encodes them to MP3.

Four classic chip channels (two pulse waves, a triangle bass, a noise drum
kit) are rendered with the standard library into a buffer exactly one loop
long. Note tails that run past the end wrap around to the start, so the last
sample flows into the first and the loop is seamless.

MP3 encoding adds silence before and after the audio. lame records how much in
its LAME/Xing tag, and Godot's decoder (like ffmpeg) trims it, so the decoded
file is exactly one loop and Godot's plain whole-file loop is seamless. Never
pass lame -t: it drops that tag. After encoding, the file is decoded (gapless)
to check it is exactly one loop long, and the loop is switched on in its
.import file when the output is inside the Godot project.
Usage (from repo root): python3 tools/music.py [out_dir]   default: sillykitty/audio/music
Needs: lame and ffmpeg on PATH (Homebrew: brew install lame ffmpeg). Output is
byte-identical on every run (constant bitrate, no ID3 tags).
"""
import math
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

RATE = 44100
PEAK = 0.8
NOTE_NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def freq(note):
    """'C5', 'F#4', 'Bb3' -> Hz (A4 = 440)."""
    name, octave = note[:-1], int(note[-1])
    semitone = NOTE_NAMES[name[0]] + name.count("#") - name.count("b")
    return 440.0 * 2 ** ((semitone + 12 * (octave + 1) - 69) / 12)


def parse(pattern):
    """Space-separated steps: a note starts, '-' holds the previous note, '.' is a rest.
    Returns (note, start_step, length_steps) tuples."""
    events, steps = [], pattern.split()
    for i, token in enumerate(steps):
        if token in ("-", "."):
            continue
        length = 1
        while i + length < len(steps) and steps[i + length] == "-":
            length += 1
        events.append((token, i, length))
    return events, len(steps)


def pulse(phase, duty):
    return 1.0 if phase % 1.0 < duty else -1.0


def triangle(phase):
    return 4.0 * abs(phase % 1.0 - 0.5) - 1.0


def add_tone(buf, start, length, hz, wave_fn, volume, attack=0.005, decay=0.0, vibrato=0.0):
    """Adds a tone with a short attack and release; samples past the end wrap to the start."""
    n, size = int(length), len(buf)
    release = min(int(0.03 * RATE), n // 3)
    a = max(1, int(attack * RATE))
    phase = 0.0
    for i in range(n):
        env = min(1.0, i / a, (n - i) / max(1, release))
        if decay:
            env *= math.exp(-decay * i / RATE)
        vib = 1.0 + vibrato * math.sin(2 * math.pi * 5.5 * i / RATE) * min(1.0, i / (0.15 * RATE))
        phase += hz * vib / RATE
        buf[(start + i) % size] += wave_fn(phase) * env * volume


def add_noise(buf, start, seconds, volume, decay, rng, bright):
    """Noise burst (snare/hat); `bright` 0..1 thins out the low end."""
    n, size, lp = int(seconds * RATE), len(buf), 0.0
    for i in range(n):
        x = rng.uniform(-1.0, 1.0)
        lp += (1.0 - bright) * (x - lp)
        buf[(start + i) % size] += (x - lp if bright > 0 else lp) * math.exp(-decay * i / RATE) * volume


def add_kick(buf, start, volume):
    n, size, phase = int(0.16 * RATE), len(buf), 0.0
    for i in range(n):
        phase += (150.0 * math.exp(-18.0 * i / RATE) + 45.0) / RATE
        buf[(start + i) % size] += math.sin(2 * math.pi * phase) * math.exp(-14.0 * i / RATE) * volume


def render(track, rng):
    step = 60.0 / track["bpm"] / 4  # 16th notes
    total_steps = None
    voices = []
    for key, wave_fn, volume, kwargs in (
        ("lead", lambda p: pulse(p, 0.25), 0.22, {"vibrato": 0.006}),
        ("harmony", lambda p: pulse(p, 0.5), 0.10, {"decay": 2.5}),
        ("bass", triangle, 0.38, {}),
    ):
        events, steps = parse(" ".join(track[key]))
        total_steps = steps if total_steps is None else total_steps
        if steps != total_steps:
            raise ValueError(f"{track['name']}: '{key}' is {steps} steps, expected {total_steps}")
        voices.append((events, wave_fn, volume, kwargs))
    size = int(round(total_steps * step * RATE))
    buf = [0.0] * size
    for events, wave_fn, volume, kwargs in voices:
        for note, start, length in events:
            add_tone(buf, int(round(start * step * RATE)), length * step * RATE * 0.95, freq(note), wave_fn, volume, **kwargs)
    drums = " ".join(track["drums"]).split()
    if len(drums) != total_steps:
        raise ValueError(f"{track['name']}: 'drums' is {len(drums)} steps, expected {total_steps}")
    for i, hit in enumerate(drums):
        at = int(round(i * step * RATE))
        if hit == "k":
            add_kick(buf, at, 0.55)
        elif hit == "s":
            add_noise(buf, at, 0.14, 0.30, 22.0, rng, 0.0)
        elif hit == "h":
            add_noise(buf, at, 0.04, 0.12, 80.0, rng, 0.8)
    return buf


def to_pcm(samples):
    peak = max(abs(s) for s in samples) or 1.0
    return [int(s / peak * PEAK * 32767) for s in samples]


def write_wav(path, pcm):
    frames = b"".join(struct.pack("<h", v) for v in pcm)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)


# Title: a gentle, curious 96 BPM tune (4 bars, repeated with a variation).
TITLE = {
    "name": "title", "bpm": 96,
    "lead": [
        "E5 - - - G5 - E5 - D5 - - - C5 - D5 -", "E5 - - - G5 - A5 - G5 - - - - - . .",
        "A5 - - - G5 - E5 - D5 - - - E5 - C5 -", "D5 - - - - - - - . . . . . . . .",
        "E5 - - - G5 - E5 - D5 - - - C5 - D5 -", "E5 - - - G5 - A5 - C6 - - - - - . .",
        "A5 - - - G5 - E5 - D5 - - - E5 - D5 -", "C5 - - - - - - - . . . . . . . .",
    ],
    "harmony": [
        "C4 . E4 . G4 . E4 . C4 . E4 . G4 . E4 .", "A3 . C4 . E4 . C4 . A3 . C4 . E4 . C4 .",
        "F3 . A3 . C4 . A3 . F3 . A3 . C4 . A3 .", "G3 . B3 . D4 . B3 . G3 . B3 . D4 . B3 .",
        "C4 . E4 . G4 . E4 . C4 . E4 . G4 . E4 .", "A3 . C4 . E4 . C4 . A3 . C4 . E4 . C4 .",
        "F3 . A3 . C4 . A3 . G3 . B3 . D4 . B3 .", "C4 . E4 . G4 . E4 . C4 . E4 . G4 . E4 .",
    ],
    "bass": [
        "C3 - - - . . . . G2 - - - . . . .", "A2 - - - . . . . E2 - - - . . . .",
        "F2 - - - . . . . C3 - - - . . . .", "G2 - - - . . . . G2 - - - . . . .",
        "C3 - - - . . . . G2 - - - . . . .", "A2 - - - . . . . E2 - - - . . . .",
        "F2 - - - . . . . G2 - - - . . . .", "C3 - - - . . . . C3 - - - . . . .",
    ],
    "drums": ["k . . . h . . . s . . . h . . ."] * 8,
}

# Play: a bouncy 132 BPM chase tune (8 bars).
PLAY = {
    "name": "play", "bpm": 132,
    "lead": [
        "C5 . E5 . G5 . E5 . C6 - - - G5 . E5 .", "F5 . A5 . C6 . A5 . G5 - - - . . . .",
        "E5 . G5 . C6 . G5 . A5 - G5 - E5 - D5 -", "D5 . F5 . A5 . F5 . G5 - - - . . . .",
        "C5 . E5 . G5 . E5 . C6 - - - G5 . E5 .", "F5 . A5 . C6 . D6 . E6 - - - . . C6 .",
        "D6 - C6 - A5 - G5 - F5 - E5 - D5 - B4 -", "C5 - - - . . G4 . C5 - - - . . . .",
    ],
    "harmony": [
        "E4 . G4 . E4 . G4 . E4 . G4 . E4 . G4 .", "F4 . A4 . F4 . A4 . E4 . G4 . E4 . G4 .",
        "E4 . G4 . E4 . G4 . F4 . A4 . F4 . A4 .", "F4 . A4 . F4 . A4 . D4 . G4 . D4 . G4 .",
        "E4 . G4 . E4 . G4 . E4 . G4 . E4 . G4 .", "F4 . A4 . F4 . A4 . G4 . C5 . G4 . C5 .",
        "F4 . A4 . F4 . A4 . D4 . F4 . D4 . G4 .", "E4 . G4 . E4 . G4 . E4 . G4 . E4 . G4 .",
    ],
    "bass": [
        "C3 . C3 . G2 . G2 . C3 . C3 . G2 . G2 .", "F2 . F2 . C3 . C3 . G2 . G2 . D3 . D3 .",
        "A2 . A2 . E2 . E2 . F2 . F2 . C3 . C3 .", "D3 . D3 . A2 . A2 . G2 . G2 . B2 . B2 .",
        "C3 . C3 . G2 . G2 . C3 . C3 . G2 . G2 .", "F2 . F2 . C3 . C3 . E2 . E2 . G2 . G2 .",
        "F2 . F2 . G2 . G2 . E2 . E2 . A2 . A2 .", "C3 . C3 . G2 . G2 . C3 . . G2 . B2 . .",
    ],
    "drums": ["k . h . s . h . k . h k s . h h"] * 7 + ["k . h . s . h . k . s . s s s s"],
}


def check_decode(ffmpeg, mp3, samples):
    """Decodes `mp3` the gapless way (as Godot does) and confirms it is exactly `samples` long."""
    raw = subprocess.run([ffmpeg, "-v", "error", "-i", str(mp3), "-f", "s16le", "-ac", "1", "-"],
                         capture_output=True, check=True).stdout
    if len(raw) // 2 != samples:
        sys.exit(f"music.py: {mp3} decodes to {len(raw) // 2} samples, expected {samples}; "
                 "is lame still writing its LAME tag?")


def write_import(mp3):
    """Switches Godot's plain loop on in <mp3>.import, keeping whatever else Godot wrote there.
    Skipped when the output is outside the Godot project."""
    path = Path(str(mp3) + ".import")
    params = {"loop": "true", "loop_offset": "0", "bpm": "0", "beat_count": "0", "bar_beats": "4"}
    project = next((d for d in Path(mp3).resolve().parents if (d / "project.godot").exists()), None)
    if project is None:
        print(f"  {mp3} is outside the Godot project; no .import written")
        return
    if path.exists():
        lines, seen = [], set()
        for line in path.read_text().splitlines():
            key = line.split("=", 1)[0]
            if key in params:
                line = f"{key}={params[key]}"
                seen.add(key)
            lines.append(line)
        lines += [f"{k}={v}" for k, v in params.items() if k not in seen]
        text = "\n".join(lines) + "\n"
    else:
        res = "res://" + Path(mp3).resolve().relative_to(project).as_posix()
        text = (f'[remap]\n\nimporter="mp3"\ntype="AudioStreamMP3"\n\n[deps]\n\nsource_file="{res}"\n\n[params]\n\n'
                + "".join(f"{k}={v}\n" for k, v in params.items()))
    path.write_text(text)


def main():
    out_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "sillykitty/audio/music")
    lame, ffmpeg = shutil.which("lame"), shutil.which("ffmpeg")
    if lame is None or ffmpeg is None:
        sys.exit("music.py: lame and ffmpeg are needed on PATH (Homebrew: brew install lame ffmpeg)")
    out_dir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(1004)
    with tempfile.TemporaryDirectory() as tmp:
        for track in (TITLE, PLAY):
            loop = to_pcm(render(track, rng))
            wav = Path(tmp) / f"{track['name']}.wav"
            write_wav(wav, loop)
            mp3 = out_dir / f"{track['name']}.mp3"
            # CBR, no ID3 tags: byte-identical output for identical input. Keep the LAME tag (no -t).
            result = subprocess.run([lame, "--quiet", "-m", "m", "-b", "96", "--noreplaygain", str(wav), str(mp3)],
                                    capture_output=True, text=True)
            if result.returncode != 0:
                sys.exit(f"music.py: lame failed for {mp3}: {result.stderr.strip()}")
            check_decode(ffmpeg, mp3, len(loop))
            write_import(mp3)
            print(f"wrote {mp3} ({len(loop) / RATE:.3f}s loop, {len(loop)} samples)")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generates the placeholder sound effects in assets/sounds as 16-bit mono
22050 Hz WAV files, each under half a second, from the Python standard
library only (no numpy). Run from the project root:

    python3 tools/gen_sounds.py

Each sound is a tiny synth patch: sine/triangle tones with an envelope, or
filtered noise. Replace the files with real recordings later; the names are
what Sfx.play() uses."""
import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")


def env(t, attack, decay, length):
    """Attack/decay envelope, 0..1."""
    if t < attack:
        return t / attack
    rest = length - attack
    return max(0.0, 1.0 - (t - attack) / max(rest, 1e-6)) ** decay


def tone(freq, length, shape="sine", attack=0.005, decay=1.5, slide=0.0, vol=0.8):
    """A single note. slide is the frequency multiplier reached at the end."""
    n = int(length * RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq * (1.0 + (slide - 1.0) * t / length) if slide else freq
        phase += 2 * math.pi * f / RATE
        if shape == "sine":
            v = math.sin(phase)
        elif shape == "tri":
            v = 2.0 / math.pi * math.asin(math.sin(phase))
        else:  # square-ish, softened
            v = math.tanh(3.0 * math.sin(phase))
        out.append(v * env(t, attack, decay, length) * vol)
    return out


def noise(length, attack=0.002, decay=2.0, vol=0.7, lowpass=0.0, seed=1):
    """A noise burst; lowpass 0..1 smooths it (1 = very muffled)."""
    rng = random.Random(seed)
    n = int(length * RATE)
    out = []
    last = 0.0
    for i in range(n):
        t = i / RATE
        v = rng.uniform(-1.0, 1.0)
        last = last * lowpass + v * (1.0 - lowpass)
        out.append(last * env(t, attack, decay, length) * vol)
    return out


def mix(*parts):
    """Sums sample lists, padding the shorter ones."""
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, v in enumerate(p):
            out[i] += v
    peak = max(1e-6, max(abs(v) for v in out))
    return [v / peak * 0.9 for v in out]


def seq(*parts):
    """Plays sample lists one after the other."""
    out = []
    for p in parts:
        out.extend(p)
    return out


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    print("wrote", path, "%.2fs" % (len(samples) / RATE))


SOUNDS = {
    # Wood or stone struck: a muffled knock with a little body.
    "chop": lambda: mix(noise(0.12, decay=3.0, lowpass=0.85, seed=3), tone(140, 0.12, "tri", slide=0.6, vol=0.5)),
    # Picking berries or grass: a soft pluck.
    "pick": lambda: mix(tone(520, 0.09, "tri", decay=2.0, slide=0.8), noise(0.04, decay=3.0, lowpass=0.6, vol=0.25, seed=5)),
    # A weapon connects: sharp and short.
    "hit": lambda: mix(noise(0.07, decay=2.5, lowpass=0.3, seed=7), tone(900, 0.06, "sine", slide=0.4, vol=0.5)),
    # Something falls: a low thump.
    "kill": lambda: mix(tone(90, 0.3, "sine", decay=1.2, slide=0.5), noise(0.1, decay=3.0, lowpass=0.9, vol=0.4, seed=9)),
    # A building tier finishes: two rising tones.
    "build_done": lambda: seq(tone(392, 0.16, "tri", decay=1.0), tone(523, 0.28, "tri", decay=1.5)),
    # A craft finishes: a bright chime.
    "craft_done": lambda: mix(tone(1047, 0.35, "sine", decay=2.0), tone(1568, 0.3, "sine", decay=2.5, vol=0.35)),
    # Level up: three rising notes.
    "level_up": lambda: seq(tone(523, 0.12, "tri", decay=1.0), tone(659, 0.12, "tri", decay=1.0), tone(784, 0.24, "tri", decay=1.5)),
    # A button press: a click.
    "ui_tap": lambda: mix(noise(0.03, decay=3.0, lowpass=0.5, seed=11), tone(1200, 0.03, "sine", vol=0.4)),
    # Taking damage: a low noise burst.
    "hurt": lambda: mix(noise(0.22, decay=1.8, lowpass=0.92, seed=13), tone(110, 0.2, "soft", slide=0.7, vol=0.5)),
    # Eating or drinking: a short blip.
    "eat": lambda: seq(tone(660, 0.07, "sine", decay=1.5), tone(880, 0.1, "sine", decay=2.0)),
}

if __name__ == "__main__":
    for name, make in SOUNDS.items():
        write(name, make())

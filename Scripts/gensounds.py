#!/usr/bin/env python3
"""Synthesize Elbowroom's five sounds: pebble, whoomp, pour, tuck,
heads-up. Organic/felt palette: filtered noise bursts and soft sine thumps,
high-passed feel, short, quiet. Pure-stdlib WAV output."""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "Sources/ElbowroomKit/Resources/Sounds"
OUT.mkdir(parents=True, exist_ok=True)
random.seed(7)


def write_wav(name, samples):
    # Normalize to -20 LUFS-ish headroom (peak ~0.35), fade edges.
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.35 / peak
    n = len(samples)
    fade = int(0.004 * RATE)
    out = []
    for i, s in enumerate(samples):
        env = min(1.0, i / fade if fade else 1.0, (n - 1 - i) / fade if fade else 1.0)
        out.append(int(max(-1, min(1, s * scale * env)) * 32767))
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(struct.pack(f"<{len(out)}h", *out))
    print(f"wrote {name}.wav ({n / RATE * 1000:.0f} ms)")


def hp_noise(dur, cutoff_mix=0.6):
    """Noise with a crude one-pole high-pass feel (>=120 Hz per spec)."""
    n = int(dur * RATE)
    prev_in = prev_out = 0.0
    out = []
    a = 0.995
    for _ in range(n):
        x = random.uniform(-1, 1)
        y = a * (prev_out + x - prev_in)
        prev_in, prev_out = x, y
        out.append(y * cutoff_mix)
    return out


def sine(freq, dur, glide=1.0):
    n = int(dur * RATE)
    phase = 0.0
    out = []
    for i in range(n):
        f = freq * (glide + (1 - glide) * (1 - i / n))
        phase += 2 * math.pi * f / RATE
        out.append(math.sin(phase))
    return out


def env_exp(samples, decay):
    return [s * math.exp(-i / (decay * RATE)) for i, s in enumerate(samples)]


def mix(*layers):
    n = max(len(l) for l in layers)
    return [sum(l[i] if i < len(l) else 0.0 for l in layers) for i in range(n)]


# pebble: a tiny wooden tick. ~90 ms.
pebble = mix(
    env_exp(sine(1900, 0.09), 0.012),
    env_exp(hp_noise(0.05, 0.5), 0.008),
    [s * 0.6 for s in env_exp(sine(950, 0.07), 0.02)],
)
write_wav("pebble", pebble)

# whoomp: a soft felt door-thud with a downward glide. ~240 ms.
whoomp = mix(
    env_exp(sine(160, 0.24, glide=0.55), 0.09),
    [s * 0.35 for s in env_exp(hp_noise(0.12, 0.4), 0.04)],
)
write_wav("whoomp", whoomp)

# pour: grain trickling into a jar, brightening as it fills. ~850 ms.
n = int(0.85 * RATE)
pour = [0.0] * n
for g in range(260):
    t0 = int((g / 260) ** 0.8 * (n - 900))
    f = 900 + 1400 * (g / 260) + random.uniform(-150, 150)
    grain = env_exp(sine(f, 0.02), 0.004)
    amp = 0.25 + 0.5 * (g / 260)
    for i, s in enumerate(grain):
        if t0 + i < n:
            pour[t0 + i] += s * amp * random.uniform(0.4, 1.0)
pour = mix(pour, [s * 0.25 for s in env_exp(hp_noise(0.85, 0.25), 0.5)])
write_wav("pour", pour)

# tuck: two soft felt steps, like something settled into place. ~260 ms.
step1 = env_exp(sine(420, 0.09, glide=0.7), 0.03)
step2 = env_exp(sine(300, 0.12, glide=0.7), 0.045)
tuck = step1 + [0.0] * int(0.05 * RATE) + step2
write_wav("tuck", tuck)

# heads-up: one round wooden knock, calm, no alarm. ~300 ms.
heads = mix(
    env_exp(sine(520, 0.3, glide=0.92), 0.07),
    [s * 0.5 for s in env_exp(sine(780, 0.12), 0.02)],
    [s * 0.3 for s in env_exp(hp_noise(0.05, 0.5), 0.006)],
)
write_wav("heads-up", heads)

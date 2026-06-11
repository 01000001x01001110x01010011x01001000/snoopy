#!/usr/bin/env python3
"""Generate the bundled preset sounds for Snoopy as 16-bit mono WAV files."""

import math
import os
import random
import struct
import wave

RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Resources", "Sounds")


def write_wav(name, samples):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(
            struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in samples
        )
        w.writeframes(frames)
    print(f"wrote {path} ({len(samples) / RATE:.2f}s)")


def silence(dur):
    return [0.0] * int(RATE * dur)


def noise_click(dur, amp, decay, lowpass=0.0):
    """Short filtered noise burst with exponential decay — a mechanical click."""
    n = int(RATE * dur)
    out = []
    prev = 0.0
    for i in range(n):
        s = random.uniform(-1, 1) * amp * math.exp(-i / (RATE * decay))
        if lowpass > 0:
            s = prev + lowpass * (s - prev)
            prev = s
        out.append(s)
    return out


def tone(freq, dur, amp, decay):
    n = int(RATE * dur)
    return [
        amp * math.sin(2 * math.pi * freq * i / RATE) * math.exp(-i / (RATE * decay))
        for i in range(n)
    ]


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    peak = max(abs(s) for s in out) or 1.0
    if peak > 0.95:
        out = [s * 0.95 / peak for s in out]
    return out


random.seed(7)

# Shutter Open: bright tick, then a slightly bigger snap — rising feel.
shutter_open = mix(
    noise_click(0.04, 0.5, 0.006),
    silence(0.05) + noise_click(0.08, 0.9, 0.012),
    silence(0.05) + tone(1800, 0.06, 0.25, 0.01),
)

# Shutter Close: bigger snap first, then a soft damped tick — falling feel.
shutter_close = mix(
    noise_click(0.08, 0.9, 0.012),
    tone(1200, 0.06, 0.25, 0.01),
    silence(0.07) + noise_click(0.05, 0.45, 0.008, lowpass=0.25),
)

# Camera Click: classic SLR — mirror slap (low thunk) + crisp shutter tick.
camera_click = mix(
    tone(140, 0.10, 0.6, 0.02),
    noise_click(0.05, 0.8, 0.008),
    silence(0.06) + noise_click(0.06, 0.6, 0.010),
    silence(0.06) + tone(2400, 0.04, 0.2, 0.006),
)

# Soft Pop: gentle rounded pop, no noise.
soft_pop = mix(
    tone(520, 0.12, 0.7, 0.025),
    tone(1040, 0.08, 0.2, 0.015),
)

# Plug In: two quick rising pops — "connected".
plug_in = mix(
    tone(600, 0.08, 0.5, 0.020),
    silence(0.07) + tone(900, 0.12, 0.5, 0.025),
)

# Plug Out: the same figure falling — "disconnected".
plug_out = mix(
    tone(900, 0.08, 0.5, 0.020),
    silence(0.07) + tone(600, 0.12, 0.5, 0.025),
)

# Charge Up: warm two-note chime (C5 -> G5) with a sparkle on top.
charge_up = mix(
    tone(523.25, 0.45, 0.50, 0.12),
    silence(0.12) + tone(783.99, 0.50, 0.45, 0.14),
    silence(0.12) + tone(1567.98, 0.30, 0.12, 0.08),
)

# Charge Full: three ascending notes (C5, E5, G5) — "all done".
charge_full = mix(
    tone(523.25, 0.30, 0.40, 0.08),
    silence(0.14) + tone(659.25, 0.30, 0.40, 0.08),
    silence(0.28) + tone(783.99, 0.45, 0.45, 0.12),
)

# Battery Low: two mellow descending notes (G4 -> C4) — gentle warning.
battery_low = mix(
    tone(392.00, 0.25, 0.45, 0.08),
    silence(0.22) + tone(261.63, 0.40, 0.50, 0.12),
)

write_wav("shutter-open.wav", shutter_open)
write_wav("shutter-close.wav", shutter_close)
write_wav("camera-click.wav", camera_click)
write_wav("soft-pop.wav", soft_pop)
write_wav("plug-in.wav", plug_in)
write_wav("plug-out.wav", plug_out)
write_wav("charge-up.wav", charge_up)
write_wav("charge-full.wav", charge_full)
write_wav("battery-low.wav", battery_low)

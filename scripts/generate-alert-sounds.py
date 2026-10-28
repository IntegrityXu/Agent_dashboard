#!/usr/bin/env python3
"""Recreate Status Board's original notification tones (44.1 kHz mono PCM)."""
from pathlib import Path
import math
import random
import struct
import wave

folder = Path(__file__).resolve().parents[1] / 'Packages/StatusBoardCore/Sources/StatusBoardDesktop/Resources'
folder.mkdir(exist_ok=True)
patterns = {
    'waiting': [(0, .17, 740), (.25, .22, 740)],
    'failed': [(0, .23, 440), (.19, .32, 330)],
}
for name, notes in patterns.items():
    duration = max(start + length for start, length, _ in notes) + .05
    samples = []
    for i in range(round(duration * 44100)):
        t, value = i / 44100, 0
        for start, length, frequency in notes:
            u = t - start
            if 0 <= u < length:
                envelope = min(1, u / .012) * min(1, (length - u) / .07) * math.exp(-3 * u / length)
                value += .24 * envelope * (math.sin(2 * math.pi * frequency * u) + .15 * math.sin(4 * math.pi * frequency * u))
        samples.append(struct.pack('<h', round(max(-1, min(1, value)) * 32767)))
    with wave.open(str(folder / (name + '.wav')), 'wb') as output:
        output.setparams((1, 2, 44100, 0, 'NONE', 'not compressed'))
        output.writeframes(b''.join(samples))

# Selected audition 05: a 650 ms wooden double tap, with unchanged pitch.
rate = 44100
duration = .65
scale = duration / .95
rng = random.Random(27)
samples = [0.0] * round(duration * rate)
for start, length, frequency, gain in [(0, .58, 650, 1), (.24, .62, 975, .75)]:
    start *= scale
    length *= scale
    offset = round((start + .02 * scale) * rate)
    for i in range(round(length * rate)):
        t = i / rate
        x = t / length
        envelope = min(1, t / .006) * math.exp(-4.8 * x) * min(1, max(0, (length - t) / (.09 * scale)))
        sound = (math.sin(2 * math.pi * frequency * t)
                 + .45 * math.exp(-8 * x) * math.sin(2 * math.pi * frequency * 1.61 * t)
                 + .08 * rng.uniform(-1, 1) * math.exp(-35 * x))
        samples[offset + i] += .25 * gain * envelope * sound
peak = max(abs(value) for value in samples)
active = [value for value in samples if abs(value) > peak * .025]
rms = math.sqrt(sum(value * value for value in active) / len(active))
gain = min(.075 / rms, .4 / peak)
pcm = b''.join(struct.pack('<h', round(max(-1, min(1, value * gain)) * 32767)) for value in samples)
with wave.open(str(folder / 'completed.wav'), 'wb') as output:
    output.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
    output.writeframes(pcm)

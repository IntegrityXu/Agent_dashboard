#!/usr/bin/env python3
"""Recreate Status Board's original notification tones (44.1 kHz mono PCM)."""
from pathlib import Path
import math
import struct
import wave

folder = Path(__file__).resolve().parents[1] / 'Packages/StatusBoardCore/Sources/StatusBoardDesktop/Resources'
folder.mkdir(exist_ok=True)
patterns = {
    'completed': [(0, .23, 660), (.18, .35, 880)],
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

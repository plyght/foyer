#!/usr/bin/env python3
"""Generate Foyer's 13 original UI sounds as CAF files.

Every sound is synthesised from scratch (additive / FM synthesis, envelopes
and a small synthetic reverb). Only the *measured metadata* of Alcove's
sounds (duration, rough peak level, mood; teardown Part G §8) informed the
targets below; no audio from Alcove is read or reused.

Output: Foyer/Resources/Sounds/<name>.caf, mono, 44.1 kHz, 16-bit big-endian
linear PCM in a Core Audio Format container ('caff' + 'desc' + 'data').

Usage: python3 scripts/generate_sounds.py [output_dir]
Requires numpy.
"""

import os
import struct
import sys

import numpy as np

SR = 44100
RNG = np.random.default_rng(20261012)

# --------------------------------------------------------------------------
# CAF writer
# --------------------------------------------------------------------------


def write_caf(path, samples):
    """Write float samples in [-1, 1] as 16-bit big-endian LPCM CAF."""
    pcm = np.clip(np.round(samples * 32767.0), -32768, 32767).astype(">i2")
    data = pcm.tobytes()
    out = bytearray()
    # File header: 'caff', version 1, flags 0.
    out += b"caff" + struct.pack(">HH", 1, 0)
    # Audio description chunk (32 bytes).
    desc = struct.pack(
        ">dIIIIII",
        float(SR),       # mSampleRate
        0x6C70636D,      # 'lpcm'
        0,               # flags: big-endian signed integer
        2,               # mBytesPerPacket
        1,               # mFramesPerPacket
        1,               # mChannelsPerFrame
        16,              # mBitsPerChannel
    )
    out += b"desc" + struct.pack(">q", len(desc)) + desc
    # Data chunk: 4-byte edit count + samples.
    out += b"data" + struct.pack(">q", len(data) + 4) + struct.pack(">I", 0) + data
    with open(path, "wb") as f:
        f.write(out)


# --------------------------------------------------------------------------
# Building blocks
# --------------------------------------------------------------------------


def t_axis(duration):
    return np.arange(int(round(duration * SR))) / SR


def silence(duration):
    return np.zeros(int(round(duration * SR)))


def adsr(n, attack, decay_tau, sustain=0.0, release=0.0):
    """Exponential envelope: linear attack, exponential decay toward
    `sustain`, optional linear release at the end."""
    t = np.arange(n) / SR
    env = np.where(t < attack, t / max(attack, 1e-6), 1.0)
    after = np.maximum(t - attack, 0)
    decay = sustain + (1 - sustain) * np.exp(-after / max(decay_tau, 1e-6))
    env = np.where(t < attack, env, decay)
    if release > 0:
        r = int(release * SR)
        if 0 < r < n:
            env[-r:] *= np.linspace(1, 0, r)
    return env


def fade_edges(x, fade_in=0.002, fade_out=0.01):
    n = len(x)
    a = min(int(fade_in * SR), n // 2)
    b = min(int(fade_out * SR), n // 2)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def bell(freq, duration, decay=0.8, brightness=1.0, partials=None):
    """Inharmonic bell/glass tone from decaying partials."""
    t = t_axis(duration)
    if partials is None:
        partials = [(1.0, 1.0, 1.0), (2.0, 0.45, 0.7), (2.76, 0.30 * brightness, 0.5),
                    (5.40, 0.16 * brightness, 0.32), (8.93, 0.07 * brightness, 0.2)]
    out = np.zeros_like(t)
    for ratio, amp, decay_scale in partials:
        f = freq * ratio
        if f >= SR / 2:
            continue
        env = np.exp(-t / (decay * decay_scale))
        out += amp * env * np.sin(2 * np.pi * f * t + RNG.uniform(0, 2 * np.pi))
    attack = int(0.003 * SR)
    out[:attack] *= np.linspace(0, 1, attack)
    return out


def marimba(freq, duration, decay=0.25):
    t = t_axis(duration)
    out = (np.sin(2 * np.pi * freq * t) * np.exp(-t / decay)
           + 0.35 * np.sin(2 * np.pi * freq * 4.0 * t) * np.exp(-t / (decay * 0.25))
           + 0.12 * np.sin(2 * np.pi * freq * 9.9 * t) * np.exp(-t / (decay * 0.1)))
    attack = int(0.002 * SR)
    out[:attack] *= np.linspace(0, 1, attack)
    return out


def fm_tone(freq, duration, ratio=2.0, index=1.5, index_decay=0.2, amp_decay=0.6, attack=0.004):
    t = t_axis(duration)
    idx = index * np.exp(-t / index_decay)
    mod = idx * np.sin(2 * np.pi * freq * ratio * t)
    out = np.sin(2 * np.pi * freq * t + mod)
    return out * adsr(len(t), attack, amp_decay)


def soft_sine(freq, duration, attack=0.01, decay=0.2, vibrato=0.0):
    t = t_axis(duration)
    phase = 2 * np.pi * freq * t
    if vibrato:
        phase += vibrato * np.sin(2 * np.pi * 5.0 * t)
    return np.sin(phase) * adsr(len(t), attack, decay)


def noise_burst(duration, lowpass_hz, decay):
    n = int(round(duration * SR))
    noise = RNG.standard_normal(n)
    return one_pole_lowpass(noise, lowpass_hz) * adsr(n, 0.0005, decay)


def one_pole_lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def mix_at(base, sound, start):
    i = int(round(start * SR))
    end = min(len(base), i + len(sound))
    if end > i:
        base[i:end] += sound[: end - i]
    return base


def reverb(x, seconds=1.2, wet=0.25, damping=4000.0):
    """Convolve with a short synthetic exponentially decaying noise tail."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    ir = RNG.standard_normal(n) * np.exp(-t * (6.9 / seconds))
    ir = one_pole_lowpass(ir, damping)
    ir[: int(0.012 * SR)] = 0  # pre-delay
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    size = len(x) + n - 1
    fft = 1 << (size - 1).bit_length()
    tail = np.fft.irfft(np.fft.rfft(x, fft) * np.fft.rfft(ir, fft), fft)[: len(x)]
    return (1 - wet) * x + wet * tail


def normalize(x, peak_dbfs):
    peak = np.max(np.abs(x))
    if peak == 0:
        return x
    return x * (10 ** (peak_dbfs / 20.0) / peak)


def fit_length(x, duration):
    n = int(round(duration * SR))
    if len(x) >= n:
        return x[:n].copy()
    return np.concatenate([x, np.zeros(n - len(x))])


def note(name):
    """Frequency of a note name such as 'A4', 'C#5', 'Eb3'."""
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    letter = name[0]
    rest = name[1:]
    semitone = names[letter]
    if rest.startswith("#"):
        semitone += 1
        rest = rest[1:]
    elif rest.startswith("b"):
        semitone -= 1
        rest = rest[1:]
    octave = int(rest)
    midi = 12 * (octave + 1) + semitone
    return 440.0 * 2 ** ((midi - 69) / 12)


# --------------------------------------------------------------------------
# The 13 sounds. Targets: (duration s, peak dBFS) from the measured table.
# --------------------------------------------------------------------------


def alt_jingle():
    """~6.0 s bright, upbeat intro jingle: rising FM-bell arpeggio over a
    warm chord bed, resolving on a sustained major-ninth chord."""
    d = 5.996
    out = silence(d)
    arpeggio = ["G4", "C5", "E5", "G5", "D5", "E5", "A5", "G5"]
    for i, n in enumerate(arpeggio):
        tone = fm_tone(note(n), 1.6, ratio=3.5, index=1.2, index_decay=0.12, amp_decay=0.45)
        mix_at(out, 0.55 * tone, 0.08 + i * 0.16)
    # Resolution chord.
    for n, amp in [("C4", 0.35), ("G4", 0.28), ("D5", 0.22), ("E5", 0.22), ("B5", 0.12)]:
        tone = bell(note(n), 4.0, decay=1.4, brightness=0.6)
        mix_at(out, amp * tone, 1.45)
    # Soft pad under everything.
    t = t_axis(d)
    pad = sum(np.sin(2 * np.pi * note(n) * (1 + det) * t)
              for n in ("C3", "G3", "E4") for det in (-0.0015, 0.0015))
    pad_env = np.clip(t / 1.2, 0, 1) * np.clip((d - t) / 1.8, 0, 1)
    out += 0.05 * pad * pad_env
    out = reverb(out, seconds=1.8, wet=0.3)
    return fade_edges(fit_length(out, d), 0.002, 0.25), -3.4


def blips():
    """~6.7 s playful celebratory blips: a pentatonic run of short sine
    blips with echoes, finishing with a sparkle."""
    d = 6.741
    out = silence(d)
    scale = ["C5", "D5", "E5", "G5", "A5", "C6", "D6", "E6"]
    pattern = [0, 2, 4, 3, 5, 4, 6, 7, 5, 3, 4, 6, 7, 6, 5, 7]
    for i, idx in enumerate(pattern):
        f = note(scale[idx])
        blip = soft_sine(f, 0.18, attack=0.002, decay=0.045) + 0.25 * soft_sine(f * 2, 0.18, attack=0.002, decay=0.02)
        start = 0.05 + i * 0.13 + (0.02 if i % 4 == 3 else 0)
        mix_at(out, 0.5 * blip, start)
        # Echoes.
        mix_at(out, 0.22 * blip, start + 0.27)
        mix_at(out, 0.09 * blip, start + 0.54)
    # Final sparkle.
    for k, n in enumerate(["E6", "G6", "C7"]):
        mix_at(out, 0.3 * bell(note(n), 2.5, decay=0.6, brightness=0.4), 2.35 + k * 0.07)
    out = reverb(out, seconds=1.5, wet=0.28)
    return fade_edges(fit_length(out, d), 0.002, 0.4), -4.1


def chime():
    """~4.2 s quiet hourly chime: two soft bell strikes (a fifth apart)
    with a long, gentle decay."""
    d = 4.237
    out = silence(d)
    mix_at(out, 0.8 * bell(note("E5"), 4.0, decay=1.5, brightness=0.5), 0.0)
    mix_at(out, 0.65 * bell(note("A4"), 3.6, decay=1.5, brightness=0.5), 0.55)
    out = reverb(out, seconds=1.6, wet=0.22)
    return fade_edges(fit_length(out, d), 0.002, 0.3), -20.0


def directions():
    """~1.5 s "time to leave": two-note rising marimba motif."""
    d = 1.476
    out = silence(d)
    mix_at(out, marimba(note("G5"), 1.2, decay=0.3), 0.0)
    mix_at(out, marimba(note("D6"), 1.2, decay=0.35), 0.17)
    out = reverb(out, seconds=0.8, wet=0.2)
    return fade_edges(fit_length(out, d), 0.002, 0.15), -14.0


def event():
    """~1.7 s calendar event: three-note descending glass chime."""
    d = 1.743
    out = silence(d)
    for i, n in enumerate(["B5", "G5", "D6"]):
        mix_at(out, 0.7 * bell(note(n), 1.5, decay=0.45, brightness=0.8), i * 0.14)
    out = reverb(out, seconds=0.9, wet=0.22)
    return fade_edges(fit_length(out, d), 0.002, 0.2), -17.5


def haptic():
    """~10.6 ms audible tick for the notch-width tuning slider."""
    d = 0.0106
    t = t_axis(d)
    tick = np.sin(2 * np.pi * 2600 * t) * np.exp(-t / 0.0022)
    tick += 0.4 * np.sin(2 * np.pi * 900 * t) * np.exp(-t / 0.003)
    tick += 0.15 * RNG.standard_normal(len(t)) * np.exp(-t / 0.0008)
    return fade_edges(tick, 0.0003, 0.002), -8.5


def lock():
    """~0.28 s lock: a soft, low, closing "thock" with a short click."""
    d = 0.284
    t = t_axis(d)
    sweep = 2 * np.pi * np.cumsum(np.linspace(190, 120, len(t))) / SR
    body = np.sin(sweep) * adsr(len(t), 0.002, 0.05)
    click = noise_burst(d, 3500, 0.006)
    latch = np.zeros_like(t)
    mix_at(latch, 0.5 * noise_burst(0.06, 2200, 0.008), 0.045)
    out = body + 0.6 * click + latch
    return fade_edges(out, 0.0005, 0.04), -10.7


def low_battery():
    """~1.1 s connected-device low battery alert: two descending tones,
    clearly audible."""
    d = 1.096
    out = silence(d)
    for i, n in enumerate(["E5", "B4"]):
        tone = fm_tone(note(n), 0.75, ratio=1.0, index=0.8, index_decay=0.15, amp_decay=0.22, attack=0.006)
        mix_at(out, tone, i * 0.22)
    out = reverb(out, seconds=0.5, wet=0.15)
    return fade_edges(fit_length(out, d), 0.002, 0.1), -0.5


def low_power():
    """~0.67 s Mac low battery: soft two-tone descending warning."""
    d = 0.672
    out = silence(d)
    mix_at(out, soft_sine(note("A5"), 0.5, attack=0.004, decay=0.12) + 0.3 * soft_sine(note("A6"), 0.5, attack=0.004, decay=0.05), 0.0)
    mix_at(out, soft_sine(note("E5"), 0.5, attack=0.004, decay=0.14) + 0.3 * soft_sine(note("E6"), 0.5, attack=0.004, decay=0.05), 0.15)
    out = reverb(out, seconds=0.4, wet=0.15)
    return fade_edges(fit_length(out, d), 0.002, 0.08), -5.8


def pad():
    """~6.1 s ambient pad for the About / intro screens: slowly blooming
    detuned chord with gentle movement."""
    d = 6.059
    t = t_axis(d)
    chord = ["D3", "A3", "E4", "F#4", "C#5"]
    out = np.zeros_like(t)
    for k, n in enumerate(chord):
        f = note(n)
        for det in (-0.003, 0.0, 0.0031):
            lfo = 0.5 + 0.5 * np.sin(2 * np.pi * (0.13 + 0.05 * k) * t + k)
            out += (0.6 + 0.4 * lfo) * (np.sin(2 * np.pi * f * (1 + det) * t)
                                        + 0.18 * np.sin(2 * np.pi * 2 * f * (1 + det) * t))
    env = np.clip(t / 1.8, 0, 1) ** 1.5 * np.clip((d - t) / 2.2, 0, 1)
    out *= env
    out = reverb(out, seconds=2.2, wet=0.35, damping=2500)
    return fade_edges(out, 0.01, 0.3), -4.0


def sleep():
    """~3.0 s Sleep Focus: a hushed three-note lullaby falling into a
    soft tail."""
    d = 3.002
    out = silence(d)
    for i, n in enumerate(["E5", "C5", "A4"]):
        tone = soft_sine(note(n), 2.2, attack=0.03, decay=0.6, vibrato=0.002)
        tone += 0.2 * soft_sine(note(n) * 2, 2.2, attack=0.03, decay=0.3)
        mix_at(out, 0.6 * tone, i * 0.32)
    out = reverb(out, seconds=1.6, wet=0.35, damping=3000)
    return fade_edges(fit_length(out, d), 0.005, 0.4), -11.1


def unlock():
    """~0.27 s unlock: light, rising double click."""
    d = 0.270
    t = t_axis(d)
    out = np.zeros_like(t)
    for start, f in [(0.0, 1300.0), (0.07, 1750.0)]:
        n = int(0.12 * SR)
        tt = np.arange(n) / SR
        tone = np.sin(2 * np.pi * f * tt) * np.exp(-tt / 0.018)
        tone += 0.3 * noise_burst(0.12, 6000, 0.003)
        mix_at(out, tone, start)
    return fade_edges(out, 0.0005, 0.03), -11.9


def volume():
    """~0.38 s volume feedback: a short rounded pop."""
    d = 0.382
    t = t_axis(d)
    sweep = 2 * np.pi * np.cumsum(np.linspace(980, 860, len(t))) / SR
    out = np.sin(sweep) * adsr(len(t), 0.002, 0.045)
    out += 0.25 * np.sin(2 * sweep) * adsr(len(t), 0.002, 0.02)
    return fade_edges(out, 0.0005, 0.05), -7.0


SOUNDS = {
    "alt-jingle": alt_jingle,
    "blips": blips,
    "chime": chime,
    "directions": directions,
    "event": event,
    "haptic": haptic,
    "lock": lock,
    "low-battery": low_battery,
    "low-power": low_power,
    "pad": pad,
    "sleep": sleep,
    "unlock": unlock,
    "volume": volume,
}


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "Foyer", "Resources", "Sounds")
    os.makedirs(out_dir, exist_ok=True)
    for name, fn in SOUNDS.items():
        samples, peak = fn()
        samples = normalize(np.asarray(samples, dtype=np.float64), peak)
        path = os.path.join(out_dir, name + ".caf")
        write_caf(path, samples)
        rms = 20 * np.log10(np.sqrt(np.mean(samples ** 2)) + 1e-12)
        print(f"{name:12s} {len(samples) / SR:7.3f} s  peak {peak:6.1f} dBFS  rms {rms:6.1f} dBFS  -> {path}")


if __name__ == "__main__":
    main()

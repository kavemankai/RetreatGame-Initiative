"""Synthesizes the game's sound set into retreat-sim/assets/audio/*.wav.
Everything is generated from code with a fixed seed (no samples, no network),
so the files are reproducible:   python art/make_sounds.py

sfx_*      one-shot effects          amb_*     ambient loops (one per level family)
music_*    act music loops           ui_*      interface sounds
"""
import os
import sys
import wave

import numpy as np
from scipy import signal

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "retreat-sim", "assets", "audio")
RNG = np.random.default_rng(1160)


def t_arr(sec):
    return np.arange(int(SR * sec)) / SR


def noise(sec, seed=None):
    r = np.random.default_rng(seed) if seed is not None else RNG
    return r.standard_normal(int(SR * sec))


def lowpass(x, hz, order=2):
    b, a = signal.butter(order, hz / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def highpass(x, hz, order=2):
    b, a = signal.butter(order, hz / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def env(sec, attack=0.005, decay=8.0):
    t = t_arr(sec)
    e = np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-decay * t)
    return e


def sine(freq, sec, phase=0.0):
    f = freq if np.ndim(freq) else np.full(int(SR * sec), freq)
    return np.sin(2 * np.pi * np.cumsum(f) / SR + phase)


def fade(x, ms=8):
    n = int(SR * ms / 1000)
    x = x.copy()
    x[:n] *= np.linspace(0, 1, n)
    x[-n:] *= np.linspace(1, 0, n)
    return x


def reverb(x, size=0.12, mix=0.25):
    out = x.copy()
    for d, g in ((0.029, 0.5), (0.043, 0.4), (0.067, 0.3), (size, 0.25)):
        n = int(SR * d)
        out[n:] += x[:-n] * g * mix * 2
    return out


def fit(x, n):
    """Pad with silence or trim `x` to exactly n samples."""
    return np.pad(x, (0, max(0, n - len(x))))[:n]


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def save(name, x, loop=False):
    x = np.clip(x, -1, 1)
    data = (x * 32767).astype("<i2").tobytes()
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(f"{name:18s} {len(x) / SR:5.1f}s {'loop' if loop else ''}")


def crossfade_loop(x, sec=1.0):
    """Make `x` loop seamlessly by blending its tail into its head."""
    n = int(SR * sec)
    body = x[:-n].copy()
    body[:n] = body[:n] * np.linspace(0, 1, n) + x[-n:] * np.linspace(1, 0, n)
    return body


# --- one-shot effects -------------------------------------------------------------

def shot(seed, heavy=False):
    sec = 0.55
    n = noise(sec, seed)
    crack = lowpass(n, 4200 if not heavy else 2600) * env(sec, 0.001, 22)
    thump = sine(np.linspace(150 if heavy else 120, 45, int(SR * sec)), sec) * env(sec, 0.002, 14)
    tail = lowpass(n, 900) * env(sec, 0.02, 6) * 0.35
    return norm(reverb(crack * 0.8 + thump * (1.0 if heavy else 0.7) + tail), 0.85)


def hit():
    sec = 0.3
    thud = sine(np.linspace(130, 55, int(SR * sec)), sec) * env(sec, 0.002, 16)
    body = lowpass(noise(sec, 5), 900) * env(sec, 0.002, 18)
    return norm(thud + body * 0.8, 0.8)


def miss():
    sec = 0.32
    n = noise(sec, 6)
    sweep = np.zeros_like(n)
    for lo in range(1200, 3600, 400):
        sweep += bandpass(n, lo, lo + 500) * (np.linspace(1, 0, len(n)) ** 1.5 if lo < 2400 else np.linspace(0.2, 1, len(n)) * np.linspace(1, 0, len(n)))
    ping = sine(2300, sec) * env(sec, 0.05, 14) * 0.25
    return norm(fade(sweep * 0.8 + ping), 0.55)


def blocked():
    sec = 0.45
    x = sum(sine(f, sec) * env(sec, 0.001, d) * a for f, d, a in ((1270, 9, 1), (1930, 12, 0.7), (2710, 16, 0.5), (3300, 20, 0.3)))
    return norm(x + highpass(noise(sec, 7), 3000) * env(sec, 0.001, 40) * 0.5, 0.7)


def death():
    sec = 1.1
    drop = sine(np.linspace(220, 40, int(SR * sec)), sec) * env(sec, 0.01, 3.0)
    breath = lowpass(noise(sec, 8), 600) * env(sec, 0.15, 3.5) * 0.4
    return norm(fade(drop + breath), 0.75)


def step(seed):
    sec = 0.12
    return norm(lowpass(noise(sec, seed), 520) * env(sec, 0.002, 38), 0.45)


def bell(freq, sec, partials=((1, 1), (2.01, 0.4), (3.2, 0.2)), decay=3.5):
    return sum(sine(freq * m, sec) * a for m, a in partials) * env(sec, 0.004, decay)


def steady():
    return norm(fade(bell(520, 0.8) + bell(780, 0.8) * 0.6), 0.5)


def broken():
    sec = 0.9
    x = sine(np.linspace(300, 190, int(SR * sec)), sec) * env(sec, 0.01, 3.2) + sine(np.linspace(317, 203, int(SR * sec)), sec) * env(sec, 0.01, 3.2) * 0.8
    return norm(fade(x), 0.55)


def equip():
    sec = 0.3
    clunk = lowpass(noise(sec, 9), 1500) * env(sec, 0.001, 30)
    ring = bell(940, sec, ((1, 1), (2.7, 0.5)), 14) * 0.5
    return norm(clunk + ring, 0.6)


def loot():
    parts = [bell(f, 0.9) * (0.9 ** i) for i, f in enumerate((523, 659, 784))]
    out = np.zeros(int(SR * 1.5))
    for i, p in enumerate(parts):
        s = int(SR * 0.16 * i)
        out[s:s + len(p)] += p
    return norm(fade(out), 0.55)


def ui_click():
    sec = 0.05
    return norm(sine(1900, sec) * env(sec, 0.001, 70) + highpass(noise(sec, 10), 2500) * env(sec, 0.001, 90) * 0.4, 0.45)


def ui_confirm():
    sec = 0.28
    a = sine(440, sec) * env(sec, 0.003, 14)
    b = np.concatenate([np.zeros(int(SR * 0.07)), (sine(660, sec) * env(sec, 0.003, 12))[:int(SR * (sec - 0.07))]])
    return norm(a + fit(b, len(a)), 0.45)


def go():
    sec = 0.7
    rise = lowpass(noise(sec, 11), np.linspace(300, 2500, 1)[0]) * np.linspace(0.1, 1, int(SR * sec)) ** 2
    thump = np.concatenate([np.zeros(int(SR * 0.4)), (sine(np.linspace(100, 40, int(SR * 0.3)), 0.3) * env(0.3, 0.002, 12))])[:int(SR * sec)]
    return norm(fade(rise * 0.5 + fit(thump, len(rise))), 0.7)


def stinger_win():
    notes = (392, 466, 587, 784)
    out = np.zeros(int(SR * 2.6))
    for i, f in enumerate(notes):
        b = bell(f, 1.8, decay=2.2)
        s = int(SR * 0.22 * i)
        out[s:s + len(b)] += b
    return norm(fade(reverb(out, 0.2, 0.3)), 0.6)


def stinger_loss():
    out = np.zeros(int(SR * 3.0))
    for i, f in enumerate((294, 247, 196)):
        b = bell(f, 2.0, ((1, 1), (2.0, 0.3)), 1.6)
        s = int(SR * 0.45 * i)
        out[s:s + len(b)] += b
    return norm(fade(reverb(out, 0.25, 0.35)), 0.6)


def stinger_start():
    sec = 1.2
    drum = sine(np.linspace(90, 38, int(SR * sec)), sec) * env(sec, 0.002, 4.5)
    air = lowpass(noise(sec, 12), 700) * env(sec, 0.01, 5) * 0.4
    return norm(fade(reverb(drum + air, 0.2, 0.3)), 0.75)


# --- ambient loops ---------------------------------------------------------------

def slow_lfo(sec, hz, depth=0.5, seed=0):
    r = np.random.default_rng(seed)
    return 1 - depth + depth * (0.5 + 0.5 * np.sin(2 * np.pi * hz * t_arr(sec) + r.uniform(0, 6)))


def amb(kind):
    sec = 12.0
    t = t_arr(sec + 1.0)
    n = noise(sec + 1.0, 21)
    if kind == "deck":
        x = sine(55, sec + 1) * 0.5 + sine(110.5, sec + 1) * 0.2 + lowpass(n, 300) * 0.25 * slow_lfo(sec + 1, 0.15, 0.4, 1)
    elif kind == "wind":
        x = lowpass(bandpass(n, 150, 1400), 900) * slow_lfo(sec + 1, 0.11, 0.7, 2) * 1.2 + sine(48, sec + 1) * 0.12
    elif kind == "foundry":
        x = lowpass(n, 220) * 0.9 + sine(40, sec + 1) * 0.4 * slow_lfo(sec + 1, 0.3, 0.5, 3)
        for k in range(3):
            s = int(SR * (1.5 + 4.2 * k)); c = bell(180 + 30 * k, 0.9, ((1, 1), (2.4, 0.5)), 8) * 0.6
            x[s:s + len(c)] += c
    elif kind == "market":
        x = bandpass(n, 300, 2200) * slow_lfo(sec + 1, 0.4, 0.6, 4) * 0.8 + bandpass(noise(sec + 1, 22), 600, 3000) * slow_lfo(sec + 1, 0.23, 0.7, 5) * 0.5
    elif kind == "garden":
        x = sine(62, sec + 1) * 0.25 + lowpass(n, 500) * 0.12
        for k in range(5):
            s = int(SR * (0.8 + 2.3 * k)); d = sine(np.linspace(1500, 700, int(SR * 0.12)), 0.12) * env(0.12, 0.002, 30) * 0.5
            x[s:s + len(d)] += d
    elif kind == "hospital":
        x = sine(118, sec + 1) * 0.3 + sine(236, sec + 1) * 0.12 + lowpass(n, 400) * 0.08
        for k in range(3):
            s = int(SR * (1.0 + 4.0 * k)); b = sine(1040, 0.18) * env(0.18, 0.005, 12) * 0.25
            x[s:s + len(b)] += b
    elif kind == "relay":
        x = sine(90, sec + 1) * 0.35 + sine(3150, sec + 1) * 0.02 * slow_lfo(sec + 1, 0.2, 0.9, 6) + lowpass(n, 700) * 0.1
    else:  # threshold
        x = sine(41, sec + 1) * 0.5 + sine(82.4, sec + 1) * 0.2 * slow_lfo(sec + 1, 0.07, 0.8, 7) + sine(1200, sec + 1) * 0.01
    return norm(crossfade_loop(x, 1.0), 0.45)


# --- music loops --------------------------------------------------------------

def pad(freq, sec, bright):
    t = t_arr(sec)
    x = sum(sine(freq * d, sec) * a for d, a in ((1.0, 1), (1.004, 0.7), (0.996, 0.7), (2.0, 0.3 * bright)))
    return x * np.minimum(1, t / 1.8) * np.minimum(1, (sec - t) / 1.8)


def music(roots, bright, melody_scale, density, seed, bpm_sec=6.0):
    n_chords = len(roots)
    sec = bpm_sec * n_chords
    out = np.zeros(int(SR * (sec + 1.5)))
    for i, root in enumerate(roots):
        s = int(SR * bpm_sec * i)
        for interval in (1.0, 1.2, 1.5):  # a minor triad
            p = pad(root * interval, bpm_sec + 1.5, bright)
            out[s:s + len(p)] += p * 0.18
    r = np.random.default_rng(seed)
    for i in range(int(density * n_chords)):
        f = roots[0] * 4 * melody_scale[r.integers(len(melody_scale))]
        b = bell(f, 2.6, ((1, 1), (2.0, 0.25)), 1.7) * 0.22
        s = int(SR * (r.uniform(0, sec - 1)))
        out[s:s + len(b)] += b[:len(out) - s]
    out = reverb(out, 0.3, 0.4)
    return norm(crossfade_loop(out, 1.5), 0.55)


PENTATONIC = [1.0, 1.2, 1.333, 1.5, 1.8, 2.0]


# --- weapon classes: one shot sound per class, plus the grenade's blast ------------------------

def shot_carbine(seed):
    sec = 0.32
    n = noise(sec, seed)
    crack = lowpass(n, 5200) * env(sec, 0.001, 30)
    thump = sine(np.linspace(130, 70, int(SR * sec)), sec) * env(sec, 0.002, 22)
    return norm(reverb(crack * 0.85 + thump * 0.45, 0.08, 0.15), 0.8)


def shot_sniper(seed):
    sec = 1.1
    n = noise(sec, seed)
    crack = highpass(lowpass(n, 6500), 900) * env(sec, 0.0007, 40)
    thump = sine(np.linspace(110, 32, int(SR * sec)), sec) * env(sec, 0.003, 7)
    tail = lowpass(n, 600) * env(sec, 0.05, 3.2) * 0.3
    return norm(reverb(crack * 0.9 + thump * 0.9 + tail, 0.22, 0.4), 0.9)


def shot_shotgun(seed):
    sec = 0.8
    n = noise(sec, seed)
    boom = lowpass(n, 3200) * env(sec, 0.001, 11)
    thump = sine(np.linspace(95, 30, int(SR * sec)), sec) * env(sec, 0.002, 8)
    tail = lowpass(n, 700) * env(sec, 0.03, 4.0) * 0.5
    return norm(reverb(boom * 0.9 + thump * 1.1 + tail, 0.15, 0.3), 0.92)


def shot_grenade(seed):
    sec = 0.55
    n = noise(sec, seed)
    puff = lowpass(n, 1400) * env(sec, 0.004, 14)
    thoomp = sine(np.linspace(120, 38, int(SR * sec)), sec) * env(sec, 0.003, 9)
    return norm(reverb(puff * 0.55 + thoomp * 1.0, 0.1, 0.2), 0.85)


def blast(seed):
    sec = 1.4
    n = noise(sec, seed)
    rumble = lowpass(n, 380) * env(sec, 0.004, 3.2)
    burst = lowpass(n, 2600) * env(sec, 0.001, 12)
    boom = sine(np.linspace(80, 26, int(SR * sec)), sec) * env(sec, 0.003, 3.6)
    return norm(reverb(rumble * 0.8 + burst * 0.6 + boom * 1.1, 0.25, 0.35), 0.95)


def shot_beam(seed):
    sec = 0.45
    sweep = np.linspace(2400, 420, int(SR * sec))
    zap = (sine(sweep, sec) + 0.7 * sine(sweep * 1.012, sec)) * env(sec, 0.002, 9)
    fizz = highpass(noise(sec, seed), 3000) * env(sec, 0.001, 18) * 0.35
    return norm(reverb(zap * 0.7 + fizz, 0.06, 0.15), 0.8)


def weapons():
    save("sfx_shot_carbine", shot_carbine(71))
    save("sfx_shot_sniper", shot_sniper(72))
    save("sfx_shot_shotgun", shot_shotgun(73))
    save("sfx_shot_grenade", shot_grenade(74))
    save("sfx_blast", blast(75))
    save("sfx_shot_beam", shot_beam(76))



def main():
    if "--weapons" in sys.argv:  # only the weapon-class sounds; leaves every other file untouched
        weapons()
        return
    for i in range(3):
        save(f"sfx_shot_{i}", shot(40 + i))
    save("sfx_shot_heavy", shot(50, True))
    save("sfx_hit", hit())
    save("sfx_miss", miss())
    save("sfx_blocked", blocked())
    save("sfx_death", death())
    for i in range(3):
        save(f"sfx_step_{i}", step(60 + i))
    save("sfx_steady", steady())
    save("sfx_broken", broken())
    save("sfx_equip", equip())
    save("sfx_loot", loot())
    save("ui_click", ui_click())
    save("ui_confirm", ui_confirm())
    save("ui_go", go())
    save("stinger_win", stinger_win())
    save("stinger_loss", stinger_loss())
    save("stinger_start", stinger_start())
    for kind in ("deck", "wind", "foundry", "market", "garden", "hospital", "relay", "threshold"):
        save(f"amb_{kind}", amb(kind), True)
    # act music: A minor and friends, slow; act 3 lower and sparser
    save("music_act1", music([110.0, 87.3, 98.0, 82.4], 1.0, PENTATONIC, 2.2, 1), True)
    save("music_act2", music([98.0, 77.8, 87.3, 73.4], 0.7, PENTATONIC, 1.6, 2), True)
    save("music_act3", music([82.4, 65.4, 73.4, 61.7], 0.4, PENTATONIC, 1.0, 3), True)
    weapons()


if __name__ == "__main__":
    main()

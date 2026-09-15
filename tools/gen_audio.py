# -*- coding: utf-8 -*-
"""gen_audio.py —— 程序化合成全部音效与背景音乐（WAV / 16bit PCM / mono / 22050Hz）。

所有音频都由本文件用数学波形实时合成：方波、三角波、锯齿波、噪声、扫频、
包络与简易延迟/低通滤波。旋律、和声、节奏全部为本工程原创编写，
不采样、不引用任何外部音频素材。

命名约定（Godot 侧按此加载，勿改名）：

  audio/sfx/<name>.wav    约 45 个音效
  audio/bgm/<name>.wav    7 首可循环背景音乐
"""
from __future__ import annotations

import math
import os
import struct

import numpy as np

from pixel import ASSETS_ROOT

SR = 22050
MASTER = 0.86

# BGM 专用采样率：44100Hz 细节更丰富。SFX 仍走全局 SR=22050，互不影响。
SR_BGM = 44100


# ==================================================================== 基础工具

def _t(n: int, sr: int = SR) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / sr


def _smpl_chunk(sr: int, n_frames: int) -> bytes:
    """构造 WAV 的 smpl（采样器）块，声明一个从首帧到末帧的前向循环。

    Godot 的 WAV 导入器会读取该块并自动把 AudioStreamWAV 设为 LOOP_FORWARD，
    因此循环信息随素材本身携带，不依赖编辑器里的逐文件导入参数。
    """
    body = struct.pack(
        "<IIIIIIII",
        0,                                   # dwManufacturer
        0,                                   # dwProduct
        int(round(1_000_000_000 / sr)),      # dwSamplePeriod（纳秒）
        60,                                  # dwMIDIUnityNote
        0,                                   # dwMIDIPitchFraction
        0,                                   # dwSMPTEFormat
        0,                                   # dwSMPTEOffset
        1,                                   # cSampleLoops
    )
    body += struct.pack(
        "<IIIIII",
        0,                       # dwIdentifier
        0,                       # dwType：0 = 前向循环
        0,                       # dwStart
        max(0, n_frames - 1),    # dwEnd
        0,                       # dwFraction
        0,                       # dwPlayCount：0 = 无限循环
    )
    return b"smpl" + struct.pack("<I", len(body)) + body


def write_wav(rel: str, sig: np.ndarray, sr: int = SR, loop: bool = False) -> str:
    """归一化后写成 16bit PCM mono WAV；loop=True 时附带 smpl 循环块。

    手写 RIFF 而非用标准库 wave，是为了能插入 smpl 块。
    """
    sig = np.asarray(sig, dtype=np.float64)
    peak = float(np.max(np.abs(sig))) if sig.size else 0.0
    if peak > 1e-9:
        sig = sig / peak * MASTER
    pcm = np.clip(sig * 32767.0, -32768, 32767).astype("<i2").tobytes()
    path = os.path.join(ASSETS_ROOT, *rel.replace("\\", "/").split("/"))
    os.makedirs(os.path.dirname(path), exist_ok=True)

    fmt = struct.pack("<HHIIHH", 1, 1, sr, sr * 2, 2, 16)  # PCM / mono / 16bit
    chunks = [b"fmt " + struct.pack("<I", len(fmt)) + fmt]
    if loop:
        chunks.append(_smpl_chunk(sr, int(pcm.__len__() // 2)))
    chunks.append(b"data" + struct.pack("<I", len(pcm)) + pcm)
    body = b"".join(chunks)
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body) + 4) + b"WAVE" + body)
    return path


def env(n: int, a: float = 0.005, d: float = 0.05, s: float = 0.6, r: float = 0.08,
        hold: float = 0.0, sr: int = SR) -> np.ndarray:
    """ADSR 包络（时间单位秒）。"""
    na, nd, nr = int(a * sr), int(d * sr), int(r * sr)
    ns = max(0, n - na - nd - nr)
    na = min(na, n)
    nd = min(nd, n - na)
    ns = min(ns, n - na - nd)
    nr = n - na - nd - ns
    parts = []
    if na:
        parts.append(np.linspace(0, 1, na, endpoint=False))
    if nd:
        parts.append(np.linspace(1, s, nd, endpoint=False))
    if ns:
        parts.append(np.full(ns, s))
    if nr:
        parts.append(np.linspace(s, 0, nr))
    out = np.concatenate(parts) if parts else np.zeros(0)
    if out.size < n:
        out = np.concatenate([out, np.zeros(n - out.size)])
    return out[:n]


def lowpass(x: np.ndarray, cutoff: float, sr: int = SR) -> np.ndarray:
    """一阶低通（幅度响应 1/sqrt(1+(f/fc)^2)），FFT 实现，稳定且快。

    cutoff 单位 Hz。零相位，对短音符的边界效应可忽略。
    """
    n = x.size
    if n == 0:
        return x
    fc = max(float(cutoff), 20.0)
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1.0 / sr)
    h = 1.0 / np.sqrt(1.0 + (freqs / fc) ** 2)
    return np.fft.irfft(spec * h, n)


# 兼容旧名：两处调用点都用 lowpass_fast
lowpass_fast = lowpass


def delay(x: np.ndarray, time: float = 0.16, feedback: float = 0.32, mix: float = 0.28,
          sr: int = SR) -> np.ndarray:
    n = x.size
    out = x.copy()
    d = int(time * sr)
    if d <= 0:
        return out
    gain = feedback
    total = n + d * 8
    buf = np.zeros(total)
    buf[:n] = x
    for k in range(1, 8):
        s = d * k
        if s >= total:
            break
        e = min(n, total - s)
        buf[s:s + e] += x[:e] * (gain ** k)
    # buf 的前 n 个采样已包含干声 + 各次回声（mix 控制回声整体强度）
    return buf[:n] * (1.0 - mix) + x * mix


def mix(*sigs) -> np.ndarray:
    """把若干长度可能不同的信号按起点对齐叠加（短的补零）。"""
    n = max((s.size for s in sigs), default=0)
    out = np.zeros(n)
    for sig in sigs:
        out[:sig.size] += sig
    return out


def soft_clip(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
    return np.tanh(x * drive)


# ==================================================================== 波形

def square(freq: float, dur: float, duty: float = 0.5, phase: float = 0.0,
           sr: int = SR) -> np.ndarray:
    n = int(dur * sr)
    if n <= 0:
        return np.zeros(0)
    t = _t(n, sr)
    ph = (t * freq + phase) % 1.0
    return np.where(ph < duty, 1.0, -1.0)


def saw(freq: float, dur: float, phase: float = 0.0, sr: int = SR) -> np.ndarray:
    n = int(dur * sr)
    if n <= 0:
        return np.zeros(0)
    t = _t(n, sr)
    return 2.0 * ((t * freq + phase) % 1.0) - 1.0


def tri(freq: float, dur: float, phase: float = 0.0, sr: int = SR) -> np.ndarray:
    n = int(dur * sr)
    if n <= 0:
        return np.zeros(0)
    t = _t(n, sr)
    p = (t * freq + phase) % 1.0
    return 4.0 * np.abs(p - 0.5) - 1.0


def sine(freq: float, dur: float, phase: float = 0.0, sr: int = SR) -> np.ndarray:
    n = int(dur * sr)
    if n <= 0:
        return np.zeros(0)
    return np.sin(2 * math.pi * freq * _t(n, sr) + phase)


def noise(dur: float, seed: int = 0, sr: int = SR) -> np.ndarray:
    n = int(dur * sr)
    rng = np.random.default_rng(seed)
    return rng.standard_normal(n)


def sweep(f0: float, f1: float, dur: float, wave: str = "sine", sr: int = SR) -> np.ndarray:
    """指数频率扫描。"""
    n = int(dur * sr)
    if n <= 0:
        return np.zeros(0)
    t = _t(n, sr)
    k = t / dur
    f = f0 * ((f1 / max(f0, 1e-6)) ** k)
    ph = 2 * math.pi * np.cumsum(f) / sr
    if wave == "sine":
        return np.sin(ph)
    if wave == "square":
        return np.where((ph / (2 * math.pi)) % 1.0 < 0.5, 1.0, -1.0)
    if wave == "saw":
        return 2.0 * ((ph / (2 * math.pi)) % 1.0) - 1.0
    return np.sin(ph)


def vibrato(x: np.ndarray, rate: float = 5.5, depth: float = 0.012, sr: int = SR) -> np.ndarray:
    n = x.size
    t = _t(n, sr)
    # 用重采样近似变调
    idx = np.clip(np.arange(n) + depth * np.sin(2 * math.pi * rate * t) * sr / max(rate, 1e-6), 0, n - 1)
    return np.interp(idx, np.arange(n), x)


# ==================================================================== 音符

NOTE_OFF = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note_freq(name) -> float:
    """'A4' / 'C#3' / 'Bb2' -> Hz；None 或 '-' 返回 0。"""
    if name is None or name in ("-", "", "rest"):
        return 0.0
    s = str(name)
    letter = s[0].upper()
    i = 1
    acc = 0
    while i < len(s) and s[i] in "#b":
        acc += 1 if s[i] == "#" else -1
        i += 1
    octv = int(s[i:])
    midi = (octv + 1) * 12 + NOTE_OFF[letter] + acc
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


# ==================================================================== 乐器

def lead_tone(freq: float, dur: float, duty: float = 0.35, vol: float = 0.5,
              a: float = 0.004, r: float = 0.05, vib: float = 0.0,
              sr: int = SR) -> np.ndarray:
    if freq <= 0:
        return np.zeros(int(dur * sr))
    x = mix(square(freq, dur, duty, sr=sr) * 0.7, square(freq * 2, dur, duty, sr=sr) * 0.16,
            tri(freq, dur, sr=sr) * 0.25)
    e = env(x.size, a=a, d=dur * 0.25, s=0.72, r=r, sr=sr)
    x = x * e * vol
    if vib > 0:
        x = vibrato(x, 6.0, vib, sr=sr)
    return lowpass_fast(x, min(sr * 0.45, freq * 9 + 1800), sr)


def bass_tone(freq: float, dur: float, vol: float = 0.55, sr: int = SR) -> np.ndarray:
    if freq <= 0:
        return np.zeros(int(dur * sr))
    x = mix(tri(freq, dur, sr=sr) * 0.85, square(freq, dur, 0.25, sr=sr) * 0.3)
    e = env(x.size, a=0.006, d=dur * 0.3, s=0.55, r=0.07, sr=sr)
    return lowpass_fast(x * e * vol, 900.0, sr)


def pad_tone(freq: float, dur: float, vol: float = 0.22, sr: int = SR) -> np.ndarray:
    if freq <= 0:
        return np.zeros(int(dur * sr))
    x = mix(saw(freq, dur, sr=sr) * 0.5, saw(freq * 1.005, dur, sr=sr) * 0.5,
            tri(freq * 0.5, dur, sr=sr) * 0.35)
    e = env(x.size, a=dur * 0.35, d=dur * 0.2, s=0.8, r=dur * 0.4, sr=sr)
    return lowpass_fast(x * e * vol, 1600.0, sr)


def pluck(freq: float, dur: float, vol: float = 0.45, sr: int = SR) -> np.ndarray:
    if freq <= 0:
        return np.zeros(int(dur * sr))
    x = mix(square(freq, dur, 0.2, sr=sr) * 0.6, saw(freq, dur, sr=sr) * 0.4)
    e = np.exp(-np.arange(x.size) / (sr * dur * 0.28))
    return lowpass_fast(x * e * vol, 3200.0, sr)


def kick(vol: float = 0.9, sr: int = SR) -> np.ndarray:
    x = sweep(150, 42, 0.16, "sine", sr=sr)
    e = np.exp(-np.arange(x.size) / (sr * 0.055))
    return x * e * vol


def snare(vol: float = 0.5, seed: int = 1, sr: int = SR) -> np.ndarray:
    n = int(0.14 * sr)
    nz = noise(0.14, seed, sr=sr) * np.exp(-np.arange(n) / (sr * 0.045))
    body = sweep(220, 150, 0.09, "tri", sr=sr) * np.exp(-np.arange(int(0.09 * sr)) / (sr * 0.03))
    out = np.zeros(n)
    out += nz * vol * 0.8
    out[:body.size] += body * vol * 0.5
    return lowpass_fast(out, 5200.0, sr)


def hat(vol: float = 0.22, seed: int = 2, dur: float = 0.045, sr: int = SR) -> np.ndarray:
    n = int(dur * sr)
    x = noise(dur, seed, sr=sr) * np.exp(-np.arange(n) / (sr * dur * 0.35))
    x = x - lowpass_fast(x, 4000.0, sr)
    return x * vol


def crash(vol: float = 0.4, seed: int = 3, sr: int = SR) -> np.ndarray:
    dur = 0.9
    n = int(dur * sr)
    x = noise(dur, seed, sr=sr) * np.exp(-np.arange(n) / (sr * 0.32))
    x = x - lowpass_fast(x, 2600.0, sr)
    return x * vol


# ==================================================================== 混音

def overlay(out: np.ndarray, sig: np.ndarray, at: int = 0) -> np.ndarray:
    """把 sig 安全叠加到 out 的第 at 个采样处（越界自动截断）。"""
    i = int(at)
    if i < 0:
        sig = sig[-i:]
        i = 0
    k = min(sig.size, out.size - i)
    if k > 0:
        out[i:i + k] += sig[:k]
    return out


def render_track(length_sec: float, sr: int = SR) -> "Mixer":
    return Mixer(length_sec, sr)


class Mixer:
    """多轨叠加混音器；长度参数单位为秒。"""

    def __init__(self, length_sec: float, sr: int = SR):
        self.sr = sr
        self.buf = np.zeros(max(1, int(length_sec * sr)))

    @property
    def n(self) -> int:
        return self.buf.size

    def add(self, sig: np.ndarray, at_sec: float, vol: float = 1.0) -> None:
        i = int(at_sec * self.sr)
        if i < 0:
            sig = sig[-i:]
            i = 0
        if i >= self.n or sig.size == 0:
            return
        e = min(self.n - i, sig.size)
        self.buf[i:i + e] += sig[:e] * vol

    def fade_out(self, sec: float = 0.6) -> None:
        n = int(sec * SR)
        if n <= 0 or n > self.n:
            n = self.n
        ramp = np.linspace(1.0, 0.0, n) ** 1.4
        self.buf[-n:] *= ramp

    def fade_in(self, sec: float = 0.2) -> None:
        n = min(int(sec * SR), self.n)
        if n <= 0:
            return
        self.buf[:n] *= np.linspace(0.0, 1.0, n)

    def out(self) -> np.ndarray:
        return self.buf


# ==================================================================== 序列器

def seq_render(mx: Mixer, start: float, step: float, notes, inst, vol: float = 1.0,
               legato: float = 1.0) -> float:
    """把一串音名按 step 秒渲染进混音器，返回结束时间。"""
    t = start
    for name in notes:
        if isinstance(name, tuple):
            name, mult = name
        else:
            mult = 1
        dur = step * mult * legato
        f = note_freq(name)
        if f > 0:
            mx.add(inst(f, dur), t, vol)
        t += step * mult
    return t


def chord_render(mx: Mixer, start: float, dur: float, names, inst, vol: float = 1.0,
                 spread: float = 0.0) -> None:
    for i, nm in enumerate(names):
        f = note_freq(nm)
        if f > 0:
            mx.add(inst(f, dur), start + i * spread, vol)


# ==================================================================== 音效

def sfx_pistol() -> np.ndarray:
    x = mix(sweep(880, 180, 0.09, "square") * 0.5,
            noise(0.05, 11) * np.exp(-np.arange(int(0.05 * SR)) / (SR * 0.012)) * 0.5)
    e = np.exp(-np.arange(x.size) / (SR * 0.03))
    return lowpass_fast(x * e, 6500.0)


def sfx_smg() -> np.ndarray:
    x = mix(sweep(1100, 320, 0.05, "square") * 0.42, noise(0.03, 21) * 0.4)
    e = np.exp(-np.arange(x.size) / (SR * 0.017))
    return lowpass_fast(x * e, 7800.0)


def sfx_shotgun() -> np.ndarray:
    n = int(0.34 * SR)
    boom = sweep(240, 55, 0.3, "sine") * np.exp(-np.arange(int(0.3 * SR)) / (SR * 0.09))
    nz = noise(0.3, 33) * np.exp(-np.arange(int(0.3 * SR)) / (SR * 0.05))
    out = np.zeros(n)
    out[:boom.size] += boom * 1.0
    out[:nz.size] += nz * 0.75
    return lowpass_fast(out, 4200.0)


def sfx_rifle() -> np.ndarray:
    x = mix(sweep(1500, 240, 0.11, "saw") * 0.4, noise(0.06, 41) * 0.35)
    e = np.exp(-np.arange(x.size) / (SR * 0.035))
    return lowpass_fast(x * e, 8200.0)


def sfx_laser() -> np.ndarray:
    x = mix(sweep(2400, 700, 0.16, "sine") * 0.4,
            sweep(1200, 350, 0.16, "square") * 0.18,
            sine(3200, 0.05) * 0.12)
    e = env(x.size, a=0.003, d=0.05, s=0.4, r=0.08)
    return lowpass_fast(x * e, 9000.0)


def sfx_rocket() -> np.ndarray:
    n = int(0.5 * SR)
    whoosh = noise(0.5, 51) * np.exp(-np.arange(n) / (SR * 0.22)) * 0.5
    ign = sweep(300, 90, 0.35, "sine") * 0.7
    e = np.exp(-np.arange(ign.size) / (SR * 0.13))
    out = np.zeros(n)
    out += whoosh
    out[:ign.size] += ign * e
    return lowpass_fast(out, 3000.0)


def sfx_wand() -> np.ndarray:
    x = mix(sine(1400, 0.22) * 0.3, sine(2100, 0.22) * 0.2, sine(2800, 0.18) * 0.12)
    x = vibrato(x, 9.0, 0.02)
    e = env(x.size, a=0.02, d=0.1, s=0.5, r=0.12)
    return delay(x * e, 0.09, 0.3, 0.3)


def sfx_blade() -> np.ndarray:
    n = int(0.24 * SR)
    nz = noise(0.24, 61)
    nz = nz - lowpass_fast(nz, 1200.0)
    sw = sweep(500, 2600, 0.18, "saw") * 0.3
    out = np.zeros(n)
    e = np.exp(-np.arange(n) / (SR * 0.07))
    out += nz * e * 0.55
    out[:sw.size] += sw * np.exp(-np.arange(sw.size) / (SR * 0.06)) * 0.5
    return lowpass_fast(out, 9000.0)


def sfx_hit_flesh() -> np.ndarray:
    n = int(0.14 * SR)
    thud = sweep(300, 90, 0.12, "sine") * np.exp(-np.arange(int(0.12 * SR)) / (SR * 0.03)) * 0.8
    sq = noise(0.09, 71) * np.exp(-np.arange(int(0.09 * SR)) / (SR * 0.02)) * 0.4
    out = np.zeros(n)
    out[:thud.size] += thud
    out[:sq.size] += lowpass_fast(sq, 2500.0)
    return out


def sfx_hit_wall() -> np.ndarray:
    n = int(0.12 * SR)
    x = noise(0.1, 81) * np.exp(-np.arange(int(0.1 * SR)) / (SR * 0.018))
    x = lowpass_fast(x, 3000.0) * 0.5
    tick = sweep(1800, 700, 0.05, "square") * 0.25
    out = np.zeros(n)
    out[:x.size] += x
    out[:tick.size] += tick
    return out


def sfx_hit_crit() -> np.ndarray:
    x = mix(sweep(1600, 3200, 0.1, "square") * 0.3, sine(2400, 0.14) * 0.25,
            noise(0.06, 91) * 0.25)
    e = np.exp(-np.arange(x.size) / (SR * 0.045))
    return delay(lowpass_fast(x * e, 9000.0), 0.05, 0.22, 0.25)


def sfx_enemy_hurt() -> np.ndarray:
    x = mix(sweep(420, 260, 0.1, "square") * 0.4, noise(0.06, 101) * 0.2)
    e = np.exp(-np.arange(x.size) / (SR * 0.035))
    return lowpass_fast(x * e, 3200.0)


def sfx_enemy_die() -> np.ndarray:
    n = int(0.4 * SR)
    x = sweep(500, 60, 0.35, "saw") * 0.45
    e = np.exp(-np.arange(x.size) / (SR * 0.11))
    x = x * e
    nz = noise(0.3, 111) * np.exp(-np.arange(int(0.3 * SR)) / (SR * 0.08)) * 0.3
    out = np.zeros(n)
    out[:x.size] += lowpass_fast(x, 2200.0)
    out[:nz.size] += lowpass_fast(nz, 1800.0)
    return out


def sfx_explode_small() -> np.ndarray:
    n = int(0.34 * SR)
    boom = sweep(200, 40, 0.3, "sine") * np.exp(-np.arange(int(0.3 * SR)) / (SR * 0.08))
    nz = noise(0.3, 121) * np.exp(-np.arange(int(0.3 * SR)) / (SR * 0.06))
    out = np.zeros(n)
    out[:boom.size] += boom * 0.9
    out[:nz.size] += lowpass_fast(nz, 2600.0) * 0.7
    return out


def sfx_explode_big() -> np.ndarray:
    n = int(0.85 * SR)
    boom = sweep(160, 30, 0.7, "sine") * np.exp(-np.arange(int(0.7 * SR)) / (SR * 0.22))
    nz = noise(0.75, 131) * np.exp(-np.arange(int(0.75 * SR)) / (SR * 0.16))
    out = np.zeros(n)
    out[:boom.size] += boom * 1.0
    out[:nz.size] += lowpass_fast(nz, 1500.0) * 0.8
    return delay(out, 0.07, 0.25, 0.2)


def sfx_player_hurt() -> np.ndarray:
    x = mix(sweep(320, 120, 0.2, "square") * 0.4, noise(0.1, 141) * 0.25)
    e = np.exp(-np.arange(x.size) / (SR * 0.07))
    return lowpass_fast(x * e, 2400.0)


def sfx_player_die() -> np.ndarray:
    mx = Mixer(1.5)
    seq = ["E4", "D4", "C4", "A3", "F3", "D3"]
    seq_render(mx, 0.0, 0.17, seq, lambda f, d: lead_tone(f, d, 0.4, 0.5), 0.85)
    mx.add(sweep(220, 40, 1.0, "sine") * 0.4, 0.25)
    mx.fade_out(0.4)
    return mx.out()


def sfx_shield_break() -> np.ndarray:
    n = int(0.4 * SR)
    out = np.zeros(n)
    for k, (f, t0) in enumerate([(1800, 0.0), (1200, 0.05), (800, 0.1), (500, 0.16)]):
        x = sweep(f, f * 0.4, 0.14, "square") * 0.28
        i = int(t0 * SR)
        e = np.exp(-np.arange(x.size) / (SR * 0.05))
        k = min(x.size, n - i)
        if k > 0:
            out[i:i + k] += x[:k] * e[:k]
    nz = noise(0.2, 151) * 0.18
    out[:nz.size] += (nz - lowpass_fast(nz, 3000.0))
    return lowpass_fast(out, 8000.0)


def sfx_shield_regen() -> np.ndarray:
    x = mix(sine(700, 0.3) * 0.25, sine(1050, 0.28) * 0.18, sine(1400, 0.2) * 0.1)
    e = env(x.size, a=0.06, d=0.1, s=0.6, r=0.14)
    return delay(x * e, 0.08, 0.25, 0.3)


def sfx_dash() -> np.ndarray:
    n = int(0.26 * SR)
    nz = noise(0.26, 161)
    nz = nz - lowpass_fast(nz, 700.0)
    e = np.sin(np.linspace(0, math.pi, n)) ** 1.5
    sw = sweep(400, 1600, 0.2, "sine") * 0.22
    out = nz * e * 0.5
    out[:sw.size] += sw * np.exp(-np.arange(sw.size) / (SR * 0.08))
    return out


def sfx_skill() -> np.ndarray:
    mx = Mixer(0.6)
    for k, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        mx.add(sine(f, 0.4) * 0.2, k * 0.045)
        mx.add(square(f, 0.3, 0.25) * 0.08, k * 0.045)
    mx.add(noise(0.2, 171) * 0.1, 0.0)
    mx.fade_out(0.25)
    return delay(mx.out(), 0.1, 0.28, 0.3)


def sfx_pickup_coin() -> np.ndarray:
    mx = Mixer(0.28)
    mx.add(square(note_freq("B5"), 0.07, 0.3) * 0.3, 0.0)
    mx.add(square(note_freq("E6"), 0.16, 0.3) * 0.3, 0.055)
    return mx.out()


def sfx_pickup_energy() -> np.ndarray:
    x = mix(sweep(600, 1500, 0.16, "sine") * 0.3,
            square(note_freq("G5"), 0.14, 0.25) * 0.14)
    e = env(x.size, a=0.01, d=0.06, s=0.5, r=0.07)
    return x * e


def sfx_pickup_heart() -> np.ndarray:
    mx = Mixer(0.4)
    mx.add(sine(note_freq("C5"), 0.2) * 0.3, 0.0)
    mx.add(sine(note_freq("G5"), 0.24) * 0.26, 0.09)
    mx.add(tri(note_freq("E5"), 0.3) * 0.14, 0.02)
    mx.fade_out(0.12)
    return mx.out()


def sfx_pickup_weapon() -> np.ndarray:
    mx = Mixer(0.6)
    seq = ["D4", "F4", "A4", "D5"]
    seq_render(mx, 0.0, 0.075, seq, lambda f, d: pluck(f, d, 0.4), 0.8)
    mx.add(crash(0.18, 181), 0.28)
    mx.fade_out(0.15)
    return delay(mx.out(), 0.09, 0.2, 0.22)


def sfx_pickup_talent() -> np.ndarray:
    mx = Mixer(0.85)
    seq = ["C5", "E5", "G5", "B5", "C6"]
    seq_render(mx, 0.0, 0.07, seq, lambda f, d: lead_tone(f, d, 0.3, 0.34), 0.8)
    mx.add(sine(note_freq("C6"), 0.5) * 0.14, 0.3)
    mx.fade_out(0.3)
    return delay(mx.out(), 0.12, 0.3, 0.34)


def sfx_door_open() -> np.ndarray:
    n = int(0.5 * SR)
    out = np.zeros(n)
    rumble = noise(0.45, 191) * 0.35
    rumble = lowpass_fast(rumble, 700.0) * np.sin(np.linspace(0, math.pi, rumble.size))
    out[:rumble.size] += rumble
    clank = sweep(900, 300, 0.12, "square") * 0.22
    out[:clank.size] += clank * np.exp(-np.arange(clank.size) / (SR * 0.04))
    tail = sweep(500, 180, 0.14, "square") * 0.18
    i = int(0.32 * SR)
    out[i:i + tail.size] += tail * np.exp(-np.arange(tail.size) / (SR * 0.05))
    return out


def sfx_door_locked() -> np.ndarray:
    mx = Mixer(0.3)
    mx.add(square(180, 0.09, 0.4) * 0.35, 0.0)
    mx.add(square(140, 0.13, 0.4) * 0.35, 0.1)
    mx.add(noise(0.06, 201) * 0.2, 0.0)
    return lowpass_fast(mx.out(), 2200.0)


def sfx_chest_open() -> np.ndarray:
    mx = Mixer(0.8)
    mx.add(noise(0.2, 211) * 0.12, 0.0)
    seq = ["G4", "C5", "E5", "G5", "C6"]
    seq_render(mx, 0.1, 0.085, seq, lambda f, d: lead_tone(f, d, 0.3, 0.32), 0.8)
    mx.add(crash(0.22, 212), 0.42)
    mx.fade_out(0.2)
    return delay(mx.out(), 0.11, 0.26, 0.3)


def sfx_portal() -> np.ndarray:
    n = int(1.1 * SR)
    out = np.zeros(n)
    for k in range(6):
        f = 300 * (1.35 ** k)
        x = sweep(f, f * 2.2, 0.5, "sine") * 0.16
        i = int(k * 0.08 * SR)
        e = env(x.size, a=0.06, d=0.2, s=0.5, r=0.24)
        out[i:i + x.size] += x * e
    whoosh = noise(0.7, 221) * 0.2
    whoosh = (whoosh - lowpass_fast(whoosh, 900.0)) * np.sin(np.linspace(0, math.pi, whoosh.size))
    out[:whoosh.size] += whoosh
    out[int(0.6 * SR):] += sweep(900, 120, 0.5, "sine") * 0.2
    return delay(out, 0.13, 0.32, 0.34)


def sfx_altar() -> np.ndarray:
    mx = Mixer(1.0)
    for f in [note_freq("C4"), note_freq("E4"), note_freq("G4"), note_freq("B4")]:
        mx.add(pad_tone(f, 0.9, 0.16), 0.0)
    seq_render(mx, 0.05, 0.1, ["C5", "E5", "G5", "C6"], lambda f, d: lead_tone(f, d, 0.25, 0.26), 0.7)
    mx.fade_out(0.4)
    return delay(mx.out(), 0.16, 0.35, 0.36)


def sfx_ui_click() -> np.ndarray:
    x = mix(square(1200, 0.04, 0.3) * 0.3, noise(0.02, 231) * 0.16)
    return lowpass_fast(x * env(x.size, 0.002, 0.01, 0.4, 0.02), 7000.0)


def sfx_ui_hover() -> np.ndarray:
    return square(800, 0.035, 0.25) * 0.14


def sfx_ui_back() -> np.ndarray:
    mx = Mixer(0.2)
    mx.add(square(900, 0.05, 0.3) * 0.24, 0.0)
    mx.add(square(600, 0.08, 0.3) * 0.24, 0.05)
    return mx.out()


def sfx_ui_pause() -> np.ndarray:
    mx = Mixer(0.3)
    mx.add(sine(note_freq("E5"), 0.12) * 0.22, 0.0)
    mx.add(sine(note_freq("A5"), 0.16) * 0.2, 0.07)
    return mx.out()


def sfx_boss_roar() -> np.ndarray:
    n = int(1.8 * SR)
    out = np.zeros(n)
    base = saw(58, 1.6) * 0.4 + saw(58 * 1.01, 1.6) * 0.3 + square(29, 1.6, 0.4) * 0.35
    base = vibrato(base, 7.0, 0.035)
    e = env(base.size, a=0.25, d=0.4, s=0.8, r=0.6)
    out[:base.size] += lowpass_fast(base * e, 900.0)
    nz = noise(1.5, 241) * 0.25
    nz = lowpass_fast(nz, 1200.0) * np.sin(np.linspace(0, math.pi, nz.size))
    out[:nz.size] += nz
    overlay(out, kick(0.8), int(0.3 * SR))
    return delay(out, 0.19, 0.3, 0.3)


def sfx_boss_charge() -> np.ndarray:
    n = int(0.9 * SR)
    x = sweep(120, 900, 0.8, "saw") * 0.35
    x = vibrato(x, 14.0, 0.02)
    e = env(x.size, a=0.5, d=0.2, s=0.9, r=0.1)
    out = lowpass_fast(x * e, 3000.0)
    nz = (noise(0.85, 251) * 0.12)
    nz = nz - lowpass_fast(nz, 600.0)
    overlay(out, nz)
    return out


def sfx_boss_slam() -> np.ndarray:
    n = int(1.2 * SR)
    out = np.zeros(n)
    overlay(out, kick(1.0))
    boom = sweep(120, 28, 0.9, "sine") * np.exp(-np.arange(int(0.9 * SR)) / (SR * 0.25))
    out[:boom.size] += boom * 0.9
    nz = noise(0.6, 261) * 0.4
    out[:nz.size] += lowpass_fast(nz, 1100.0) * np.exp(-np.arange(nz.size) / (SR * 0.12))
    return delay(out, 0.09, 0.3, 0.28)


def sfx_boss_summon() -> np.ndarray:
    mx = Mixer(1.2)
    for k, f in enumerate([note_freq("A2"), note_freq("E3"), note_freq("A3"), note_freq("C4"), note_freq("E4")]):
        mx.add(pad_tone(f, 1.0, 0.16), k * 0.06)
    seq_render(mx, 0.1, 0.11, ["A4", "C5", "E5", "A5"], lambda f, d: lead_tone(f, d, 0.2, 0.24, vib=0.02), 0.7)
    mx.fade_out(0.35)
    return delay(mx.out(), 0.17, 0.36, 0.38)


def sfx_boss_die() -> np.ndarray:
    n = int(3.2 * SR)
    mx = Mixer(3.2)
    seq = ["A3", "G3", "F3", "E3", "D3", "C3", "A2", "A2"]
    seq_render(mx, 0.0, 0.22, seq, lambda f, d: lead_tone(f, d, 0.45, 0.42), 0.9)
    for k in range(5):
        mx.add(sfx_explode_small() * 0.5, 0.4 + k * 0.42)
    mx.add(sfx_explode_big() * 0.9, 2.3)
    mx.add(sweep(400, 30, 2.6, "sine") * 0.35, 0.3)
    mx.fade_out(0.6)
    return delay(mx.out(), 0.21, 0.3, 0.3)


def sfx_level_clear() -> np.ndarray:
    mx = Mixer(2.2)
    seq = ["C5", "E5", "G5", "C6", "G5", "C6", "E6"]
    mult = [1, 1, 1, 2, 1, 1, 3]
    seq_render(mx, 0.0, 0.13, list(zip(seq, mult)), lambda f, d: lead_tone(f, d, 0.35, 0.4), 0.9)
    chord_render(mx, 0.0, 1.6, ["C3", "G3", "E4"], lambda f, d: pad_tone(f, d, 0.14), 0.8)
    mx.add(crash(0.35, 271), 0.0)
    mx.add(crash(0.4, 272), 1.0)
    mx.fade_out(0.5)
    return delay(mx.out(), 0.15, 0.28, 0.3)


def sfx_game_over() -> np.ndarray:
    mx = Mixer(3.0)
    seq = ["D4", "C4", "A#3", "A3", "F3", "D3"]
    mult = [1, 1, 1, 2, 1, 4]
    seq_render(mx, 0.0, 0.26, list(zip(seq, mult)), lambda f, d: lead_tone(f, d, 0.45, 0.4), 0.9)
    chord_render(mx, 0.0, 2.4, ["D2", "A2", "F3"], lambda f, d: pad_tone(f, d, 0.16), 0.8)
    mx.fade_out(0.8)
    return delay(mx.out(), 0.22, 0.34, 0.36)


def sfx_level_start() -> np.ndarray:
    mx = Mixer(1.6)
    seq_render(mx, 0.0, 0.14, ["A3", "C4", "E4", "A4"], lambda f, d: lead_tone(f, d, 0.3, 0.34), 0.85)
    chord_render(mx, 0.5, 1.0, ["A2", "E3", "A3"], lambda f, d: pad_tone(f, d, 0.15), 0.8)
    mx.add(kick(0.6), 0.0)
    mx.fade_out(0.4)
    return delay(mx.out(), 0.14, 0.28, 0.3)


def sfx_low_health() -> np.ndarray:
    mx = Mixer(0.9)
    for k in range(2):
        mx.add(sine(note_freq("A3"), 0.2) * 0.22, k * 0.4)
        mx.add(sine(note_freq("E4"), 0.16) * 0.14, k * 0.4 + 0.05)
    mx.fade_out(0.25)
    return mx.out()


def sfx_empty() -> np.ndarray:
    """能量不足 / 空仓：闷响。"""
    x = mix(square(220, 0.06, 0.4) * 0.22, noise(0.04, 281) * 0.14)
    return lowpass_fast(x * env(x.size, 0.002, 0.02, 0.3, 0.03), 1600.0)


def sfx_reload() -> np.ndarray:
    mx = Mixer(0.5)
    mx.add(noise(0.06, 291) * 0.2, 0.0)
    mx.add(sweep(700, 300, 0.08, "square") * 0.2, 0.09)
    mx.add(square(1100, 0.05, 0.3) * 0.22, 0.24)
    mx.add(noise(0.05, 292) * 0.16, 0.3)
    return lowpass_fast(mx.out(), 6000.0)


def sfx_step() -> np.ndarray:
    n = int(0.09 * SR)
    nz = noise(0.09, 301) * np.exp(-np.arange(n) / (SR * 0.018))
    return lowpass_fast(nz, 1400.0) * 0.5


def sfx_land() -> np.ndarray:
    n = int(0.16 * SR)
    x = sweep(180, 70, 0.14, "sine") * np.exp(-np.arange(int(0.14 * SR)) / (SR * 0.04)) * 0.7
    nz = noise(0.1, 311) * 0.2
    out = np.zeros(n)
    out[:x.size] += x
    out[:nz.size] += lowpass_fast(nz, 1200.0)
    return out


def sfx_buy() -> np.ndarray:
    mx = Mixer(0.7)
    seq_render(mx, 0.0, 0.08, ["E5", "G5", "B5", "E6"], lambda f, d: pluck(f, d, 0.36), 0.85)
    mx.add(sfx_pickup_coin() * 0.7, 0.0)
    mx.fade_out(0.2)
    return delay(mx.out(), 0.1, 0.24, 0.28)


def sfx_break_crate() -> np.ndarray:
    n = int(0.32 * SR)
    out = np.zeros(n)
    rng = np.random.default_rng(321)
    for k in range(9):
        i = int(rng.random() * 0.12 * SR)
        f = 1200 + rng.random() * 2600
        x = sweep(f, f * 0.4, 0.09, "square") * 0.16
        e = np.exp(-np.arange(x.size) / (SR * 0.025))
        out[i:i + x.size] += x * e
    nz = noise(0.22, 331) * 0.3
    out[:nz.size] += lowpass_fast(nz, 2600.0) * np.exp(-np.arange(nz.size) / (SR * 0.05))
    return out


def sfx_teleport_out() -> np.ndarray:
    x = sweep(1600, 200, 0.4, "sine") * 0.3
    x = vibrato(x, 11.0, 0.02)
    e = env(x.size, 0.01, 0.15, 0.5, 0.2)
    return delay(x * e, 0.08, 0.3, 0.32)


SFX = {
    "shoot_pistol": sfx_pistol, "shoot_smg": sfx_smg, "shoot_shotgun": sfx_shotgun,
    "shoot_rifle": sfx_rifle, "shoot_laser": sfx_laser, "shoot_rocket": sfx_rocket,
    "shoot_wand": sfx_wand, "swing_blade": sfx_blade,
    "hit_flesh": sfx_hit_flesh, "hit_wall": sfx_hit_wall, "hit_crit": sfx_hit_crit,
    "enemy_hurt": sfx_enemy_hurt, "enemy_die": sfx_enemy_die,
    "explode_small": sfx_explode_small, "explode_big": sfx_explode_big,
    "player_hurt": sfx_player_hurt, "player_die": sfx_player_die,
    "shield_break": sfx_shield_break, "shield_regen": sfx_shield_regen,
    "dash": sfx_dash, "skill": sfx_skill,
    "pickup_coin": sfx_pickup_coin, "pickup_energy": sfx_pickup_energy,
    "pickup_heart": sfx_pickup_heart, "pickup_weapon": sfx_pickup_weapon,
    "pickup_talent": sfx_pickup_talent,
    "door_open": sfx_door_open, "door_locked": sfx_door_locked,
    "chest_open": sfx_chest_open, "portal": sfx_portal, "altar": sfx_altar,
    "ui_click": sfx_ui_click, "ui_hover": sfx_ui_hover, "ui_back": sfx_ui_back,
    "ui_pause": sfx_ui_pause,
    "boss_roar": sfx_boss_roar, "boss_charge": sfx_boss_charge,
    "boss_slam": sfx_boss_slam, "boss_summon": sfx_boss_summon, "boss_die": sfx_boss_die,
    "level_clear": sfx_level_clear, "game_over": sfx_game_over,
    "level_start": sfx_level_start, "low_health": sfx_low_health,
    "empty": sfx_empty, "reload": sfx_reload, "step": sfx_step, "land": sfx_land,
    "buy": sfx_buy, "break_crate": sfx_break_crate, "teleport_out": sfx_teleport_out,
}


# ==================================================================== 音乐
# 全部旋律/和声为本工程原创编写。

def _drums(mx: Mixer, start: float, step: float, pattern: str, vol: float = 1.0,
           seed: int = 0, sr: int = SR) -> float:
    """pattern 每个字符对应一个 16 分音符：K=底鼓 S=军鼓 H=闭镲 O=开镲 .=空"""
    t = start
    for i, ch in enumerate(pattern):
        if ch == "K":
            mx.add(kick(0.85 * vol, sr=sr), t)
        elif ch == "S":
            mx.add(snare(0.42 * vol, seed + i, sr=sr), t)
        elif ch == "H":
            mx.add(hat(0.16 * vol, seed + i * 3, 0.035, sr=sr), t)
        elif ch == "O":
            mx.add(hat(0.2 * vol, seed + i * 5, 0.12, sr=sr), t)
        elif ch == "C":
            mx.add(crash(0.3 * vol, seed + i, sr=sr), t)
        t += step
    return t


def _bell(freq: float, dur: float, vol: float = 0.28, sr: int = SR_BGM) -> np.ndarray:
    """水晶钟声：正弦基频 + 2.76x/5.4x 泛音，指数衰减，用于空灵段落。"""
    if freq <= 0:
        return np.zeros(int(dur * sr))
    n = int(dur * sr)
    x = (sine(freq, dur, sr=sr)
         + 0.5 * sine(freq * 2.76, dur, sr=sr)
         + 0.22 * sine(freq * 5.4, dur, sr=sr))
    e = np.exp(-np.arange(n) / (sr * dur * 0.42))
    return lowpass_fast(x * e * vol, 7200.0, sr)


def bgm_menu() -> np.ndarray:
    """主菜单：空灵、神秘的水晶洞窟氛围。A 小调，72 BPM，约 27 秒循环。"""
    sr = SR_BGM
    bpm = 72
    step = 60.0 / bpm / 4          # 16 分音符
    bars = 8
    total = step * 16 * bars
    mx = Mixer(total + 2.5, sr)

    # 和声进行：Am - F - C - G | Am - F - Dm - E
    prog = [
        ["A2", "E3", "A3", "C4", "E4"],
        ["F2", "C3", "F3", "A3", "C4"],
        ["C3", "G3", "C4", "E4", "G4"],
        ["G2", "D3", "G3", "B3", "D4"],
        ["A2", "E3", "A3", "C4", "E4"],
        ["F2", "C3", "F3", "A3", "C4"],
        ["D3", "A3", "D4", "F4", "A4"],
        ["E2", "B2", "E3", "G#3", "B3"],
    ]
    # 手写水晶琶音（每小节一个上行-回落轮廓）
    arps = [
        ["A4", "C5", "E5", "C5", "A4", "E4", "A4", "C5"],
        ["F4", "A4", "C5", "A4", "F4", "C4", "F4", "A4"],
        ["G4", "C5", "E5", "C5", "G4", "E4", "G4", "C5"],
        ["G4", "B4", "D5", "B4", "G4", "D4", "G4", "B4"],
        ["A4", "C5", "E5", "C5", "A4", "E4", "A4", "C5"],
        ["F4", "A4", "C5", "A4", "F4", "C4", "F4", "A4"],
        ["F4", "A4", "D5", "A4", "F4", "D4", "F4", "A4"],
        ["G#4", "B4", "E5", "B4", "G#4", "E4", "B3", "E4"],
    ]
    # 手写主旋律（五声动机，呼吸感）
    melody = [
        ("E5", 2), ("C5", 2), ("D5", 2), ("E5", 2), ("G5", 4), ("E5", 4),
        ("F5", 2), ("E5", 2), ("D5", 2), ("C5", 4), ("A4", 4),
        ("C5", 2), ("E5", 2), ("G5", 4), ("A5", 2), ("G5", 2),
        ("G5", 2), ("F5", 2), ("E5", 4), ("D5", 4),
        ("E5", 2), ("G5", 2), ("A5", 2), ("G5", 2), ("E5", 4), ("C5", 2),
        ("D5", 2), ("C5", 2), ("A4", 4), ("C5", 4),
        ("D5", 2), ("F5", 2), ("A5", 4), ("G5", 2), ("F5", 2),
        ("G#4", 2), ("B4", 2), ("E5", 4), ("G#5", 2), ("E5", 2),
    ]
    t = 0.0
    for b in range(bars):
        ch = prog[b % len(prog)]
        bt = b * step * 16
        for nm in ch[:3]:
            mx.add(pad_tone(note_freq(nm), step * 16, 0.15, sr=sr), bt)
        ark = arps[b % len(arps)]
        for k, nm in enumerate(ark):
            mx.add(_bell(note_freq(nm), step * 1.6, 0.2, sr), bt + k * step * 2)
        mx.add(bass_tone(note_freq(ch[0]), step * 14, 0.42, sr=sr), bt)
        mx.add(bass_tone(note_freq(ch[0]), step * 12, 0.3, sr=sr), bt + step * 14)
    mt = step * 8
    for nm, mult in melody:
        f = note_freq(nm)
        if f > 0:
            mx.add(_bell(f, step * mult * 0.95, 0.26, sr), mt)
        mt += step * mult
        if mt > total - step * 4:
            break
    mx.fade_in(1.4)
    mx.fade_out(2.0)
    return delay(mx.out(), 0.32, 0.36, 0.36, sr=sr)


def _dungeon_track(bpm: int, bars: int, key_root: str, seed: int,
                   intensity: float) -> np.ndarray:
    """地牢 BGM 生成器：低音驱动 + 琶音 + 手写旋律 + 鼓组（44100Hz）。"""
    sr = SR_BGM
    step = 60.0 / bpm / 4
    total = step * 16 * bars
    mx = Mixer(total + 1.5, sr)

    # 音阶（自然小调）
    scale_semi = [0, 2, 3, 5, 7, 8, 10]
    root_midi = {"A": 57, "D": 50, "E": 52, "C": 48, "G": 55}[key_root]

    # 低音进行：i - VI - III - VII（每两拍换）
    bass_prog = [0, 5, 2, 6, 0, 3, 4, 4]

    # 手写旋律动机（每 2 小节一个乐句，共 8 小节 → 循环两次填满 16 小节）。
    # 用 (音级, 时值) 表示；None 表示休止。音级基于小调音阶，+2 八度置于高音区。
    motif = {
        0: [(4, 2), (0, 2), (2, 2), (4, 2), (3, 4), (2, 2), (3, 2), (4, 2),
            (2, 2), (3, 2), (2, 2), (0, 2), (3, 4)],
        1: [(2, 2), (3, 2), (1, 2), (3, 2), (4, 4), (3, 2), (2, 2), (1, 2),
            (0, 4), (1, 2), (2, 2), (0, 2), (3, 2), (2, 4)],
        2: [(5, 2), (4, 2), (3, 2), (4, 2), (2, 4), (3, 2), (2, 2), (4, 2),
            (3, 2), (2, 2), (0, 2), (4, 2), (5, 4)],
        3: [(0, 2), (2, 2), (4, 2), (3, 2), (2, 2), (4, 2), (3, 2), (1, 2),
            (2, 4), (3, 2), (2, 2), (0, 4)],
        4: [(3, 2), (2, 2), (0, 2), (2, 2), (1, 2), (2, 2), (4, 2), (5, 2),
            (4, 2), (3, 2), (2, 2), (3, 2), (1, 4)],
        5: [(1, 2), (2, 2), (0, 2), (2, 2), (1, 4), (2, 2), (1, 2), (0, 2),
            (3, 2), (2, 2), (1, 2), (3, 4)],
        6: [(2, 2), (4, 2), (5, 2), (4, 2), (3, 2), (4, 2), (2, 2), (3, 2),
            (4, 2), (2, 2), (0, 2), (3, 2), (2, 4)],
    }[seed % 7]

    melody_notes = motif * (bars // 8) if bars >= 8 else motif[:bars * 8]

    for b in range(bars):
        bt = b * step * 16
        deg = bass_prog[b % len(bass_prog)]
        # 驱动低音（8 分音符脉冲）
        for k in range(8):
            f = note_midi_freq(root_midi + scale_semi[deg % 7] + 12 * (deg // 7) - 12)
            mx.add(bass_tone(f, step * 1.7, 0.5, sr=sr), bt + k * step * 2)
            if k % 4 == 3:
                f2 = note_midi_freq(root_midi + scale_semi[deg % 7] + 12 * (deg // 7) - 5)
                mx.add(bass_tone(f2, step * 1.4, 0.36, sr=sr), bt + k * step * 2)
        # 和声铺底
        chordm = [root_midi + scale_semi[deg % 7] + 12 * (deg // 7),
                  root_midi + scale_semi[(deg + 2) % 7] + 12 * ((deg + 2) // 7),
                  root_midi + scale_semi[(deg + 4) % 7] + 12 * ((deg + 4) // 7)]
        for m in chordm:
            mx.add(pad_tone(note_midi_freq(m), step * 16, 0.075 + 0.03 * intensity, sr=sr), bt)
        # 琶音（16 分，确定性取模而非随机）
        arpm = [chordm[0] + 12, chordm[1] + 12, chordm[2] + 12, chordm[1] + 12]
        for k in range(16):
            m = arpm[k % 4]
            if (k + b * 3) % 5 != 0:
                mx.add(pluck(note_midi_freq(m), step * 1.6,
                             0.16 + 0.05 * intensity, sr=sr), bt + k * step)
        # 鼓组
        if intensity < 0.4:
            pat = "K...H...K...H..." if b % 2 == 0 else "K...H...K.K.HH.."
            _drums(mx, bt, step, pat, 0.75, seed=b * 13 + seed, sr=sr)
        elif intensity < 0.75:
            pat = "K..HH..HK..HH..H" if b % 2 == 0 else "K..HH..HK.KHS..H"
            _drums(mx, bt, step, pat, 0.85, seed=b * 13 + seed, sr=sr)
            if b % 4 == 3:
                _drums(mx, bt + step * 12, step, "SSSS", 0.5, seed=b * 17 + seed, sr=sr)
        else:
            pat = "K..HS..HK..HS..H" if b % 2 == 0 else "K.KHS.KHK..HS.SS"
            _drums(mx, bt, step, pat, 1.0, seed=b * 13 + seed, sr=sr)

    # 主旋律：按手写乐句的 (音级, 时值) 推进（高八度，音头清晰）
    t = step * 4
    for item in melody_notes:
        if isinstance(item, tuple):
            d, mult = item
        else:
            d, mult = item, 2
        if d is not None:
            m = root_midi + scale_semi[d % 7] + 12 * (d // 7) + 12
            mx.add(lead_tone(note_midi_freq(m), step * mult * 0.96,
                             0.32 - 0.08 * intensity, 0.22 + 0.06 * intensity,
                             r=0.08, vib=0.007, sr=sr), t)
        t += step * mult
        if t > total - step * 4:
            break

    mx.fade_in(0.4)
    mx.fade_out(0.8)
    return delay(mx.out(), 60.0 / bpm * 0.75, 0.22, 0.2, sr=sr)


def note_midi_freq(midi: int) -> float:
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


def bgm_dungeon(layer: int) -> np.ndarray:
    layer = max(1, min(3, layer))
    if layer == 1:
        return _dungeon_track(bpm=104, bars=16, key_root="A", seed=101, intensity=0.3)
    if layer == 2:
        return _dungeon_track(bpm=118, bars=16, key_root="D", seed=202, intensity=0.6)
    return _dungeon_track(bpm=132, bars=16, key_root="E", seed=303, intensity=0.9)


def bgm_boss() -> np.ndarray:
    """Boss 战：150 BPM，d 小调，重鼓 + 半音下行 + 急促弦乐。约 32 秒循环。"""
    bpm = 150
    step = 60.0 / bpm / 4
    bars = 16
    total = step * 16 * bars
    mx = Mixer(total + 1.5, sr=SR_BGM)
    root = 50  # D3

    # 半音下行的固定低音（原创动机）
    ostinato = [0, 0, -1, -1, -2, -2, -3, -3, -4, -4, -3, -3, -2, -1, -1, 0]
    # 主旋律：紧张的四度跳进（手写）
    mel = [(12, 2), (15, 2), (19, 4), (17, 2), (15, 2), (12, 4),
           (10, 2), (12, 2), (15, 4), (14, 2), (12, 2), (10, 4),
           (8, 2), (10, 2), (12, 4), (15, 4), (19, 4), (17, 4)]

    for b in range(bars):
        bt = b * step * 16
        semi = ostinato[b % len(ostinato)]
        # 低音脉冲（16 分）
        for k in range(16):
            f = note_midi_freq(root - 12 + semi + (12 if k % 4 == 2 else 0))
            v = 0.55 if k % 4 == 0 else 0.38
            mx.add(bass_tone(f, step * 0.95, v, sr=SR_BGM), bt + k * step)
        # 弦乐式持续音
        for deg in (0, 3, 7):
            mx.add(pad_tone(note_midi_freq(root + semi + deg), step * 16, 0.09,
                            sr=SR_BGM), bt)
        # 高频紧张琶音
        for k in range(16):
            m = root + 12 + semi + [0, 7, 12, 7][k % 4]
            mx.add(pluck(note_midi_freq(m), step * 1.2, 0.13, sr=SR_BGM), bt + k * step)
        # 鼓
        if b % 4 == 3:
            _drums(mx, bt, step, "K.SHK.SHKSKSKSKS", 1.0, seed=b * 29, sr=SR_BGM)
        else:
            _drums(mx, bt, step, "K..HS..HK..HS..H", 1.0, seed=b * 29, sr=SR_BGM)
        if b == 0:
            mx.add(crash(0.35, 900, sr=SR_BGM), bt)

    # 主旋律
    t = step * 4
    for deg, mult in mel:
        mx.add(lead_tone(note_midi_freq(root + deg), step * mult * 0.92, 0.42, 0.3,
                         r=0.05, vib=0.012, sr=SR_BGM), t)
        t += step * mult
        if t > total - step * 2:
            t = step * 4 + (t - total)

    mx.fade_in(0.3)
    mx.fade_out(0.7)
    return delay(mx.out(), step * 6, 0.24, 0.22, sr=SR_BGM)


def bgm_victory() -> np.ndarray:
    """通关：明亮的 C 大调凯旋短句（不循环），44100Hz。"""
    sr = SR_BGM
    bpm = 128
    step = 60.0 / bpm / 4
    mx = Mixer(step * 16 * 6 + 2.0, sr)
    mel = [("C5", 2), ("E5", 2), ("G5", 2), ("C6", 4), ("G5", 2), ("C6", 6),
           ("B5", 2), ("C6", 2), ("D6", 4), ("E6", 8),
           ("D6", 2), ("E6", 2), ("G6", 4), ("E6", 2), ("C6", 6),
           ("G5", 4), ("C6", 12)]
    chords = [["C3", "E3", "G3"], ["F3", "A3", "C4"], ["G2", "D3", "G3"], ["C3", "E4", "G4"]]
    t = 0.0
    for nm, mult in mel:
        mx.add(lead_tone(note_freq(nm), step * mult * 0.94, 0.4, 0.42, r=0.1,
                         vib=0.01, sr=sr), t)
        t += step * mult
    for b in range(4):
        bt = b * step * 16
        chord_render(mx, bt, step * 16, chords[b],
                     lambda f, d: pad_tone(f, d, 0.14, sr=sr), 0.85)
        seq_render(mx, bt, step * 2, chords[b] * 4,
                   lambda f, d: pluck(f, d, 0.2, sr=sr), 0.5)
        _drums(mx, bt, step, "K..HS..HK..HS..H" if b < 3 else "K.SHK.SHKSKSKSC.",
               0.9, seed=b * 31, sr=sr)
        mx.add(bass_tone(note_freq(chords[b][0][0] + "2"), step * 8, 0.42, sr=sr), bt)
    mx.fade_out(1.4)
    return delay(mx.out(), 0.2, 0.3, 0.3, sr=sr)


def bgm_gameover() -> np.ndarray:
    """失败：低沉的 d 小调短句（不循环），44100Hz。"""
    sr = SR_BGM
    bpm = 76
    step = 60.0 / bpm / 4
    mx = Mixer(step * 16 * 5 + 2.5, sr)
    mel = [("D4", 4), ("F4", 4), ("E4", 4), ("D4", 4),
           ("A#3", 6), ("A3", 10),
           ("D4", 4), ("C4", 4), ("A#3", 4), ("A3", 4),
           ("G3", 8), ("D3", 12)]
    t = 0.0
    for nm, mult in mel:
        mx.add(lead_tone(note_freq(nm), step * mult * 0.94, 0.45, 0.36, r=0.2,
                         vib=0.014, sr=sr), t)
        t += step * mult
    for b, ch in enumerate([["D2", "A2", "D3"], ["A#2", "F3", "A#3"], ["A2", "E3", "A3"],
                            ["G2", "D3", "G3"], ["D2", "A2", "D3"]]):
        bt = b * step * 16
        chord_render(mx, bt, step * 16, ch, lambda f, d: pad_tone(f, d, 0.16, sr=sr), 0.9)
        mx.add(bass_tone(note_freq(ch[0]), step * 12, 0.42, sr=sr), bt)
    mx.fade_out(2.0)
    return delay(mx.out(), 0.34, 0.38, 0.38, sr=sr)


def bgm_shop() -> np.ndarray:
    """商店 / 安全房：轻快的短循环，44100Hz。"""
    sr = SR_BGM
    bpm = 96
    step = 60.0 / bpm / 4
    bars = 8
    mx = Mixer(step * 16 * bars + 1.0, sr)
    prog = [["C3", "E3", "G3"], ["A2", "C3", "E3"], ["F2", "A2", "C3"], ["G2", "B2", "D3"]]
    mel = [("E5", 2), ("G5", 2), ("C6", 4), ("G5", 2), ("E5", 2), ("D5", 2),
           ("C5", 4), ("E5", 4), ("A5", 4), ("G5", 4),
           ("F5", 2), ("A5", 2), ("C6", 4), ("A5", 4), ("F5", 4),
           ("G5", 2), ("B5", 2), ("D6", 4), ("B5", 4), ("G5", 4)]
    for b in range(bars):
        bt = b * step * 16
        ch = prog[b % len(prog)]
        chord_render(mx, bt, step * 16, ch, lambda f, d: pad_tone(f, d, 0.1, sr=sr), 0.8)
        seq_render(mx, bt, step * 2, ch * 4, lambda f, d: pluck(f, d, 0.22, sr=sr), 0.6)
        mx.add(bass_tone(note_freq(ch[0][0] + "2"), step * 8, 0.4, sr=sr), bt)
        _drums(mx, bt, step, "K..HH..HK..HH..H", 0.7, seed=b * 41, sr=sr)
    t = step * 4
    for nm, mult in mel:
        mx.add(lead_tone(note_freq(nm), step * mult * 0.9, 0.3, 0.28, r=0.08, sr=sr), t)
        t += step * mult
        if t > step * 16 * bars:
            break
    mx.fade_in(0.3)
    mx.fade_out(0.6)
    return delay(mx.out(), 0.25, 0.26, 0.26, sr=sr)


# BGM 表：name -> (合成函数, 是否无缝循环)。
# 结算曲 victory / gameover 只播一次，其余为循环曲（写盘时带 smpl 循环块）。
BGM = {
    "menu": (bgm_menu, True),
    "dungeon_1": (lambda: bgm_dungeon(1), True),
    "dungeon_2": (lambda: bgm_dungeon(2), True),
    "dungeon_3": (lambda: bgm_dungeon(3), True),
    "boss": (bgm_boss, True),
    "shop": (bgm_shop, True),
    "victory": (bgm_victory, False),
    "gameover": (bgm_gameover, False),
}


# ==================================================================== 入口

def main() -> int:
    import sys
    bgm_only = "--bgm-only" in sys.argv
    n = 0
    if not bgm_only:
        for name, fn in SFX.items():
            write_wav("audio/sfx/%s.wav" % name, fn())
            n += 1
        print("[gen_audio] 音效 %d 个" % n)
    else:
        print("[gen_audio] --bgm-only：跳过全部音效（sfx 目录零改动）")
    m = 0
    for name, (fn, loop) in BGM.items():
        p = write_wav("audio/bgm/%s.wav" % name, fn(), sr=SR_BGM, loop=loop)
        m += 1
        print("  - bgm/%-10s %.1f KB%s" % (name, os.path.getsize(p) / 1024.0,
                                           "  [loop]" if loop else ""))
    print("[gen_audio] 背景音乐 %d 首" % m)
    return n + m


if __name__ == "__main__":
    main()

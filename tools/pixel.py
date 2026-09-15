# -*- coding: utf-8 -*-
"""pixel.py —— 原创像素素材绘制库。

本工程所有美术素材都由 tools/ 下的脚本程序化生成，不引用任何外部素材，
因此不存在版权问题。本文件提供一套面向"像素画"的底层绘制能力：

- Spr        : RGBA 画布（numpy 数组），支持点/矩形/椭圆/直线/多边形绘制
- outline    : 给不透明像素加统一描边（经典像素画做法）
- bevel      : 顶边提亮、底边压暗，制造体积感
- dither     : 棋盘抖动，用于地面/墙壁的粗糙质感
- trim/center: 裁掉透明边并把内容居中到指定画布，保证锚点一致

坐标单位一律是"1 像素 = 1 游戏像素"，最终在 Godot 里用 3 倍相机缩放显示。
"""
from __future__ import annotations

import os
from typing import Iterable, Sequence, Tuple, Union

import numpy as np
from PIL import Image

# ---------------------------------------------------------------- 路径

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(TOOL_DIR)
ASSETS_ROOT = os.path.join(PROJECT_ROOT, "assets")


def out_path(rel: str) -> str:
    """把 assets/ 下的相对路径转成绝对路径，并自动建目录。"""
    rel = rel.replace("\\", "/")
    if rel.startswith("assets/"):
        rel = rel[len("assets/"):]
    full = os.path.join(ASSETS_ROOT, *rel.split("/"))
    os.makedirs(os.path.dirname(full), exist_ok=True)
    return full


# ---------------------------------------------------------------- 调色板
# 统一的"霓虹地窟"配色：冷色石底 + 青色晶体 + 暖色点缀。
# 所有生成器都从这里取色，保证整体风格一致。

PAL = {
    # 描边 / 底色
    "outline":    (20, 20, 30),
    "void":       (12, 12, 20),
    "shadow":     (8, 8, 14),

    # 石材（地面 / 墙体）
    "stone_0":    (32, 32, 46),
    "stone_1":    (39, 39, 56),
    "stone_2":    (48, 48, 68),
    "stone_3":    (60, 60, 82),
    "stone_hi":   (78, 78, 104),
    "wall_top":   (44, 44, 62),
    "wall_face":  (26, 26, 38),
    "wall_edge":  (58, 58, 80),

    # 晶体（青）
    "cry_dk":     (23, 106, 110),
    "cry":        (47, 189, 186),
    "cry_lt":     (140, 240, 234),
    "cry_glow":   (206, 255, 252),

    # 暖色
    "gold_dk":    (166, 122, 44),
    "gold":       (255, 209, 102),
    "gold_lt":    (255, 236, 179),
    "red_dk":     (140, 34, 58),
    "red":        (239, 71, 111),
    "red_lt":     (255, 143, 168),
    "green_dk":   (6, 130, 100),
    "green":      (6, 214, 160),
    "green_lt":   (140, 255, 214),
    "purple_dk":  (78, 44, 132),
    "purple":     (155, 93, 229),
    "purple_lt":  (206, 168, 255),
    "blue_dk":    (34, 56, 96),
    "blue":       (74, 111, 165),
    "blue_lt":    (140, 178, 232),

    # 角色
    "skin":       (242, 196, 141),
    "skin_dk":    (206, 152, 100),
    "armor":      (74, 111, 165),
    "armor_lt":   (122, 160, 214),
    "armor_dk":   (40, 62, 98),
    "cloth":      (47, 74, 114),
    "cloth_dk":   (30, 48, 76),
    "metal":      (168, 178, 196),
    "metal_dk":   (104, 112, 128),
    "metal_lt":   (216, 224, 238),
    "visor":      (24, 34, 48),
    "white":      (245, 248, 255),
    "black":      (10, 10, 16),

    # 敌人
    "husk":       (122, 92, 196),
    "husk_dk":    (74, 52, 132),
    "husk_lt":    (176, 148, 240),
    "eye_body":   (74, 95, 122),
    "eye_dk":     (44, 58, 78),
    "eye_lt":     (126, 152, 184),
    "spore":      (6, 214, 160),
    "spore_dk":   (10, 130, 100),
    "spore_lt":   (160, 255, 214),

    # Boss
    "warden":     (96, 108, 148),
    "warden_dk":  (54, 62, 92),
    "warden_lt":  (150, 164, 208),
    "weaver":     (126, 60, 140),
    "weaver_dk":  (74, 32, 88),
    "weaver_lt":  (196, 130, 220),
}


Color = Tuple[int, int, int]
ColorLike = Union[str, Sequence[int], Tuple[int, int, int, int]]


def mix(a: Color, b: Color, t: float) -> Color:
    """线性混色，t=0 取 a，t=1 取 b。"""
    t = max(0.0, min(1.0, t))
    return (
        int(round(a[0] + (b[0] - a[0]) * t)),
        int(round(a[1] + (b[1] - a[1]) * t)),
        int(round(a[2] + (b[2] - a[2]) * t)),
    )


def shade(c: Color, amount: float) -> Color:
    """amount>0 提亮（向白混），amount<0 压暗（向黑混）。"""
    if amount >= 0:
        return mix(c, (255, 255, 255), amount)
    return mix(c, (0, 0, 0), -amount)


def to_rgba(c) -> Tuple[int, int, int, int]:
    if isinstance(c, str):
        c = PAL[c]
    if len(c) == 3:
        return (int(c[0]), int(c[1]), int(c[2]), 255)
    return (int(c[0]), int(c[1]), int(c[2]), int(c[3]))


# ---------------------------------------------------------------- 画布


class Spr:
    """RGBA 像素画布。"""

    def __init__(self, w: int, h: int):
        self.w = int(w)
        self.h = int(h)
        self.a = np.zeros((self.h, self.w, 4), dtype=np.uint8)

    # ---- 基础绘制 ----

    def px(self, x: int, y: int, c) -> None:
        x = int(round(x))
        y = int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.a[y, x] = to_rgba(c)

    def rect(self, x: int, y: int, w: int, h: int, c) -> None:
        for j in range(int(y), int(y + h)):
            for i in range(int(x), int(x + w)):
                self.px(i, j, c)

    def frame_rect(self, x: int, y: int, w: int, h: int, c) -> None:
        self.hline(x, y, w, c)
        self.hline(x, y + h - 1, w, c)
        self.vline(x, y, h, c)
        self.vline(x + w - 1, y, h, c)

    def hline(self, x: int, y: int, w: int, c) -> None:
        for i in range(int(x), int(x + w)):
            self.px(i, y, c)

    def vline(self, x: int, y: int, h: int, c) -> None:
        for j in range(int(y), int(y + h)):
            self.px(x, j, c)

    def line(self, x0: float, y0: float, x1: float, y1: float, c) -> None:
        x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
        dx, dy = abs(x1 - x0), abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx - dy
        steps = 0
        while steps < 4096:
            self.px(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 > -dy:
                err -= dy
                x0 += sx
            if e2 < dx:
                err += dx
                y0 += sy
            steps += 1

    def ell(self, cx: float, cy: float, rx: float, ry: float, c) -> None:
        rx = max(0.5, float(rx))
        ry = max(0.5, float(ry))
        for j in range(int(np.floor(cy - ry)) - 1, int(np.ceil(cy + ry)) + 2):
            for i in range(int(np.floor(cx - rx)) - 1, int(np.ceil(cx + rx)) + 2):
                dx = (i - cx) / rx
                dy = (j - cy) / ry
                if dx * dx + dy * dy <= 1.0:
                    self.px(i, j, c)

    def ring(self, cx: float, cy: float, rx: float, ry: float, c, thickness: float = 1.0) -> None:
        rx = max(0.5, float(rx))
        ry = max(0.5, float(ry))
        inner_r = max(0.0, 1.0 - thickness / max(rx, ry))
        for j in range(int(np.floor(cy - ry)) - 1, int(np.ceil(cy + ry)) + 2):
            for i in range(int(np.floor(cx - rx)) - 1, int(np.ceil(cx + rx)) + 2):
                dx = (i - cx) / rx
                dy = (j - cy) / ry
                v = dx * dx + dy * dy
                if v <= 1.0 and v >= inner_r * inner_r:
                    self.px(i, j, c)

    def poly(self, points: Sequence[Sequence[float]], c) -> None:
        pts = [(float(p[0]), float(p[1])) for p in points]
        ys = [p[1] for p in pts]
        for j in range(int(min(ys)), int(max(ys)) + 1):
            xs = []
            n = len(pts)
            for k in range(n):
                x0, y0 = pts[k]
                x1, y1 = pts[(k + 1) % n]
                if (y0 <= j < y1) or (y1 <= j < y0):
                    t = (j - y0) / (y1 - y0)
                    xs.append(x0 + (x1 - x0) * t)
            if len(xs) >= 2:
                xs.sort()
                for i in range(int(round(xs[0])), int(round(xs[-1])) + 1):
                    self.px(i, j, c)

    def tri(self, x0, y0, x1, y1, x2, y2, c) -> None:
        self.poly([(x0, y0), (x1, y1), (x2, y2)], c)

    def paste(self, other: "Spr", x: int, y: int, alpha: float = 1.0) -> None:
        for j in range(other.h):
            for i in range(other.w):
                col = other.a[j, i]
                if col[3] == 0:
                    continue
                if alpha >= 1.0:
                    self.px(x + i, y + j, tuple(col))
                else:
                    a = int(col[3] * alpha)
                    self.px(x + i, y + j, (col[0], col[1], col[2], a))

    # ---- 变换 ----

    def mirror(self) -> "Spr":
        s = Spr(self.w, self.h)
        s.a = self.a[:, ::-1, :].copy()
        return s

    def flip_v(self) -> "Spr":
        s = Spr(self.w, self.h)
        s.a = self.a[::-1, :, :].copy()
        return s

    def rotated_copy(self, angle_deg: float) -> "Spr":
        """按 90 度整数倍旋转（避免插值破坏像素）。"""
        s = Spr(self.w, self.h)
        k = (int(round(angle_deg / 90.0)) % 4)
        s.a = np.rot90(self.a, k).copy()
        return s

    def bbox(self):
        alpha = self.a[:, :, 3]
        ys, xs = np.where(alpha > 0)
        if len(xs) == 0:
            return None
        return (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))

    def trimmed(self, pad: int = 0) -> "Spr":
        bb = self.bbox()
        if bb is None:
            return Spr(1, 1)
        x0, y0, x1, y1 = bb
        x0 = max(0, x0 - pad)
        y0 = max(0, y0 - pad)
        x1 = min(self.w - 1, x1 + pad)
        y1 = min(self.h - 1, y1 + pad)
        s = Spr(x1 - x0 + 1, y1 - y0 + 1)
        s.a = self.a[y0:y1 + 1, x0:x1 + 1, :].copy()
        return s

    def centered(self, w: int, h: int, dx: int = 0, dy: int = 0) -> "Spr":
        """把当前内容居中放进 w×h 画布（可加偏移），用于统一锚点。"""
        s = Spr(w, h)
        bb = self.bbox()
        if bb is None:
            return s
        x0, y0, x1, y1 = bb
        cw, ch = x1 - x0 + 1, y1 - y0 + 1
        ox = (w - cw) // 2 - x0 + dx
        oy = (h - ch) // 2 - y0 + dy
        s.paste(self, ox, oy)
        return s

    # ---- 后处理 ----

    def outline(self, color: ColorLike = "outline", diag: bool = True) -> "Spr":
        alpha = self.a[:, :, 3] > 0
        pad = np.zeros((self.h + 2, self.w + 2), dtype=bool)
        pad[1:-1, 1:-1] = alpha
        dil = pad.copy()
        offs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        if diag:
            offs += [(-1, -1), (-1, 1), (1, -1), (1, 1)]
        for oy, ox in offs:
            dil |= np.roll(np.roll(pad, oy, axis=0), ox, axis=1)
        dil = dil[1:-1, 1:-1]
        mask = dil & (~alpha)
        col = to_rgba(color)
        self.a[mask] = np.array(col, dtype=np.uint8)
        return self

    def bevel(self, light: float = 0.22, dark: float = 0.26) -> "Spr":
        """上边缘提亮、下边缘压暗，制造像素体积感。"""
        alpha = self.a[:, :, 3] > 0
        top = np.zeros_like(alpha)
        top[1:, :] = alpha[1:, :] & ~alpha[:-1, :]
        bot = np.zeros_like(alpha)
        bot[:-1, :] = alpha[:-1, :] & ~alpha[1:, :]
        rgb = self.a[:, :, :3].astype(np.float32)
        if light > 0:
            rgb[top] = np.clip(rgb[top] * (1.0 + light) + 12.0 * light, 0, 255)
        if dark > 0:
            rgb[bot] = np.clip(rgb[bot] * (1.0 - dark), 0, 255)
        self.a[:, :, :3] = rgb.astype(np.uint8)
        return self

    def recolor(self, mapping: dict) -> "Spr":
        """按 RGB 精确替换颜色（用于同一造型做配色变体 / 精英怪）。"""
        for src, dst in mapping.items():
            s = to_rgba(src)[:3]
            d = to_rgba(dst)
            m = np.all(self.a[:, :, :3] == np.array(s, dtype=np.uint8), axis=-1)
            m &= self.a[:, :, 3] > 0
            self.a[m] = np.array(d, dtype=np.uint8)
        return self

    def tint_multiply(self, color: ColorLike, strength: float = 1.0) -> "Spr":
        c = to_rgba(color)[:3]
        rgb = self.a[:, :, :3].astype(np.float32)
        f = np.array(c, dtype=np.float32) / 255.0
        out = rgb * (1.0 - strength) + rgb * f * strength
        self.a[:, :, :3] = np.clip(out, 0, 255).astype(np.uint8)
        return self

    def alpha_scale(self, factor: float) -> "Spr":
        self.a[:, :, 3] = np.clip(self.a[:, :, 3].astype(np.float32) * factor, 0, 255).astype(np.uint8)
        return self

    def radial_alpha(self, cx: float, cy: float, radius: float, soft: float = 1.0) -> "Spr":
        """按到中心的距离做径向渐隐（光晕 / 粒子常用）。"""
        yy, xx = np.mgrid[0:self.h, 0:self.w]
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / max(radius, 1e-6)
        f = np.clip((1.0 - d) * soft, 0.0, 1.0)
        self.a[:, :, 3] = np.clip(self.a[:, :, 3].astype(np.float32) * f, 0, 255).astype(np.uint8)
        return self

    # ---- 输出 ----

    def image(self) -> Image.Image:
        return Image.fromarray(self.a, "RGBA")

    def save(self, rel: str) -> str:
        path = out_path(rel)
        self.image().save(path)
        return path


def dither(spr: Spr, x: int, y: int, w: int, h: int, color: ColorLike, density: float = 0.25,
           rng: np.random.Generator | None = None, parity: bool = False) -> None:
    """在矩形区域内点缀像素。parity=True 用棋盘格，否则用随机密度。"""
    for j in range(y, y + h):
        for i in range(x, x + w):
            if parity:
                if (i + j) % 2 == 0:
                    spr.px(i, j, color)
            else:
                if rng is not None and rng.random() < density:
                    spr.px(i, j, color)


def glow_disc(w: int, h: int, color: ColorLike, radius: float | None = None, soft: float = 1.6) -> Spr:
    """柔和圆形光斑（粒子 / 光晕贴图）。"""
    s = Spr(w, h)
    r = radius if radius is not None else min(w, h) * 0.5
    s.rect(0, 0, w, h, color)
    s.radial_alpha(w * 0.5 - 0.5, h * 0.5 - 0.5, r, soft)
    return s


def save_all(items: Iterable[Tuple[Spr, str]]) -> list:
    paths = []
    for spr, rel in items:
        paths.append(spr.save(rel))
    return paths

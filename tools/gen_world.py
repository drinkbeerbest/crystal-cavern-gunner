# -*- coding: utf-8 -*-
"""gen_world.py —— 生成地牢世界素材（地砖 / 墙体 / 门 / 传送门 / 道具）。

全部由代码程序化绘制，不引用任何外部素材。
命名约定（后续 Godot 代码按此加载，勿改名）：

  tiles/floor_a_0.png ... floor_a_2.png   32x32  普通地面（3 个随机变体）
  tiles/floor_b_0.png ... floor_b_1.png   32x32  次级地面变体
  tiles/floor_crack.png                   32x32  裂缝地面
  tiles/floor_moss.png                    32x32  苔藓地面
  tiles/carpet_0.png / carpet_1.png       32x32  Boss 房地毯
  tiles/pit.png                           32x32  深坑（危险地形）
  tiles/wall_top_0.png / wall_top_1.png   32x32  墙顶面
  tiles/wall_face_0.png / wall_face_1.png 32x40  墙体正面（含 8px 阴影裙）
  tiles/wall_pillar.png                   32x40  立柱
  props/rock_0.png ... rock_1.png         24x20  障碍石块
  props/crystal_0.png ... crystal_2.png   16x20  装饰水晶（可打碎）
  props/crate.png                         22x22  木箱（可打碎）
  props/barrel.png                        18x22  桶（可打碎）
  props/torch_0.png ... torch_3.png       16x24  壁挂火把（动画）
  props/brazier_0.png ... brazier_3.png   20x26  落地火盆（动画）
  props/chest_closed.png / chest_open.png 22x20  宝箱
  props/altar_0.png ... altar_3.png       26x26  祭坛（E 交互，晶体漂浮动画）
  props/shop_pad.png                      24x24  商店台座
  props/portal_0.png ... portal_7.png     44x56  层间传送门（动画）
  tiles/door_h_closed.png / _h_open.png   64x24  横向门（墙上的水平开口）
  tiles/door_v_closed.png / _v_open.png   24x64  纵向门
  tiles/door_h_boss.png / door_v_boss.png        Boss 房专用门
"""
from __future__ import annotations

import numpy as np

from pixel import PAL, Spr, dither, glow_disc, mix, shade


TILE = 32
RNG = np.random.default_rng(20260914)


# ------------------------------------------------------------------ 地面

def _stone_base(seed: int) -> Spr:
    """带随机裂纹与颗粒的石板地面。"""
    rng = np.random.default_rng(seed)
    s = Spr(TILE, TILE)
    s.rect(0, 0, TILE, TILE, PAL["stone_0"])
    # 大块明暗（石板拼贴感）
    dither(s, 0, 0, TILE, TILE, PAL["stone_1"], 0.30, rng)
    dither(s, 0, 0, TILE, TILE, PAL["stone_2"], 0.10, rng)
    # 石板缝
    s.hline(0, 0, TILE, PAL["stone_1"])
    s.vline(0, 0, TILE, PAL["stone_1"])
    for i in range(TILE):
        if (i + seed) % 7 == 0:
            s.px(i, 0, PAL["shadow"])
            s.px(0, i, PAL["shadow"])
    # 随机短裂纹
    for _ in range(2):
        x = int(rng.integers(3, TILE - 4))
        y = int(rng.integers(3, TILE - 4))
        for k in range(int(rng.integers(3, 7))):
            s.px(x, y, PAL["shadow"])
            x += int(rng.integers(-1, 2))
            y += int(rng.integers(0, 2))
    return s


def make_floor_a(v: int) -> Spr:
    s = _stone_base(100 + v * 17)
    s.bevel(0.06, 0.10)
    return s


def make_floor_b(v: int) -> Spr:
    s = _stone_base(300 + v * 29)
    s.tint_multiply(PAL["blue_dk"], 0.22)
    s.bevel(0.05, 0.08)
    return s


def make_floor_crack() -> Spr:
    s = _stone_base(555)
    # 一道贯穿的宽裂缝，缝里透出晶光
    pts = [(2, 6), (8, 10), (12, 18), (20, 20), (24, 27), (30, 30)]
    for i in range(len(pts) - 1):
        s.line(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], PAL["shadow"])
    for i in range(len(pts) - 1):
        s.line(pts[i][0], pts[i][1] - 1, pts[i + 1][0], pts[i + 1][1] - 1, PAL["cry_dk"])
    s.px(12, 17, PAL["cry"])
    s.px(20, 19, PAL["cry"])
    s.bevel(0.05, 0.08)
    return s


def make_floor_moss() -> Spr:
    s = _stone_base(777)
    rng = np.random.default_rng(8)
    dither(s, 0, 0, TILE, TILE, PAL["green_dk"], 0.22, rng)
    dither(s, 0, 0, TILE, TILE, PAL["spore_dk"], 0.08, rng)
    for _ in range(6):
        x = int(rng.integers(1, TILE - 2))
        y = int(rng.integers(1, TILE - 2))
        s.px(x, y, PAL["spore"])
    s.bevel(0.05, 0.08)
    return s


def make_carpet(v: int) -> Spr:
    s = Spr(TILE, TILE)
    s.rect(0, 0, TILE, TILE, PAL["red_dk"])
    rng = np.random.default_rng(11 + v)
    dither(s, 0, 0, TILE, TILE, shade(PAL["red_dk"], -0.25), 0.25, rng)
    s.frame_rect(1, 1, TILE - 2, TILE - 2, PAL["gold_dk"])
    # 中央菱形纹样
    c = TILE // 2
    s.poly([(c, c - 7), (c + 7, c), (c, c + 7), (c - 7, c)], PAL["gold_dk"])
    s.poly([(c, c - 4), (c + 4, c), (c, c + 4), (c - 4, c)], PAL["gold"])
    s.px(c, c, PAL["gold_lt"])
    return s


def make_pit() -> Spr:
    s = Spr(TILE, TILE)
    s.rect(0, 0, TILE, TILE, PAL["void"])
    rng = np.random.default_rng(3)
    dither(s, 0, 0, TILE, TILE, PAL["shadow"], 0.4, rng)
    # 边缘一圈石唇，中间纯黑
    s.frame_rect(0, 0, TILE, TILE, PAL["stone_1"])
    s.frame_rect(1, 1, TILE - 2, TILE - 2, PAL["stone_0"])
    s.rect(4, 4, TILE - 8, TILE - 8, PAL["black"])
    dither(s, 4, 4, TILE - 8, TILE - 8, PAL["void"], 0.5, rng)
    for i in range(4, TILE - 4, 5):
        s.px(i, 5, PAL["cry_dk"])
    return s


# ------------------------------------------------------------------ 墙体

def make_wall_top(v: int) -> Spr:
    s = Spr(TILE, TILE)
    s.rect(0, 0, TILE, TILE, PAL["wall_top"])
    rng = np.random.default_rng(21 + v * 13)
    dither(s, 0, 0, TILE, TILE, PAL["wall_edge"], 0.14, rng)
    dither(s, 0, 0, TILE, TILE, PAL["stone_1"], 0.16, rng)
    # 顶部受光条
    s.hline(0, 0, TILE, PAL["wall_edge"])
    s.hline(0, 1, TILE, mix(PAL["wall_top"], PAL["wall_edge"], 0.4))
    s.bevel(0.10, 0.16)
    return s


def make_wall_face(v: int) -> Spr:
    """墙体正面：上 32px 是砖面，下 8px 是投影裙边。"""
    h = 40
    s = Spr(TILE, h)
    s.rect(0, 0, TILE, 32, PAL["wall_face"])
    rng = np.random.default_rng(41 + v * 7)
    # 砖缝（错缝排布）
    for row in range(4):
        y = row * 8
        s.hline(0, y, TILE, PAL["shadow"])
        off = 0 if row % 2 == 0 else 8
        for bx in range(off, TILE, 16):
            s.vline(bx, y + 1, 7, PAL["shadow"])
        for bx in range(off, TILE, 16):
            s.hline(bx + 1, y + 1, 14, mix(PAL["wall_face"], PAL["wall_edge"], 0.35))
    dither(s, 0, 0, TILE, 32, PAL["stone_0"], 0.14, rng)
    # 底部投影裙
    s.rect(0, 32, TILE, 4, shade(PAL["shadow"], 0.06))
    s.rect(0, 36, TILE, 4, PAL["shadow"])
    for j in range(32, h):
        for i in range(TILE):
            c = s.a[j, i]
            if c[3] > 0:
                c[3] = max(60, 200 - (j - 32) * 40)
    s.bevel(0.08, 0.10)
    return s


def make_wall_pillar() -> Spr:
    s = Spr(TILE, 40)
    s.rect(2, 0, TILE - 4, 32, PAL["wall_face"])
    s.rect(2, 0, TILE - 4, 3, PAL["wall_edge"])
    s.rect(2, 28, TILE - 4, 4, PAL["shadow"])
    rng = np.random.default_rng(9)
    dither(s, 3, 4, TILE - 6, 24, PAL["stone_0"], 0.18, rng)
    # 柱身竖向高光
    s.vline(5, 4, 24, mix(PAL["wall_face"], PAL["wall_edge"], 0.5))
    s.vline(6, 4, 24, PAL["wall_edge"])
    s.rect(0, 32, TILE, 4, shade(PAL["shadow"], 0.06))
    s.rect(0, 36, TILE, 4, PAL["shadow"])
    for j in range(32, 40):
        for i in range(TILE):
            if s.a[j, i][3] > 0:
                s.a[j, i][3] = max(60, 200 - (j - 32) * 40)
    s.bevel(0.10, 0.12)
    return s


# ------------------------------------------------------------------ 障碍物 / 装饰

def make_rock(v: int) -> Spr:
    rng = np.random.default_rng(61 + v * 5)
    s = Spr(24, 20)
    s.poly([(3, 18), (2, 11), (6, 5), (12, 2), (18, 5), (22, 11), (21, 18)], PAL["stone_2"])
    s.poly([(6, 6), (12, 3), (17, 6), (13, 10), (8, 10)], PAL["stone_3"])
    dither(s, 0, 0, 24, 20, PAL["stone_1"], 0.25, rng)
    s.px(9, 5, PAL["stone_hi"])
    s.px(14, 6, PAL["stone_hi"])
    s.bevel(0.14, 0.22)
    s.outline(PAL["outline"])
    return s


def make_crystal(v: int) -> Spr:
    """可打碎的装饰水晶，三种高低形态。"""
    hs = [20, 16, 13]
    h = hs[v % 3]
    s = Spr(16, 20)
    top = 20 - h
    s.poly([(8, top), (12, top + h // 2), (10, 19), (6, 19), (4, top + h // 2)], PAL["cry_dk"])
    s.poly([(8, top + 1), (10, top + h // 2), (8, 18), (6, top + h // 2)], PAL["cry"])
    s.px(8, top + 2, PAL["cry_lt"])
    s.px(7, top + 4, PAL["cry_glow"])
    s.vline(6, top + 3, max(1, h - 5), PAL["cry_lt"])
    s.bevel(0.18, 0.14)
    s.outline(PAL["outline"])
    return s


def make_crate() -> Spr:
    s = Spr(22, 22)
    s.rect(1, 1, 20, 20, PAL["gold_dk"])
    s.rect(2, 2, 18, 18, shade(PAL["gold_dk"], -0.28))
    rng = np.random.default_rng(5)
    dither(s, 2, 2, 18, 18, shade(PAL["gold_dk"], -0.12), 0.3, rng)
    # X 形加固条
    s.line(2, 2, 19, 19, PAL["gold_dk"])
    s.line(19, 2, 2, 19, PAL["gold_dk"])
    s.frame_rect(1, 1, 20, 20, shade(PAL["gold_dk"], 0.18))
    s.hline(2, 2, 18, shade(PAL["gold"], -0.25))
    s.bevel(0.12, 0.20)
    s.outline(PAL["outline"])
    return s


def make_barrel() -> Spr:
    s = Spr(18, 22)
    s.rect(2, 3, 14, 18, PAL["gold_dk"])
    s.ell(9, 3, 7, 2.4, shade(PAL["gold_dk"], 0.12))
    rng = np.random.default_rng(7)
    dither(s, 2, 5, 14, 14, shade(PAL["gold_dk"], -0.18), 0.32, rng)
    # 桶箍
    for y in (7, 15):
        s.hline(2, y, 14, PAL["metal_dk"])
        s.hline(2, y + 1, 14, PAL["metal"])
    s.vline(4, 5, 14, shade(PAL["gold"], -0.4))
    s.bevel(0.12, 0.20)
    s.outline(PAL["outline"])
    return s


def make_torch(frame: int) -> Spr:
    """壁挂火把：铁托 + 跳动的青色灵焰。"""
    s = Spr(16, 24)
    s.rect(6, 13, 4, 9, PAL["metal_dk"])
    s.rect(6, 13, 4, 1, PAL["metal"])
    s.rect(4, 21, 8, 2, PAL["metal_dk"])
    s.frame_rect(5, 10, 6, 4, PAL["metal"])
    s.rect(6, 11, 4, 2, PAL["metal_dk"])
    # 火焰（4 帧抖动）
    wob = [0, 1, -1, 1][frame % 4]
    hgt = [9, 10, 8, 10][frame % 4]
    cx = 8 + wob
    base = 10
    s.poly([(cx - 4, base), (cx - 3, base - hgt + 3), (cx, base - hgt),
            (cx + 3, base - hgt + 3), (cx + 4, base)], PAL["cry_dk"])
    s.poly([(cx - 2, base), (cx - 2, base - hgt + 4), (cx, base - hgt + 2),
            (cx + 2, base - hgt + 4), (cx + 2, base)], PAL["cry"])
    s.poly([(cx - 1, base), (cx, base - hgt + 5), (cx + 1, base)], PAL["cry_glow"])
    s.px(cx, base - 1, PAL["white"])
    return s


def make_brazier(frame: int) -> Spr:
    """落地火盆：石座 + 紫色妖焰。"""
    s = Spr(20, 26)
    # 石座
    s.poly([(3, 25), (4, 18), (16, 18), (17, 25)], PAL["stone_2"])
    s.rect(2, 15, 16, 4, PAL["stone_3"])
    s.hline(2, 15, 16, PAL["stone_hi"])
    dither(s, 3, 19, 14, 6, PAL["stone_1"], 0.3, np.random.default_rng(13))
    s.bevel(0.10, 0.18)
    s.outline(PAL["outline"])
    # 妖焰
    wob = [0, 1, 0, -1][frame % 4]
    hgt = [11, 12, 10, 12][frame % 4]
    cx = 10 + wob
    base = 15
    s.poly([(cx - 5, base), (cx - 4, base - hgt + 4), (cx - 1, base - hgt),
            (cx + 2, base - hgt + 3), (cx + 5, base)], PAL["purple_dk"])
    s.poly([(cx - 3, base), (cx - 2, base - hgt + 5), (cx, base - hgt + 2),
            (cx + 3, base - hgt + 5), (cx + 3, base)], PAL["purple"])
    s.poly([(cx - 1, base), (cx, base - hgt + 6), (cx + 1, base)], PAL["purple_lt"])
    s.px(cx, base - 1, PAL["white"])
    return s


def make_chest(opened: bool) -> Spr:
    s = Spr(22, 20)
    # 箱体
    s.rect(2, 9, 18, 10, PAL["gold_dk"])
    rng = np.random.default_rng(17)
    dither(s, 2, 9, 18, 10, shade(PAL["gold_dk"], -0.2), 0.3, rng)
    s.frame_rect(2, 9, 18, 10, shade(PAL["gold_dk"], 0.2))
    # 盖
    if opened:
        s.poly([(2, 8), (2, 2), (20, 2), (20, 8)], shade(PAL["gold_dk"], -0.35))
        s.hline(2, 2, 18, PAL["metal_dk"])
        s.rect(4, 5, 14, 3, PAL["black"])
        s.px(8, 6, PAL["gold"])
        s.px(13, 6, PAL["gold"])
    else:
        s.poly([(2, 9), (3, 3), (19, 3), (20, 9)], PAL["gold"])
        s.hline(3, 3, 17, PAL["gold_lt"])
        dither(s, 3, 4, 16, 5, shade(PAL["gold_dk"], -0.1), 0.3, rng)
        s.hline(2, 8, 18, PAL["metal_dk"])
        # 锁
        s.rect(9, 7, 4, 6, PAL["metal_dk"])
        s.rect(10, 8, 2, 4, PAL["metal"])
        s.px(10, 10, PAL["gold_lt"])
    s.bevel(0.14, 0.22)
    s.outline(PAL["outline"])
    return s


def make_altar(frame: int = 0) -> Spr:
    """祭坛：E 键交互，给一个随机天赋。

    frame 0..3 让悬浮晶体上下漂浮、光晕呼吸，台阶与符文柱保持不动。
    """
    f = frame % 4
    s = Spr(26, 26)
    # 台阶
    s.rect(1, 21, 24, 5, PAL["stone_2"])
    s.rect(3, 17, 20, 5, PAL["stone_3"])
    s.hline(1, 21, 24, PAL["stone_hi"])
    s.hline(3, 17, 20, PAL["stone_hi"])
    dither(s, 3, 18, 20, 8, PAL["stone_1"], 0.25, np.random.default_rng(23))
    # 中央符文柱
    s.rect(10, 9, 6, 9, PAL["stone_3"])
    s.vline(10, 9, 9, PAL["stone_hi"])
    # 悬浮晶体：按帧上下漂浮 1px
    dy = (0, -1, -1, 0)[f]
    s.poly([(13, 1 + dy), (17, 6 + dy), (13, 12 + dy), (9, 6 + dy)], PAL["cry_dk"])
    s.poly([(13, 2 + dy), (15, 6 + dy), (13, 10 + dy), (11, 6 + dy)], PAL["cry"])
    s.px(13, 4 + dy, PAL["cry_glow"])
    # 光晕呼吸：中段两帧多点亮一颗高光
    if f in (1, 2):
        s.px(13, 8 + dy, PAL["cry_glow"])
        s.px(12, 6 + dy, PAL["cry_glow"])
    else:
        s.px(14, 7 + dy, PAL["cry"])
    s.bevel(0.14, 0.20)
    s.outline(PAL["outline"])
    return s


def make_shop_pad() -> Spr:
    s = Spr(24, 24)
    s.ell(12, 16, 11, 6, PAL["stone_2"])
    s.ell(12, 15, 9, 4.5, PAL["stone_3"])
    s.ring(12, 15, 9, 4.5, PAL["gold_dk"], thickness=1.2)
    dither(s, 2, 10, 20, 12, PAL["stone_1"], 0.22, np.random.default_rng(31))
    # 中央金币标记
    s.ell(12, 14, 3, 3, PAL["gold_dk"])
    s.ell(12, 14, 2, 2, PAL["gold"])
    s.px(11, 13, PAL["gold_lt"])
    s.bevel(0.12, 0.18)
    s.outline(PAL["outline"])
    return s


def make_portal(frame: int) -> Spr:
    """层间传送门：石框 + 旋转能量涡（8 帧）。"""
    s = Spr(44, 56)
    # 石框
    s.rect(4, 6, 6, 44, PAL["stone_2"])
    s.rect(34, 6, 6, 44, PAL["stone_2"])
    s.rect(4, 2, 36, 6, PAL["stone_3"])
    s.rect(2, 48, 40, 6, PAL["stone_2"])
    dither(s, 4, 6, 36, 44, PAL["stone_1"], 0.18, np.random.default_rng(37))
    s.hline(4, 2, 36, PAL["stone_hi"])
    s.vline(4, 6, 44, PAL["stone_hi"])
    s.vline(39, 6, 44, PAL["shadow"])
    # 门洞底色
    s.rect(10, 8, 24, 40, PAL["void"])
    # 涡流：3 层旋转椭圆环
    cx, cy = 22, 28
    for layer in range(3):
        ang = (frame + layer * 2) * 45.0
        rx = 11 - layer * 2.5
        ry = 18 - layer * 4.0
        col = [PAL["cry_dk"], PAL["cry"], PAL["cry_lt"]][layer]
        for t in range(12):
            a = np.radians(ang + t * 30.0)
            x = int(round(cx + np.cos(a) * rx))
            y = int(round(cy + np.sin(a) * ry * 0.9))
            if 10 <= x < 34 and 8 <= y < 48:
                s.px(x, y, col)
    # 中心亮核
    core = glow_disc(14, 16, PAL["cry_glow"], 6.5, 1.5)
    s.paste(core, 15, 20, alpha=0.85)
    s.px(cx, cy, PAL["white"])
    s.px(cx - 1, cy - 2, PAL["white"])
    s.bevel(0.10, 0.16)
    s.outline(PAL["outline"])
    return s


def make_door(horizontal: bool, opened: bool, boss: bool) -> Spr:
    """门：关闭时是金属闸板，打开时只留两侧门框。"""
    if horizontal:
        w, h = 64, 24
    else:
        w, h = 24, 64
    s = Spr(w, h)
    s.rect(0, 0, w, h, PAL["stone_1"])
    dither(s, 0, 0, w, h, PAL["stone_0"], 0.22, np.random.default_rng(43))
    metal = PAL["gold_dk"] if boss else PAL["metal_dk"]
    metal_lt = PAL["gold"] if boss else PAL["metal"]
    frame_w = 5 if horizontal else 5
    # 门框（始终存在）
    if horizontal:
        s.rect(0, 0, frame_w, h, PAL["stone_2"])
        s.rect(w - frame_w, 0, frame_w, h, PAL["stone_2"])
        s.hline(0, 0, w, PAL["stone_3"])
    else:
        s.rect(0, 0, w, frame_w, PAL["stone_2"])
        s.rect(0, h - frame_w, w, frame_w, PAL["stone_2"])
        s.vline(0, 0, h, PAL["stone_3"])
    if opened:
        # 只剩门框，中间是通道
        if horizontal:
            s.rect(frame_w, 0, w - 2 * frame_w, h, PAL["stone_0"])
            dither(s, frame_w, 0, w - 2 * frame_w, h, PAL["stone_1"], 0.25, np.random.default_rng(47))
            s.hline(frame_w, 0, w - 2 * frame_w, PAL["stone_2"])
            s.hline(frame_w, h - 1, w - 2 * frame_w, PAL["shadow"])
        else:
            s.rect(0, frame_w, w, h - 2 * frame_w, PAL["stone_0"])
            dither(s, 0, frame_w, w, h - 2 * frame_w, PAL["stone_1"], 0.25, np.random.default_rng(47))
            s.vline(0, frame_w, h - 2 * frame_w, PAL["stone_2"])
            s.vline(w - 1, frame_w, h - 2 * frame_w, PAL["shadow"])
    else:
        # 闸板
        if horizontal:
            s.rect(frame_w, 2, w - 2 * frame_w, h - 4, metal)
            for i in range(frame_w + 2, w - frame_w - 2, 6):
                s.vline(i, 3, h - 6, shade(metal, -0.3))
                s.vline(i + 1, 3, h - 6, shade(metal, 0.12))
            s.hline(frame_w, 2, w - 2 * frame_w, metal_lt)
            s.hline(frame_w, h - 3, w - 2 * frame_w, shade(metal, -0.45))
            # 中央徽记
            c = w // 2
            s.poly([(c, h // 2 - 4), (c + 4, h // 2), (c, h // 2 + 4), (c - 4, h // 2)],
                   PAL["red_dk"] if boss else PAL["cry_dk"])
            s.poly([(c, h // 2 - 2), (c + 2, h // 2), (c, h // 2 + 2), (c - 2, h // 2)],
                   PAL["red"] if boss else PAL["cry"])
        else:
            s.rect(2, frame_w, w - 4, h - 2 * frame_w, metal)
            for j in range(frame_w + 2, h - frame_w - 2, 6):
                s.hline(3, j, w - 6, shade(metal, -0.3))
                s.hline(3, j + 1, w - 6, shade(metal, 0.12))
            s.vline(2, frame_w, h - 2 * frame_w, metal_lt)
            s.vline(w - 3, frame_w, h - 2 * frame_w, shade(metal, -0.45))
            c = h // 2
            s.poly([(w // 2 - 4, c), (w // 2, c - 4), (w // 2 + 4, c), (w // 2, c + 4)],
                   PAL["red_dk"] if boss else PAL["cry_dk"])
            s.poly([(w // 2 - 2, c), (w // 2, c - 2), (w // 2 + 2, c), (w // 2, c + 2)],
                   PAL["red"] if boss else PAL["cry"])
    s.bevel(0.10, 0.18)
    s.outline(PAL["outline"])
    return s


# ------------------------------------------------------------------ 入口

def gen_tiles() -> int:
    n = 0
    for v in range(3):
        make_floor_a(v).save("tiles/floor_a_%d.png" % v); n += 1
    for v in range(2):
        make_floor_b(v).save("tiles/floor_b_%d.png" % v); n += 1
    make_floor_crack().save("tiles/floor_crack.png"); n += 1
    make_floor_moss().save("tiles/floor_moss.png"); n += 1
    for v in range(2):
        make_carpet(v).save("tiles/carpet_%d.png" % v); n += 1
    make_pit().save("tiles/pit.png"); n += 1
    for v in range(2):
        make_wall_top(v).save("tiles/wall_top_%d.png" % v); n += 1
        make_wall_face(v).save("tiles/wall_face_%d.png" % v); n += 1
    make_wall_pillar().save("tiles/wall_pillar.png"); n += 1
    return n


def gen_props() -> int:
    n = 0
    for v in range(2):
        make_rock(v).save("props/rock_%d.png" % v); n += 1
    for v in range(3):
        make_crystal(v).save("props/crystal_%d.png" % v); n += 1
    make_crate().save("props/crate.png"); n += 1
    make_barrel().save("props/barrel.png"); n += 1
    for f in range(4):
        make_torch(f).save("props/torch_%d.png" % f); n += 1
        make_brazier(f).save("props/brazier_%d.png" % f); n += 1
    make_chest(False).save("props/chest_closed.png"); n += 1
    make_chest(True).save("props/chest_open.png"); n += 1
    for f in range(4):
        make_altar(f).save("props/altar_%d.png" % f); n += 1
    make_shop_pad().save("props/shop_pad.png"); n += 1
    for f in range(8):
        make_portal(f).save("props/portal_%d.png" % f); n += 1
    for hor in (True, False):
        tag = "h" if hor else "v"
        make_door(hor, False, False).save("tiles/door_%s_closed.png" % tag); n += 1
        make_door(hor, True, False).save("tiles/door_%s_open.png" % tag); n += 1
        make_door(hor, False, True).save("tiles/door_%s_boss.png" % tag); n += 1
    return n


def main() -> int:
    total = gen_tiles() + gen_props()
    print("[gen_world] 生成世界素材 %d 个" % total)
    return total


if __name__ == "__main__":
    main()

# -*- coding: utf-8 -*-
"""gen_fx.py —— 生成特效与拾取物素材。

命名约定（Godot 侧按此加载，勿改名）：

  fx/bullet_p_0.png / bullet_p_1.png      8x8    玩家能量弹（青）
  fx/bullet_shot.png                      6x6    霰弹丸
  fx/bullet_laser.png                     22x6   激光弹体
  fx/bullet_e_0.png / bullet_e_1.png      8x8    敌人弹（红）
  fx/bullet_boss.png                      14x14  Boss 弹（紫）
  fx/bullet_orb.png                       10x10  金色追踪弹
  fx/muzzle_0.png ... muzzle_2.png        18x18  枪口焰
  fx/explode_0.png ... explode_7.png      48x48  爆炸
  fx/hit_0.png ... hit_3.png              16x16  命中火花
  fx/spark_0.png ... spark_3.png          10x10  弹道火星
  fx/dust_0.png ... dust_3.png            12x12  脚步尘土
  fx/smoke_0.png ... smoke_3.png          18x18  烟雾
  fx/slash_0.png ... slash_3.png          26x26  近战挥砍
  fx/ring_0.png ... ring_3.png            40x40  冲击波环
  fx/glow_soft.png                        32x32  柔光（灯 / 高光叠加）
  fx/glow_hard.png                        16x16  硬光点
  fx/heal_0.png ... heal_3.png            16x16  治疗上升粒子
  fx/shield_pop_0.png ... _3.png          30x30  护盾破碎
  fx/level_ring_0.png ... _5.png          44x44  升级 / 拾取天赋光环
  fx/dash_trail.png                       16x16  冲刺残影
  fx/telegraph.png                        32x32  Boss 冲撞预警地面贴花

  pickups/coin_0.png ... coin_3.png       12x12  金币（旋转 4 帧）
  pickups/energy_0.png ... energy_3.png   12x12  能量球
  pickups/heart.png / heart_big.png       14/18  血包
  pickups/armor.png                       14x14  护盾片
  pickups/key.png                         14x14  房间钥匙
  pickups/weapon_box.png                  18x18  随机武器补给箱
  pickups/bomb_0.png ... bomb_3.png       14x14  炸弹（引信火星 4 帧）
  pickups/talent_speed.png 等 6 种        16x16  临时天赋
"""
from __future__ import annotations

import numpy as np

from pixel import PAL, Spr, dither, glow_disc, mix, shade


# ------------------------------------------------------------------ 子弹

def _bolt(w: int, h: int, core, mid, edge, tail_w: int) -> Spr:
    """横向能量弹：亮核 + 中层 + 外缘 + 拖尾。"""
    s = Spr(w, h)
    cy = h // 2
    s.ell(w * 0.5, cy + 0.5, w * 0.42, h * 0.42, edge)
    s.ell(w * 0.55, cy + 0.5, w * 0.30, h * 0.28, mid)
    s.ell(w * 0.58, cy + 0.5, w * 0.16, h * 0.15, core)
    # 拖尾
    for i in range(tail_w):
        x = max(0, int(w * 0.25) - i)
        a = 1.0 - (i + 1) / (tail_w + 1.0)
        s.px(x, cy, (mid[0], mid[1], mid[2], int(180 * a)))
        if h >= 6:
            s.px(x, cy - 1, (edge[0], edge[1], edge[2], int(90 * a)))
            s.px(x, cy + 1, (edge[0], edge[1], edge[2], int(90 * a)))
    return s


def make_bullet_p(v: int) -> Spr:
    wob = 0 if v == 0 else 1
    s = _bolt(8, 8, PAL["white"], PAL["cry_lt"], PAL["cry"], 2 + wob)
    return s


def make_bullet_shot() -> Spr:
    s = Spr(6, 6)
    s.ell(3, 3, 2.4, 2.4, PAL["gold_dk"])
    s.ell(3, 3, 1.5, 1.5, PAL["gold"])
    s.px(2, 2, PAL["gold_lt"])
    return s


def make_bullet_laser() -> Spr:
    s = Spr(22, 6)
    s.rect(1, 2, 20, 2, PAL["cry"])
    s.rect(2, 2, 18, 1, PAL["cry_lt"])
    s.rect(3, 2, 16, 1, PAL["white"])
    s.px(0, 2, PAL["cry_dk"]); s.px(0, 3, PAL["cry_dk"])
    s.px(21, 2, PAL["cry_glow"]); s.px(21, 3, PAL["cry_glow"])
    s.px(1, 1, (PAL["cry"][0], PAL["cry"][1], PAL["cry"][2], 120))
    s.px(1, 4, (PAL["cry"][0], PAL["cry"][1], PAL["cry"][2], 120))
    return s


def make_bullet_e(v: int) -> Spr:
    if v == 0:
        return _bolt(8, 8, PAL["white"], PAL["red_lt"], PAL["red"], 2)
    return _bolt(8, 8, PAL["white"], PAL["purple_lt"], PAL["purple"], 2)


def make_bullet_boss() -> Spr:
    s = Spr(14, 14)
    s.ell(7, 7, 6.2, 6.2, PAL["purple_dk"])
    s.ell(7, 7, 4.6, 4.6, PAL["purple"])
    s.ell(7, 7, 2.6, 2.6, PAL["purple_lt"])
    s.px(6, 5, PAL["white"]); s.px(7, 5, PAL["white"])
    for k in range(4):
        a = np.radians(k * 90.0 + 45.0)
        x = int(round(7 + np.cos(a) * 6))
        y = int(round(7 + np.sin(a) * 6))
        s.px(x, y, PAL["purple_lt"])
    return s


def make_bullet_orb() -> Spr:
    s = Spr(10, 10)
    s.ell(5, 5, 4.4, 4.4, PAL["gold_dk"])
    s.ell(5, 5, 3.2, 3.2, PAL["gold"])
    s.ell(4, 4, 1.4, 1.4, PAL["gold_lt"])
    s.px(4, 3, PAL["white"])
    return s


# ------------------------------------------------------------------ 枪口焰

def make_muzzle(frame: int) -> Spr:
    """枪口焰：3 帧由大到小。指向 +X，Godot 侧按角度旋转。"""
    s = Spr(18, 18)
    cy = 9
    scale = [1.0, 0.78, 0.55][frame % 3]
    ln = int(15 * scale)
    wd = max(1, int(5 * scale))
    s.poly([(2, cy), (2 + ln, cy - wd), (2 + ln + 2, cy), (2 + ln, cy + wd)], PAL["gold"])
    s.poly([(2, cy), (2 + int(ln * 0.7), cy - max(1, wd - 2)),
            (2 + int(ln * 0.7) + 1, cy), (2 + int(ln * 0.7), cy + max(1, wd - 2))], PAL["gold_lt"])
    s.rect(2, cy - 1, max(2, int(ln * 0.5)), 3, PAL["white"])
    glow = glow_disc(10, 10, PAL["gold_lt"], 4.6 * scale, 1.4)
    s.paste(glow, 1, cy - 5, alpha=0.6)
    return s


# ------------------------------------------------------------------ 爆炸

def make_explode(frame: int) -> Spr:
    """8 帧爆炸：白热核 -> 橙红膨胀 -> 碎屑飞散 -> 余烟。"""
    n = 8
    s = Spr(48, 48)
    t = frame / (n - 1.0)
    cx = cy = 24.0
    if t < 0.35:
        # 白热闪
        k = t / 0.35
        r = 6 + 16 * k
        core = glow_disc(48, 48, PAL["white"], r * 0.55, 1.6)
        s.paste(core, 0, 0, alpha=1.0)
        ring = glow_disc(48, 48, PAL["gold_lt"], r, 1.2)
        s.paste(ring, 0, 0, alpha=0.75)
    elif t < 0.7:
        k = (t - 0.35) / 0.35
        r = 20 + 6 * k
        outer = glow_disc(48, 48, PAL["red_dk"], r, 1.25)
        s.paste(outer, 0, 0, alpha=0.85)
        mid = glow_disc(48, 48, PAL["gold"], r * 0.68, 1.3)
        s.paste(mid, 0, 0, alpha=0.9)
        inner = glow_disc(48, 48, PAL["white"], r * 0.36, 1.5)
        s.paste(inner, 0, 0, alpha=1.0 - 0.3 * k)
    else:
        k = (t - 0.7) / 0.3
        r = 24 + 4 * k
        fade = 0.7 * (1.0 - k)
        outer = glow_disc(48, 48, PAL["red_dk"], r, 1.15)
        s.paste(outer, 0, 0, alpha=max(0.05, fade * 0.55))
        smoke = glow_disc(48, 48, PAL["stone_2"], r * 0.8, 1.0)
        s.paste(smoke, 0, 0, alpha=max(0.03, fade * 0.4))
    # 碎屑（各帧位置不同，越晚飞得越远越暗）
    rng = np.random.default_rng(frame * 13 + 7)
    for i in range(14):
        a = rng.random() * np.pi * 2
        d = (6 + rng.random() * 18) * (0.5 + t)
        x = int(round(cx + np.cos(a) * d))
        y = int(round(cy + np.sin(a) * d))
        if 0 <= x < 48 and 0 <= y < 48:
            col = PAL["gold_lt"] if t < 0.4 else (PAL["gold"] if t < 0.7 else PAL["red"])
            alpha = 255 if t < 0.7 else max(40, int(255 * (1.0 - (t - 0.7) / 0.3)))
            s.px(x, y, (col[0], col[1], col[2], alpha))
            if t < 0.5 and x + 1 < 48:
                s.px(x + 1, y, (col[0], col[1], col[2], alpha // 2))
    # 冲击环（前 4 帧）
    if frame < 4:
        rr = 8 + frame * 6
        s.ring(cx, cy, rr, rr * 0.92, PAL["gold_lt"], thickness=1.6)
    return s


def make_hit(frame: int) -> Spr:
    s = Spr(16, 16)
    cx = cy = 8.0
    r = 2.5 + frame * 1.7
    fade = 1.0 - frame / 4.0
    s.ring(cx, cy, r, r, PAL["white"], thickness=1.3)
    for k in range(6):
        a = k * np.pi / 3.0 + frame * 0.25
        x = int(round(cx + np.cos(a) * (r + 1.5)))
        y = int(round(cy + np.sin(a) * (r + 1.5)))
        if 0 <= x < 16 and 0 <= y < 16:
            s.px(x, y, PAL["gold_lt"])
    if fade < 0.55:
        s.alpha_scale(0.45 + fade)
    return s


def make_spark(frame: int) -> Spr:
    s = Spr(10, 10)
    n = 4
    r = 1.5 + frame * 1.1
    for k in range(n):
        a = k * np.pi * 2 / n + np.pi / 4 + frame * 0.2
        x = int(round(5 + np.cos(a) * r))
        y = int(round(5 + np.sin(a) * r))
        if 0 <= x < 10 and 0 <= y < 10:
            s.px(x, y, PAL["gold_lt"] if frame < 2 else PAL["gold"])
    s.px(5, 5, PAL["white"] if frame == 0 else PAL["gold"])
    if frame >= 2:
        s.alpha_scale(0.6)
    return s


def make_dust(frame: int) -> Spr:
    s = Spr(12, 12)
    rng = np.random.default_rng(frame * 5 + 2)
    r = 2.0 + frame * 1.6
    fade = 1.0 - frame / 4.0
    for _ in range(9):
        a = rng.random() * np.pi * 2
        d = rng.random() * r
        x = int(round(6 + np.cos(a) * d))
        y = int(round(6 + np.sin(a) * d * 0.7))
        if 0 <= x < 12 and 0 <= y < 12:
            s.px(x, y, PAL["stone_2"] if rng.random() < 0.6 else PAL["stone_3"])
    s.alpha_scale(max(0.12, fade * 0.85))
    return s


def make_smoke(frame: int) -> Spr:
    s = Spr(18, 18)
    rng = np.random.default_rng(frame * 11 + 3)
    r = 3.5 + frame * 2.2
    g = glow_disc(18, 18, PAL["stone_1"], r, 1.1)
    s.paste(g, 0, 0, alpha=0.7)
    for _ in range(10):
        x = int(9 + rng.normal(0, r * 0.45))
        y = int(9 + rng.normal(0, r * 0.45) - frame)
        if 0 <= x < 18 and 0 <= y < 18:
            s.px(x, y, PAL["stone_2"])
    s.alpha_scale(max(0.1, 0.8 - frame * 0.2))
    return s


def make_slash(frame: int) -> Spr:
    """近战挥砍弧：4 帧从细到宽再消散。"""
    s = Spr(26, 26)
    cx = cy = 13.0
    r = 7 + frame * 2.4
    thick = 2.6 - frame * 0.45
    a0 = -np.pi * 0.55
    a1 = np.pi * 0.35
    steps = 40
    for i in range(steps + 1):
        a = a0 + (a1 - a0) * i / steps
        x = cx + np.cos(a) * r
        y = cy + np.sin(a) * r
        for t in np.linspace(-thick, thick, max(2, int(thick * 3))):
            s.px(int(round(x + np.cos(a + np.pi / 2) * t)),
                 int(round(y + np.sin(a + np.pi / 2) * t)), PAL["cry_lt"])
    s.ring(cx, cy, r, r, PAL["white"], thickness=max(0.6, thick * 0.45))
    if frame >= 2:
        s.alpha_scale(0.75 - (frame - 2) * 0.25)
    return s


def make_ring(frame: int) -> Spr:
    s = Spr(40, 40)
    r = 6 + frame * 5.5
    col = [PAL["cry_glow"], PAL["cry_lt"], PAL["cry"], PAL["cry_dk"]][frame % 4]
    s.ring(20, 20, r, r * 0.95, col, thickness=2.0 - frame * 0.3)
    s.alpha_scale(1.0 - frame * 0.2)
    return s


def make_heal(frame: int) -> Spr:
    s = Spr(16, 16)
    rng = np.random.default_rng(frame * 3 + 1)
    for _ in range(5):
        x = int(8 + rng.normal(0, 3.2))
        y = int(13 - frame * 3 - rng.random() * 3)
        if 0 <= x < 16 and 0 <= y < 16:
            s.px(x, y, PAL["green_lt"] if rng.random() < 0.5 else PAL["green"])
            if y - 1 >= 0:
                s.px(x, y - 1, PAL["white"])
    s.alpha_scale(1.0 - frame * 0.18)
    return s


def make_shield_pop(frame: int) -> Spr:
    s = Spr(30, 30)
    cx = cy = 15.0
    r = 8 + frame * 3.0
    s.ring(cx, cy, r, r, PAL["blue_lt"], thickness=1.8 - frame * 0.3)
    rng = np.random.default_rng(frame + 9)
    for _ in range(8):
        a = rng.random() * np.pi * 2
        d = r + rng.random() * 3
        x = int(round(cx + np.cos(a) * d))
        y = int(round(cy + np.sin(a) * d))
        if 0 <= x < 30 and 0 <= y < 30:
            s.px(x, y, PAL["blue"] if rng.random() < 0.5 else PAL["blue_lt"])
    s.alpha_scale(1.0 - frame * 0.2)
    return s


def make_level_ring(frame: int) -> Spr:
    n = 6
    s = Spr(44, 44)
    t = frame / (n - 1.0)
    r = 4 + t * 18
    s.ring(22, 22, r, r * 0.6, PAL["gold_lt"], thickness=2.2 * (1.0 - t) + 0.6)
    s.ring(22, 22, r * 0.7, r * 0.42, PAL["white"], thickness=1.2 * (1.0 - t) + 0.4)
    # 上升光点
    rng = np.random.default_rng(frame * 7)
    for _ in range(7):
        a = rng.random() * np.pi * 2
        x = int(round(22 + np.cos(a) * r * 0.9))
        y = int(round(22 + np.sin(a) * r * 0.55 - t * 8))
        if 0 <= x < 44 and 0 <= y < 44:
            s.px(x, y, PAL["gold_lt"])
    s.alpha_scale(1.0 - t * 0.85)
    return s


def make_dash_trail() -> Spr:
    s = Spr(16, 16)
    g = glow_disc(16, 16, PAL["cry"], 7.0, 1.2)
    s.paste(g, 0, 0, alpha=0.75)
    s.ell(8, 8, 3.0, 5.5, PAL["cry_lt"])
    s.alpha_scale(0.6)
    return s


def make_telegraph() -> Spr:
    """Boss 冲撞预警：地面红黑斜纹贴花（32x32，可水平平铺）。"""
    s = Spr(32, 32)
    for j in range(32):
        for i in range(32):
            band = ((i + j) // 5) % 2 == 0
            s.px(i, j, PAL["red_dk"] if band else PAL["shadow"])
    # 边缘渐隐，中间更实
    s.radial_alpha(15.5, 15.5, 20.0, 1.5)
    s.alpha_scale(0.8)
    return s


# ------------------------------------------------------------------ 拾取物

def make_coin(frame: int) -> Spr:
    """金币旋转：宽窄变化模拟 3D 翻转。"""
    ws = [5.0, 3.4, 1.2, 3.4]
    w = ws[frame % 4]
    s = Spr(12, 12)
    s.ell(6, 6, w, 5.0, PAL["gold_dk"])
    s.ell(6, 6, max(0.6, w - 1.0), 4.0, PAL["gold"])
    if w > 3:
        s.ell(6, 6, max(0.4, w - 2.2), 2.4, PAL["gold_lt"])
        s.px(5, 4, PAL["white"])
        # 币面刻纹
        s.vline(6, 4, 5, PAL["gold_dk"])
    else:
        s.px(6, 5, PAL["gold_lt"])
    s.outline(PAL["outline"], diag=False)
    return s


def make_energy(frame: int) -> Spr:
    """能量球：蓝色液滴，上下呼吸。"""
    s = Spr(12, 12)
    bob = [0, -1, 0, 1][frame % 4]
    cy = 6 + bob
    s.ell(6, cy, 4.6, 4.6, PAL["blue_dk"])
    s.ell(6, cy, 3.4, 3.4, PAL["blue"])
    s.ell(5, cy - 1, 1.5, 1.5, PAL["blue_lt"])
    s.px(5, cy - 2, PAL["white"])
    # 外圈电弧
    for k in range(3):
        a = frame * 1.2 + k * 2.1
        x = int(round(6 + np.cos(a) * 5))
        y = int(round(cy + np.sin(a) * 5))
        if 0 <= x < 12 and 0 <= y < 12:
            s.px(x, y, PAL["cry_lt"])
    s.outline(PAL["outline"], diag=False)
    return s


def make_heart(big: bool = False) -> Spr:
    n = 18 if big else 14
    s = Spr(n, n)
    c = n / 2.0
    r = n * 0.30
    # 心形：两个圆 + 三角
    s.ell(c - r * 0.72, c - r * 0.35, r, r, PAL["red_dk"])
    s.ell(c + r * 0.72, c - r * 0.35, r, r, PAL["red_dk"])
    s.poly([(c - r * 1.55, c), (c + r * 1.55, c), (c, c + r * 1.75)], PAL["red_dk"])
    s.ell(c - r * 0.72, c - r * 0.35, r * 0.7, r * 0.7, PAL["red"])
    s.ell(c + r * 0.72, c - r * 0.35, r * 0.7, r * 0.7, PAL["red"])
    s.poly([(c - r * 1.2, c + 0.5), (c + r * 1.2, c + 0.5), (c, c + r * 1.4)], PAL["red"])
    s.ell(c - r * 0.75, c - r * 0.55, r * 0.3, r * 0.26, PAL["red_lt"])
    s.px(int(c - r * 0.8), int(c - r * 0.7), PAL["white"])
    s.outline(PAL["outline"], diag=True)
    return s


def make_armor_pickup() -> Spr:
    """护盾片：蓝色盾形。"""
    s = Spr(14, 14)
    s.poly([(7, 1), (12, 3), (12, 7), (7, 13), (2, 7), (2, 3)], PAL["blue_dk"])
    s.poly([(7, 2), (11, 4), (11, 7), (7, 11), (3, 7), (3, 4)], PAL["blue"])
    s.poly([(7, 3), (10, 5), (10, 6), (7, 8), (4, 6), (4, 5)], PAL["blue_lt"])
    s.px(6, 4, PAL["white"])
    s.outline(PAL["outline"])
    return s


def make_key() -> Spr:
    s = Spr(14, 14)
    s.ring(5, 5, 3.0, 3.0, PAL["gold_dk"], thickness=2.0)
    s.ring(5, 5, 2.0, 2.0, PAL["gold"], thickness=1.2)
    s.line(7, 7, 12, 12, PAL["gold_dk"])
    s.line(8, 6, 13, 11, PAL["gold"])
    s.px(11, 12, PAL["gold_lt"])
    s.px(12, 10, PAL["gold_lt"])
    s.outline(PAL["outline"], diag=False)
    return s


def make_weapon_box() -> Spr:
    s = Spr(18, 18)
    s.rect(2, 5, 14, 11, PAL["metal_dk"])
    s.rect(3, 6, 12, 9, PAL["metal"])
    s.rect(1, 3, 16, 3, PAL["metal_lt"])
    dither(s, 3, 7, 12, 8, shade(PAL["metal_dk"], 0.1), 0.28, np.random.default_rng(19))
    # 问号标记（表示随机武器）
    s.px(8, 8, PAL["cry_dk"]); s.px(9, 8, PAL["cry_dk"]); s.px(10, 8, PAL["cry_dk"])
    s.px(7, 9, PAL["cry_dk"]); s.px(10, 9, PAL["cry_dk"])
    s.px(9, 10, PAL["cry"]); s.px(9, 11, PAL["cry"])
    s.px(9, 13, PAL["cry_lt"])
    s.bevel(0.16, 0.22)
    s.outline(PAL["outline"])
    return s


def make_bomb(frame: int) -> Spr:
    """炸弹拾取物：黑铁球体 + 顶部引信，4 帧引信火星闪烁。"""
    s = Spr(14, 14)
    # 球体
    s.ell(7, 9, 5.0, 5.0, PAL["void"])
    s.ell(6.7, 8.6, 4.3, 4.3, shade(PAL["metal_dk"], -0.5))
    s.ell(6.4, 8.3, 3.2, 3.2, PAL["metal_dk"])
    s.ell(5.6, 7.2, 1.4, 1.2, PAL["metal_lt"])
    s.px(5, 6, PAL["white"])
    # 引信座
    s.rect(6, 4, 2, 2, PAL["metal"])
    s.hline(6, 4, 2, PAL["metal_lt"])
    # 引信绳
    s.line(7, 4, 9, 2, shade(PAL["gold_dk"], -0.25))
    s.line(7, 3, 9, 1, PAL["gold_dk"])
    # 火星：4 帧位置与亮度交替
    fx = [9, 10, 9, 10][frame % 4]
    fy = [1, 0, 2, 1][frame % 4]
    core = PAL["white"] if frame % 2 == 0 else PAL["gold_lt"]
    s.px(fx, fy, core)
    if fx + 1 < 14:
        s.px(fx + 1, fy, PAL["gold"])
    if fy + 1 < 14:
        s.px(fx, fy + 1, PAL["gold"])
    s.outline(PAL["outline"], diag=False)
    return s


def _talent_frame(bg, fg, glyph, frame: int) -> Spr:
    """天赋图标底板 + 中央图形，4 帧轻微闪烁。"""
    s = Spr(16, 16)
    s.ell(8, 8, 7.0, 7.0, shade(bg, -0.45))
    s.ell(8, 8, 6.0, 6.0, bg)
    s.ring(8, 8, 6.0, 6.0, shade(bg, 0.3), thickness=1.0)
    glyph(s, fg, frame)
    if frame in (1, 2):
        s.px(4, 4, PAL["white"])
    s.bevel(0.18, 0.16)
    s.outline(PAL["outline"])
    return s


def _g_speed(s: Spr, c, frame: int) -> None:
    off = [0, 1, 0, -1][frame % 4]
    for k in range(3):
        y = 5 + k * 3
        s.hline(4 + off, y, 8 - k, c)
    s.poly([(11 + off, 6), (13 + off, 8), (11 + off, 10)], PAL["white"])


def _g_crit(s: Spr, c, frame: int) -> None:
    s.line(5, 11, 11, 5, c)
    s.line(6, 12, 12, 6, c)
    s.poly([(10, 3), (13, 3), (13, 6), (11, 5)], PAL["white"])
    s.px(4 + frame % 2, 12, PAL["white"])


def _g_damage(s: Spr, c, frame: int) -> None:
    s.poly([(8, 3), (11, 8), (8, 7), (9, 13), (5, 7), (8, 8)], c)
    s.px(8, 4 + frame % 3, PAL["white"])


def _g_shield(s: Spr, c, frame: int) -> None:
    s.poly([(8, 3), (12, 5), (12, 8), (8, 13), (4, 8), (4, 5)], c)
    s.poly([(8, 5), (10, 6), (10, 8), (8, 10), (6, 8), (6, 6)], PAL["white"])
    if frame % 2 == 0:
        s.px(8, 7, c)


def _g_life(s: Spr, c, frame: int) -> None:
    s.rect(7, 4, 2, 8, c)
    s.rect(4, 7, 8, 2, c)
    s.px(7, 7, PAL["white"])
    s.px(8, 8, PAL["white"])
    if frame == 1 or frame == 2:
        s.px(5, 5, PAL["white"]); s.px(10, 10, PAL["white"])


def _g_energy(s: Spr, c, frame: int) -> None:
    s.poly([(9, 3), (5, 9), (8, 9), (7, 13), (11, 7), (8, 7)], c)
    s.px(8, 4 + frame % 4, PAL["white"])


TALENTS = [
    ("speed", PAL["green"], PAL["green_lt"], _g_speed),
    ("crit", PAL["red"], PAL["red_lt"], _g_crit),
    ("damage", PAL["gold"], PAL["gold_lt"], _g_damage),
    ("shield", PAL["blue"], PAL["blue_lt"], _g_shield),
    ("life", PAL["red"], PAL["white"], _g_life),
    ("energy", PAL["purple"], PAL["purple_lt"], _g_energy),
]


# ------------------------------------------------------------------ 入口

def gen_bullets() -> int:
    n = 0
    for v in range(2):
        make_bullet_p(v).save("fx/bullet_p_%d.png" % v); n += 1
        make_bullet_e(v).save("fx/bullet_e_%d.png" % v); n += 1
    make_bullet_shot().save("fx/bullet_shot.png"); n += 1
    make_bullet_laser().save("fx/bullet_laser.png"); n += 1
    make_bullet_boss().save("fx/bullet_boss.png"); n += 1
    make_bullet_orb().save("fx/bullet_orb.png"); n += 1
    return n


def gen_fx() -> int:
    n = 0
    for f in range(3):
        make_muzzle(f).save("fx/muzzle_%d.png" % f); n += 1
    for f in range(8):
        make_explode(f).save("fx/explode_%d.png" % f); n += 1
    for f in range(4):
        make_hit(f).save("fx/hit_%d.png" % f); n += 1
        make_spark(f).save("fx/spark_%d.png" % f); n += 1
        make_dust(f).save("fx/dust_%d.png" % f); n += 1
        make_smoke(f).save("fx/smoke_%d.png" % f); n += 1
        make_slash(f).save("fx/slash_%d.png" % f); n += 1
        make_ring(f).save("fx/ring_%d.png" % f); n += 1
        make_heal(f).save("fx/heal_%d.png" % f); n += 1
        make_shield_pop(f).save("fx/shield_pop_%d.png" % f); n += 1
    for f in range(6):
        make_level_ring(f).save("fx/level_ring_%d.png" % f); n += 1
    glow_disc(32, 32, PAL["gold"], 15.0, 1.25).save("fx/glow_soft.png"); n += 1
    glow_disc(32, 32, PAL["cry"], 15.0, 1.25).save("fx/glow_soft_blue.png"); n += 1
    glow_disc(16, 16, PAL["white"], 7.5, 1.5).save("fx/glow_hard.png"); n += 1
    make_dash_trail().save("fx/dash_trail.png"); n += 1
    make_telegraph().save("fx/telegraph.png"); n += 1
    return n


def gen_pickups() -> int:
    n = 0
    for f in range(4):
        make_coin(f).save("pickups/coin_%d.png" % f); n += 1
        make_energy(f).save("pickups/energy_%d.png" % f); n += 1
    make_heart(False).save("pickups/heart.png"); n += 1
    make_heart(True).save("pickups/heart_big.png"); n += 1
    make_armor_pickup().save("pickups/armor.png"); n += 1
    make_key().save("pickups/key.png"); n += 1
    make_weapon_box().save("pickups/weapon_box.png"); n += 1
    for f in range(4):
        make_bomb(f).save("pickups/bomb_%d.png" % f); n += 1
    for name, bg, fg, glyph in TALENTS:
        for f in range(4):
            _talent_frame(bg, fg, glyph, f).save("pickups/talent_%s_%d.png" % (name, f)); n += 1
    return n


def main() -> int:
    total = gen_bullets() + gen_fx() + gen_pickups()
    print("[gen_fx] 生成特效与拾取物 %d 个" % total)
    return total


if __name__ == "__main__":
    main()

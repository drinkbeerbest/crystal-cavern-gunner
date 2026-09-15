# -*- coding: utf-8 -*-
"""gen_ui.py —— 生成 UI、武器精灵与图标、鼠标指针、工程图标。

全部程序化绘制，原创素材。命名约定：

  ui/panel_9.png                24x24  九宫格面板（边距 7）
  ui/panel_dark_9.png           24x24  深色面板
  ui/btn_9_normal.png           24x16  按钮常态（边距 左右6 上下5）
  ui/btn_9_hover.png            24x16  按钮悬停
  ui/btn_9_pressed.png          24x16  按钮按下
  ui/btn_9_disabled.png         24x16  按钮禁用
  ui/slot_9.png                 20x20  道具格（边距 5）
  ui/bar_bg_9.png               16x10  进度条底（边距 左右4 上下3）
  ui/bar_fill_hp.png            8x8    生命条填充（可横向平铺）
  ui/bar_fill_shield.png        8x8    护盾条填充
  ui/bar_fill_energy.png        8x8    能量条填充
  ui/bar_fill_boss.png          8x8    Boss 血条填充
  ui/bar_fill_dash.png          8x8    冲刺冷却填充
  ui/boss_bar_9.png             32x14  Boss 血条外框（边距 左右8 上下4）
  ui/icon_heart.png 等 14 个    12x12  HUD 图标
  ui/crosshair_0..2.png         16x16  准星（常态/命中/暴击）
  ui/cursor.png                 16x16  鼠标指针（热点 1,1）
  ui/minimap_*.png              12x12  小地图图块
  ui/logo.png                   176x72 标题徽标（原创图形，标题文字由字体渲染）
  ui/vignette.png               320x180 屏幕暗角
  ui/rarity_common.png 等 4 个  16x16  武器稀有度底框
  weapons/<id>.png                     手持武器精灵（指向 +X，握把在左下）
  ui/weapons/<id>.png             20x20  武器图标
  icon.png                      128x128 工程图标
"""
from __future__ import annotations

import numpy as np

from pixel import PAL, Spr, dither, glow_disc, mix, shade


# ------------------------------------------------------------------ 九宫格底板

def _panel(w: int, h: int, face, edge, dark, corner, rivet=None) -> Spr:
    s = Spr(w, h)
    s.rect(1, 1, w - 2, h - 2, face)
    dither(s, 1, 1, w - 2, h - 2, dark, 0.14, np.random.default_rng(2))
    s.frame_rect(1, 1, w - 2, h - 2, edge)
    s.frame_rect(0, 0, w, h, PAL["outline"])
    # 内高光
    s.hline(2, 2, w - 4, mix(face, PAL["white"], 0.14))
    s.vline(2, 2, h - 4, mix(face, PAL["white"], 0.08))
    s.hline(2, h - 3, w - 4, shade(face, -0.25))
    s.vline(w - 3, 2, h - 4, shade(face, -0.2))
    # 四角装饰
    for cx, cy in ((3, 3), (w - 4, 3), (3, h - 4), (w - 4, h - 4)):
        s.px(cx, cy, corner)
    if rivet:
        for cx, cy in ((4, 4), (w - 5, 4), (4, h - 5), (w - 5, h - 5)):
            s.px(cx, cy, rivet)
    return s


def make_panel(dark_variant: bool = False) -> Spr:
    if dark_variant:
        return _panel(24, 24, PAL["void"], PAL["stone_2"], PAL["shadow"], PAL["cry_dk"], PAL["stone_1"])
    return _panel(24, 24, PAL["stone_1"], PAL["stone_3"], PAL["stone_0"], PAL["gold_dk"], PAL["stone_hi"])


def make_button(state: str) -> Spr:
    w, h = 24, 16
    if state == "normal":
        face, edge, txt = PAL["stone_2"], PAL["stone_3"], PAL["cry"]
    elif state == "hover":
        face, edge, txt = PAL["stone_3"], PAL["cry_dk"], PAL["cry_lt"]
    elif state == "pressed":
        face, edge, txt = PAL["stone_0"], PAL["stone_1"], PAL["cry_dk"]
    else:
        face, edge, txt = PAL["stone_0"], PAL["stone_1"], PAL["stone_2"]
    s = Spr(w, h)
    s.rect(1, 1, w - 2, h - 2, face)
    s.frame_rect(1, 1, w - 2, h - 2, edge)
    s.frame_rect(0, 0, w, h, PAL["outline"])
    if state == "pressed":
        s.hline(2, 2, w - 4, shade(face, -0.3))
        s.hline(2, h - 3, w - 4, mix(face, PAL["white"], 0.08))
    else:
        s.hline(2, 2, w - 4, mix(face, PAL["white"], 0.16))
        s.hline(2, h - 3, w - 4, shade(face, -0.3))
    # 中段装饰线（九宫格中间区域会被拉伸，所以只放细横纹）
    for i in range(8, w - 8):
        s.px(i, h // 2, mix(face, txt, 0.10))
    if state == "hover":
        s.px(3, 3, PAL["gold"]); s.px(w - 4, 3, PAL["gold"])
        s.px(3, h - 4, PAL["gold"]); s.px(w - 4, h - 4, PAL["gold"])
    if state == "disabled":
        s.alpha_scale(0.75)
    return s


def make_slot() -> Spr:
    return _panel(20, 20, PAL["void"], PAL["stone_2"], PAL["shadow"], PAL["stone_3"])


def make_bar_bg() -> Spr:
    w, h = 16, 10
    s = Spr(w, h)
    s.rect(0, 0, w, h, PAL["outline"])
    s.rect(1, 1, w - 2, h - 2, PAL["void"])
    s.rect(1, 1, w - 2, 1, PAL["shadow"])
    s.hline(1, h - 2, w - 2, shade(PAL["void"], 0.12))
    return s


def make_bar_fill(kind: str) -> Spr:
    """8x8 可平铺的条填充：上高光、下暗部、中间主体。"""
    cols = {
        "hp": (PAL["red"], PAL["red_lt"], PAL["red_dk"]),
        "shield": (PAL["blue"], PAL["blue_lt"], PAL["blue_dk"]),
        "energy": (PAL["cry"], PAL["cry_lt"], PAL["cry_dk"]),
        "boss": (PAL["purple"], PAL["purple_lt"], PAL["purple_dk"]),
        "dash": (PAL["gold"], PAL["gold_lt"], PAL["gold_dk"]),
    }
    body, hi, lo = cols[kind]
    s = Spr(8, 8)
    s.rect(0, 0, 8, 8, body)
    s.hline(0, 0, 8, hi)
    s.hline(0, 1, 8, mix(body, hi, 0.5))
    s.hline(0, 6, 8, mix(body, lo, 0.5))
    s.hline(0, 7, 8, lo)
    # 斜向扫光纹理（平铺后仍连续）
    for i in range(8):
        s.px(i, 3 - (i % 2), mix(body, PAL["white"], 0.10))
    return s


def make_boss_bar() -> Spr:
    w, h = 32, 14
    s = Spr(w, h)
    s.rect(0, 0, w, h, PAL["outline"])
    s.rect(1, 1, w - 2, h - 2, PAL["void"])
    s.frame_rect(2, 2, w - 4, h - 4, PAL["gold_dk"])
    # 两端兽面装饰
    for ox in (0, w - 6):
        s.rect(ox + 1, 3, 4, h - 6, PAL["gold_dk"])
        s.px(ox + 2, 5, PAL["red"])
        s.px(ox + 3, 8, PAL["gold"])
    s.hline(6, 1, w - 12, PAL["stone_2"])
    s.hline(6, h - 2, w - 12, PAL["stone_0"])
    return s


# ------------------------------------------------------------------ HUD 图标

def _icon_base(n: int = 12) -> Spr:
    return Spr(n, n)


def icon_heart() -> Spr:
    s = _icon_base()
    s.ell(4, 4.5, 2.6, 2.6, PAL["red_dk"])
    s.ell(8, 4.5, 2.6, 2.6, PAL["red_dk"])
    s.poly([(1.6, 5), (10.4, 5), (6, 11)], PAL["red_dk"])
    s.ell(4, 4.5, 1.7, 1.7, PAL["red"])
    s.ell(8, 4.5, 1.7, 1.7, PAL["red"])
    s.poly([(2.6, 5.6), (9.4, 5.6), (6, 9.8)], PAL["red"])
    s.px(3, 3, PAL["red_lt"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_shield() -> Spr:
    s = _icon_base()
    s.poly([(6, 1), (11, 3), (11, 6), (6, 11), (1, 6), (1, 3)], PAL["blue_dk"])
    s.poly([(6, 2), (10, 4), (10, 6), (6, 10), (2, 6), (2, 4)], PAL["blue"])
    s.poly([(6, 3), (8, 4), (8, 6), (6, 7), (4, 6), (4, 4)], PAL["blue_lt"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_energy() -> Spr:
    s = _icon_base()
    s.ell(6, 6, 5, 5, PAL["blue_dk"])
    s.ell(6, 6, 3.6, 3.6, PAL["cry"])
    s.poly([(7, 2), (4, 6), (6, 6), (5, 10), (9, 5), (6, 5)], PAL["cry_glow"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_coin() -> Spr:
    s = _icon_base()
    s.ell(6, 6, 5, 5, PAL["gold_dk"])
    s.ell(6, 6, 3.8, 3.8, PAL["gold"])
    s.ell(6, 6, 2.2, 2.2, PAL["gold_lt"])
    s.vline(6, 4, 5, PAL["gold_dk"])
    s.px(4, 4, PAL["white"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_key() -> Spr:
    s = _icon_base()
    s.ring(4, 4, 2.6, 2.6, PAL["gold_dk"], thickness=1.8)
    s.line(6, 6, 10, 10, PAL["gold"])
    s.px(9, 11, PAL["gold_lt"])
    s.px(11, 9, PAL["gold_lt"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_skull() -> Spr:
    s = _icon_base()
    s.ell(6, 5, 4.4, 4.0, PAL["metal"])
    s.rect(3, 7, 6, 3, PAL["metal_dk"])
    s.ell(4, 5, 1.4, 1.4, PAL["black"])
    s.ell(8, 5, 1.4, 1.4, PAL["black"])
    s.px(6, 7, PAL["black"])
    s.vline(4, 9, 2, PAL["black"]); s.vline(6, 9, 2, PAL["black"]); s.vline(8, 9, 2, PAL["black"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_floor() -> Spr:
    s = _icon_base()
    s.poly([(6, 1), (11, 4), (11, 8), (6, 11), (1, 8), (1, 4)], PAL["stone_2"])
    s.poly([(6, 2.5), (9.5, 4.5), (9.5, 7.5), (6, 9.5), (2.5, 7.5), (2.5, 4.5)], PAL["stone_3"])
    s.line(2.5, 4.5, 9.5, 7.5, PAL["stone_1"])
    s.line(9.5, 4.5, 2.5, 7.5, PAL["stone_1"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_dash() -> Spr:
    s = _icon_base()
    for k in range(3):
        y = 3 + k * 3
        s.hline(2, y, 6 - k, PAL["cry"])
        s.px(8 - k, y, PAL["cry_lt"])
    s.poly([(8, 3), (11, 6), (8, 9)], PAL["white"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_skill() -> Spr:
    s = _icon_base()
    s.poly([(7, 1), (3, 6), (6, 6), (5, 11), (9, 5), (6, 5)], PAL["gold"])
    s.poly([(7, 2), (4.5, 5.5), (6, 5.5), (5.5, 9), (8, 5), (6.5, 5)], PAL["gold_lt"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_pause() -> Spr:
    s = _icon_base()
    s.rect(3, 2, 2, 8, PAL["white"])
    s.rect(7, 2, 2, 8, PAL["white"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_sound(on: bool) -> Spr:
    s = _icon_base()
    s.poly([(2, 4), (4, 4), (7, 2), (7, 10), (4, 8), (2, 8)], PAL["metal"])
    s.vline(2, 4, 5, PAL["metal_dk"])
    if on:
        s.ring(8, 6, 2.4, 2.4, PAL["cry_lt"], thickness=1.0)
        s.rect(8, 4, 1, 5, PAL["void"])
        s.px(10, 5, PAL["cry"]); s.px(10, 7, PAL["cry"])
    else:
        s.line(8, 4, 11, 8, PAL["red"])
        s.line(11, 4, 8, 8, PAL["red"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_music(on: bool) -> Spr:
    s = _icon_base()
    s.vline(4, 2, 7, PAL["metal"])
    s.vline(9, 3, 6, PAL["metal"])
    s.hline(4, 2, 6, PAL["metal_lt"])
    s.ell(3, 9, 2.0, 1.6, PAL["cry"])
    s.ell(8, 9, 2.0, 1.6, PAL["cry"])
    if not on:
        s.line(1, 1, 11, 11, PAL["red"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_close() -> Spr:
    s = _icon_base()
    s.line(2, 2, 10, 10, PAL["red"])
    s.line(10, 2, 2, 10, PAL["red"])
    s.line(3, 2, 10, 9, PAL["red_lt"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_back() -> Spr:
    s = _icon_base()
    s.poly([(6, 1), (1, 6), (6, 11), (6, 8), (11, 8), (11, 4), (6, 4)], PAL["metal"])
    s.poly([(5, 3), (2.5, 6), (5, 9), (5, 7), (10, 7), (10, 5), (5, 5)], PAL["metal_lt"])
    s.outline(PAL["outline"], diag=False)
    return s


def icon_star() -> Spr:
    s = _icon_base()
    pts = []
    for k in range(10):
        a = -np.pi / 2 + k * np.pi / 5
        r = 5.2 if k % 2 == 0 else 2.2
        pts.append((6 + np.cos(a) * r, 6 + np.sin(a) * r))
    s.poly(pts, PAL["gold"])
    s.px(5, 4, PAL["gold_lt"])
    s.outline(PAL["outline"], diag=False)
    return s


ICONS = {
    "heart": icon_heart, "shield": icon_shield, "energy": icon_energy,
    "coin": icon_coin, "key": icon_key, "skull": icon_skull, "floor": icon_floor,
    "dash": icon_dash, "skill": icon_skill, "pause": icon_pause,
    "sound_on": lambda: icon_sound(True), "sound_off": lambda: icon_sound(False),
    "music_on": lambda: icon_music(True), "music_off": lambda: icon_music(False),
    "close": icon_close, "back": icon_back, "star": icon_star,
}


# ------------------------------------------------------------------ 准星 / 指针

def make_crosshair(v: int) -> Spr:
    s = Spr(16, 16)
    c = 8.0
    if v == 0:
        col, hit = PAL["cry_lt"], PAL["cry"]
    elif v == 1:
        col, hit = PAL["gold_lt"], PAL["gold"]
    else:
        col, hit = PAL["red_lt"], PAL["red"]
    gap = 2 if v == 0 else 1
    ln = 4 if v == 0 else 5
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        for k in range(gap, gap + ln):
            s.px(int(c + dx * k), int(c + dy * k), col)
    s.px(int(c), int(c), hit)
    if v == 2:
        for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
            s.px(int(c + dx * 2), int(c + dy * 2), hit)
    return s


def make_cursor() -> Spr:
    """箭头指针，热点在 (1,1)。"""
    s = Spr(16, 16)
    s.poly([(1, 1), (1, 11), (4, 8), (6, 12), (8, 11), (6, 7), (10, 7)], PAL["white"])
    s.poly([(2, 3), (2, 9), (4, 7), (6, 11), (7, 10), (5, 6), (8, 6)], PAL["cry_lt"])
    s.outline(PAL["outline"], diag=True)
    return s


# ------------------------------------------------------------------ 小地图

def make_minimap_room(kind: str) -> Spr:
    s = Spr(12, 12)
    if kind == "player":
        s = Spr(6, 6)
        s.ell(3, 3, 2.6, 2.6, PAL["white"])
        s.ell(3, 3, 1.4, 1.4, PAL["cry"])
        return s
    bg = {
        "normal": PAL["stone_1"], "boss": PAL["red_dk"], "treasure": PAL["gold_dk"],
        "shop": PAL["green_dk"], "start": PAL["blue_dk"], "current": PAL["cry_dk"],
        "unknown": PAL["shadow"],
    }.get(kind, PAL["stone_1"])
    s.rect(1, 1, 10, 10, bg)
    s.frame_rect(1, 1, 10, 10, shade(bg, 0.3))
    s.frame_rect(0, 0, 12, 12, PAL["outline"])
    if kind == "boss":
        s.px(6, 5, PAL["red"]); s.px(5, 6, PAL["red_lt"]); s.px(7, 6, PAL["red_lt"])
    elif kind == "treasure":
        s.rect(4, 5, 4, 3, PAL["gold"])
    elif kind == "shop":
        s.px(6, 6, PAL["gold"])
    elif kind == "current":
        s.ell(6, 6, 2.4, 2.4, PAL["cry_lt"])
    return s


# ------------------------------------------------------------------ 稀有度框

def make_rarity(tier: int) -> Spr:
    cols = [PAL["stone_3"], PAL["green"], PAL["blue_lt"], PAL["gold"]]
    c = cols[min(tier, 3)]
    s = Spr(16, 16)
    s.frame_rect(0, 0, 16, 16, PAL["outline"])
    s.frame_rect(1, 1, 14, 14, c)
    s.frame_rect(2, 2, 12, 12, shade(c, -0.4))
    for cx, cy in ((1, 1), (14, 1), (1, 14), (14, 14)):
        s.px(cx, cy, shade(c, 0.45))
    return s


# ------------------------------------------------------------------ 武器

def _gun_body(s: Spr, x0: int, y0: int, ln: int, hh: int, metal, dark, lite) -> None:
    """画一段枪身（矩形 + 上下描边）。"""
    s.rect(x0, y0, ln, hh, metal)
    s.hline(x0, y0, ln, lite)
    s.hline(x0, y0 + hh - 1, ln, dark)


def make_pistol() -> Spr:
    s = Spr(22, 14)
    _gun_body(s, 4, 4, 14, 4, PAL["metal"], PAL["metal_dk"], PAL["metal_lt"])
    s.rect(16, 4, 4, 3, PAL["metal_dk"])          # 枪口
    s.rect(5, 8, 4, 5, PAL["gold_dk"])             # 握把
    s.rect(5, 8, 4, 1, PAL["gold"])
    s.px(9, 5, PAL["cry_lt"])                      # 能量槽
    s.px(10, 5, PAL["cry"])
    s.bevel(0.14, 0.2)
    s.outline(PAL["outline"])
    return s


def make_smg() -> Spr:
    s = Spr(26, 14)
    _gun_body(s, 3, 4, 18, 4, PAL["metal_dk"], PAL["shadow"], PAL["metal"])
    s.rect(19, 5, 5, 2, PAL["metal"])
    s.rect(6, 8, 3, 5, PAL["gold_dk"])
    s.rect(11, 8, 3, 4, PAL["stone_2"])            # 弹匣
    s.rect(11, 8, 3, 1, PAL["stone_3"])
    s.px(8, 5, PAL["cry"]); s.px(9, 5, PAL["cry_lt"])
    s.rect(3, 2, 5, 2, PAL["stone_2"])             # 提把
    s.bevel(0.14, 0.2)
    s.outline(PAL["outline"])
    return s


def make_shotgun() -> Spr:
    s = Spr(30, 14)
    _gun_body(s, 2, 5, 22, 4, PAL["gold_dk"], shade(PAL["gold_dk"], -0.4), PAL["gold"])
    s.rect(20, 4, 9, 2, PAL["metal_dk"])           # 上管
    s.rect(20, 8, 9, 2, PAL["metal_dk"])           # 下管
    s.rect(27, 4, 2, 6, PAL["metal"])
    s.rect(4, 9, 5, 4, shade(PAL["gold_dk"], -0.2))
    s.rect(12, 8, 4, 3, PAL["stone_2"])            # 泵动握把
    s.hline(12, 8, 4, PAL["stone_3"])
    s.px(8, 6, PAL["red_lt"])
    s.bevel(0.14, 0.2)
    s.outline(PAL["outline"])
    return s


def make_rifle() -> Spr:
    s = Spr(32, 14)
    _gun_body(s, 2, 5, 26, 3, PAL["stone_2"], PAL["shadow"], PAL["stone_3"])
    s.rect(26, 5, 6, 2, PAL["metal_dk"])           # 长枪管
    s.rect(2, 4, 6, 4, PAL["gold_dk"])             # 枪托
    s.rect(4, 8, 4, 5, PAL["stone_1"])             # 握把
    s.rect(13, 2, 8, 3, PAL["metal_dk"])           # 瞄具
    s.rect(14, 3, 6, 1, PAL["cry"])
    s.px(20, 3, PAL["cry_lt"])
    s.rect(12, 8, 3, 4, PAL["metal_dk"])           # 弹匣
    s.bevel(0.14, 0.2)
    s.outline(PAL["outline"])
    return s


def make_laser() -> Spr:
    s = Spr(30, 16)
    _gun_body(s, 3, 6, 18, 5, PAL["blue_dk"], PAL["shadow"], PAL["blue"])
    s.rect(19, 7, 9, 3, PAL["metal_dk"])
    s.rect(26, 6, 3, 5, PAL["cry_dk"])             # 聚焦镜
    s.rect(27, 7, 1, 3, PAL["cry_glow"])
    # 散热鳍
    for i in range(4):
        s.rect(6 + i * 3, 4, 2, 2, PAL["metal_dk"])
        s.hline(6 + i * 3, 4, 2, PAL["metal"])
    s.rect(5, 11, 4, 4, PAL["stone_1"])            # 握把
    s.ell(12, 8, 3, 2, PAL["cry"])
    s.ell(12, 8, 1.6, 1.0, PAL["cry_glow"])
    s.bevel(0.14, 0.2)
    s.outline(PAL["outline"])
    return s


def make_rocket() -> Spr:
    s = Spr(32, 16)
    _gun_body(s, 2, 5, 24, 7, PAL["green_dk"], PAL["shadow"], PAL["green"])
    s.rect(24, 4, 7, 9, PAL["metal_dk"])           # 喇叭口
    s.rect(25, 5, 5, 7, PAL["shadow"])
    s.rect(29, 4, 2, 9, PAL["metal"])
    s.rect(4, 3, 8, 2, PAL["stone_2"])             # 提把
    s.rect(6, 12, 4, 4, PAL["stone_1"])
    s.rect(14, 6, 6, 5, PAL["red_dk"])             # 弹头舱
    s.poly([(15, 7), (19, 7), (17, 10)], PAL["red"])
    s.px(17, 8, PAL["red_lt"])
    s.bevel(0.12, 0.2)
    s.outline(PAL["outline"])
    return s


def make_wand() -> Spr:
    s = Spr(28, 16)
    # 木杆
    s.line(4, 14, 20, 4, PAL["gold_dk"])
    s.line(4, 13, 20, 3, PAL["gold"])
    s.px(4, 14, shade(PAL["gold_dk"], -0.3))
    # 顶端晶石
    s.poly([(22, 1), (26, 5), (22, 11), (18, 5)], PAL["cry_dk"])
    s.poly([(22, 2), (25, 5), (22, 9), (19, 5)], PAL["cry"])
    s.poly([(22, 3), (23, 5), (22, 7), (21, 5)], PAL["cry_glow"])
    s.px(22, 4, PAL["white"])
    g = glow_disc(12, 12, PAL["cry_lt"], 5.5, 1.3)
    s.paste(g, 16, 0, alpha=0.45)
    s.bevel(0.14, 0.18)
    s.outline(PAL["outline"])
    return s


def make_blade() -> Spr:
    s = Spr(30, 14)
    # 刀柄
    s.rect(2, 6, 6, 3, PAL["gold_dk"])
    s.rect(2, 6, 6, 1, PAL["gold"])
    s.rect(7, 4, 2, 7, PAL["metal_dk"])            # 护手
    # 能量刃
    s.poly([(9, 6), (28, 5), (29, 7), (28, 9), (9, 9)], PAL["cry_dk"])
    s.poly([(9, 7), (27, 6), (28, 7), (27, 8), (9, 8)], PAL["cry"])
    s.hline(10, 7, 17, PAL["cry_glow"])
    s.px(28, 7, PAL["white"])
    s.bevel(0.14, 0.16)
    s.outline(PAL["outline"])
    return s


WEAPONS = {
    "pistol": make_pistol,
    "smg": make_smg,
    "shotgun": make_shotgun,
    "rifle": make_rifle,
    "laser": make_laser,
    "rocket": make_rocket,
    "wand": make_wand,
    "blade": make_blade,
}


# ------------------------------------------------------------------ 徽标 / 暗角 / 图标

def make_logo() -> Spr:
    """标题徽标：双枪交叉 + 中央晶石，纯图形（标题文字用字体渲染）。"""
    w, h = 176, 72
    s = Spr(w, h)
    cx, cy = w // 2, 34
    # 背景光晕
    g = glow_disc(w, h, PAL["cry_dk"], 60, 0.9)
    s.paste(g, 0, 0, alpha=0.35)
    # 交叉的两把枪（左右镜像）
    left = make_rifle()
    right = left.mirror()
    s.paste(left, cx - 62, cy - 8, alpha=1.0)
    s.paste(right, cx + 30, cy - 8, alpha=1.0)
    # 中央大晶石
    s.poly([(cx, 4), (cx + 22, 30), (cx + 13, 62), (cx - 13, 62), (cx - 22, 30)], PAL["cry_dk"])
    s.poly([(cx, 8), (cx + 17, 30), (cx + 9, 58), (cx - 9, 58), (cx - 17, 30)], PAL["cry"])
    s.poly([(cx, 12), (cx + 9, 30), (cx + 4, 54), (cx - 4, 54), (cx - 9, 30)], PAL["cry_lt"])
    s.poly([(cx, 18), (cx + 4, 30), (cx, 46), (cx - 4, 30)], PAL["cry_glow"])
    # 晶石裂纹
    s.line(cx - 12, 34, cx - 4, 44, PAL["cry_dk"])
    s.line(cx + 12, 34, cx + 5, 46, PAL["cry_dk"])
    # 两侧装饰翼
    for side in (-1, 1):
        for k in range(5):
            x = cx + side * (26 + k * 7)
            y = 30 + k * 3
            s.rect(x - 3, y, 6, 2, PAL["gold_dk"])
            s.rect(x - 2, y, 4, 1, PAL["gold"])
    s.outline(PAL["outline"], diag=True)
    return s


def make_vignette(w: int = 320, h: int = 180) -> Spr:
    """屏幕暗角：中心全透明，四角变暗。"""
    s = Spr(w, h)
    s.rect(0, 0, w, h, PAL["void"])
    yy, xx = np.mgrid[0:h, 0:w]
    dx = (xx - (w - 1) / 2.0) / (w / 2.0)
    dy = (yy - (h - 1) / 2.0) / (h / 2.0)
    d = np.sqrt(dx * dx * 0.85 + dy * dy * 1.15)
    a = np.clip((d - 0.55) / 0.65, 0.0, 1.0) ** 1.7
    s.a[:, :, 3] = (a * 190).astype(np.uint8)
    return s


def make_project_icon() -> Spr:
    """128x128 工程图标：晶石 + 星芒。"""
    n = 128
    s = Spr(n, n)
    s.rect(0, 0, n, n, PAL["void"])
    # 背景放射
    g = glow_disc(n, n, PAL["cry_dk"], 62, 0.85)
    s.paste(g, 0, 0, alpha=0.55)
    cx, cy = 64, 66
    s.poly([(cx, 14), (cx + 34, 52), (cx + 20, 104), (cx - 20, 104), (cx - 34, 52)], PAL["cry_dk"])
    s.poly([(cx, 20), (cx + 27, 52), (cx + 15, 98), (cx - 15, 98), (cx - 27, 52)], PAL["cry"])
    s.poly([(cx, 28), (cx + 14, 52), (cx + 7, 92), (cx - 7, 92), (cx - 14, 52)], PAL["cry_lt"])
    s.poly([(cx, 38), (cx + 6, 54), (cx, 80), (cx - 6, 54)], PAL["cry_glow"])
    # 星芒
    for k in range(4):
        a = k * np.pi / 2 + np.pi / 4
        for t in range(6, 40, 2):
            x = int(cx + np.cos(a) * t)
            y = int(cy - 8 + np.sin(a) * t * 0.7)
            if 0 <= x < n and 0 <= y < n:
                s.px(x, y, (PAL["gold"][0], PAL["gold"][1], PAL["gold"][2], max(0, 200 - t * 5)))
    # 外框
    s.frame_rect(2, 2, n - 4, n - 4, PAL["stone_2"])
    s.frame_rect(0, 0, n, n, PAL["outline"])
    return s


# ------------------------------------------------------------------ 入口

def gen_panels() -> int:
    n = 0
    make_panel(False).save("ui/panel_9.png"); n += 1
    make_panel(True).save("ui/panel_dark_9.png"); n += 1
    for st in ("normal", "hover", "pressed", "disabled"):
        make_button(st).save("ui/btn_9_%s.png" % st); n += 1
    make_slot().save("ui/slot_9.png"); n += 1
    make_bar_bg().save("ui/bar_bg_9.png"); n += 1
    for kind in ("hp", "shield", "energy", "boss", "dash"):
        make_bar_fill(kind).save("ui/bar_fill_%s.png" % kind); n += 1
    make_boss_bar().save("ui/boss_bar_9.png"); n += 1
    for t in range(4):
        make_rarity(t).save("ui/rarity_%d.png" % t); n += 1
    return n


def gen_icons() -> int:
    n = 0
    for name, fn in ICONS.items():
        fn().save("ui/icon_%s.png" % name); n += 1
    for v in range(3):
        make_crosshair(v).save("ui/crosshair_%d.png" % v); n += 1
    make_cursor().save("ui/cursor.png"); n += 1
    for kind in ("normal", "boss", "treasure", "shop", "start", "current", "unknown"):
        make_minimap_room(kind).save("ui/minimap_%s.png" % kind); n += 1
    make_minimap_room("player").save("ui/minimap_player.png"); n += 1
    return n


def gen_weapons() -> int:
    n = 0
    for wid, fn in WEAPONS.items():
        spr = fn()
        spr.save("weapons/%s.png" % wid)
        n += 1
        icon = spr.centered(20, 20)
        icon.save("ui/weapons/%s.png" % wid)
        n += 1
    return n


def gen_misc() -> int:
    n = 0
    make_logo().save("ui/logo.png"); n += 1
    make_vignette().save("ui/vignette.png"); n += 1
    make_project_icon().save("icon.png"); n += 1
    return n


def main() -> int:
    total = gen_panels() + gen_icons() + gen_weapons() + gen_misc()
    print("[gen_ui] 生成 UI / 武器素材 %d 个" % total)
    return total


if __name__ == "__main__":
    main()

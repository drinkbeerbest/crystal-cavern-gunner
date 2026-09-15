# -*- coding: utf-8 -*-
"""gen_characters.py —— 生成玩家 / 敌人 / Boss 的原创像素精灵。

风格设定（全部原创）：
  玩家  —— "晶窟漫游者"：蓝灰护甲 + 青色晶体面罩 + 红色头冠的 Q 版角色，4 方向 x 4 帧
  敌人  —— 晶壳兽(近战冲锋) / 咒眼(远程射击) / 孢子雷(自爆)，各 3-4 帧
  Boss  —— 晶核守卫(巨石晶体傀儡) / 深渊织者(触须浮空体)，各 4 帧
  精英  —— 同造型换配色（recolor），无需重新设计

命名约定（Godot 侧按此加载）：
  assets/sprites/player/<dir>_<frame>.png      dir in down/up/left/right, frame 0..3
  assets/sprites/enemies/<key>_<frame>.png     key in husk/hexeye/bloom (+ _elite 变体)
  assets/sprites/bosses/<key>_<frame>.png      key in warden/weaver
"""
from __future__ import annotations

import numpy as np

from pixel import PAL, Spr, dither, mix, shade


# ------------------------------------------------------------------ 通用工具

def rrect(s: Spr, x: int, y: int, w: int, h: int, c, cut: int = 1) -> None:
    """带切角的矩形（像素画里比纯矩形更耐看）。"""
    s.rect(x, y, w, h, c)
    for k in range(cut):
        clear_px(s, x + k, y + cut - 1 - k)
        clear_px(s, x + w - 1 - k, y + cut - 1 - k)
        clear_px(s, x + k, y + h - cut + k)
        clear_px(s, x + w - 1 - k, y + h - cut + k)


def clear_px(s: Spr, x: int, y: int) -> None:
    if 0 <= x < s.w and 0 <= y < s.h:
        s.a[y, x] = (0, 0, 0, 0)


# ------------------------------------------------------------------ 玩家
# 画布 22 x 26，锚点居中偏下（脚底）

PLAYER_W, PLAYER_H = 22, 26
P_HEAD_X, P_HEAD_Y, P_HEAD_W, P_HEAD_H = 4, 2, 14, 12
P_BODY_X, P_BODY_Y, P_BODY_W, P_BODY_H = 6, 14, 10, 7
LEG_ROWS = (21, 22, 23, 24)


def make_player(direction: str, frame: int) -> Spr:
    """direction: down/up/left/right ; frame: 0 待机, 1..3 行走循环"""
    s = Spr(PLAYER_W, PLAYER_H)
    bob = -1 if frame in (1, 3) else 0
    step = frame  # 0/2 双腿并立, 1 左腿前, 3 右腿前

    hy = P_HEAD_Y + bob
    by = P_BODY_Y + bob

    # ---- 影子（脚底椭圆，半透明）
    sh = Spr(PLAYER_W, PLAYER_H)
    sh.ell(11, 25, 6, 1.6, (6, 6, 12, 120))
    s.paste(sh, 0, 0)

    # ---- 腿
    leg_c = PAL["cloth_dk"]
    boot_c = PAL["metal_dk"]
    if step == 1:
        s.rect(7, 21, 3, 3, leg_c)
        s.rect(12, 21, 3, 4, leg_c)
        s.rect(7, 23, 3, 1, boot_c)
        s.rect(12, 24, 3, 1, boot_c)
    elif step == 3:
        s.rect(7, 21, 3, 4, leg_c)
        s.rect(12, 21, 3, 3, leg_c)
        s.rect(7, 24, 3, 1, boot_c)
        s.rect(12, 23, 3, 1, boot_c)
    else:
        s.rect(7, 21, 3, 4, leg_c)
        s.rect(12, 21, 3, 4, leg_c)
        s.rect(7, 24, 3, 1, boot_c)
        s.rect(12, 24, 3, 1, boot_c)

    # ---- 躯干
    s.rect(P_BODY_X, by, P_BODY_W, P_BODY_H, PAL["armor"])
    s.rect(P_BODY_X, by, P_BODY_W, 2, PAL["armor_lt"])
    s.rect(P_BODY_X, by + P_BODY_H - 1, P_BODY_W, 1, PAL["armor_dk"])
    s.rect(P_BODY_X, by + 5, P_BODY_W, 1, PAL["gold_dk"])   # 腰带
    s.px(10, by + 5, PAL["gold"])
    s.px(11, by + 5, PAL["gold"])
    # 胸口晶体
    s.px(10, by + 2, PAL["cry"])
    s.px(11, by + 2, PAL["cry_lt"])
    s.px(10, by + 3, PAL["cry_dk"])

    # ---- 手臂 / 肩甲
    arm_swing = 0 if step in (0, 2) else (1 if step == 1 else -1)
    if direction == "up":
        s.rect(3, by + 1, 3, 5, PAL["armor_dk"])
        s.rect(16, by + 1, 3, 5, PAL["armor_dk"])
        s.rect(3, by, 3, 2, PAL["armor_lt"])
        s.rect(16, by, 3, 2, PAL["armor_lt"])
        # 背包
        s.rect(8, by + 1, 6, 5, PAL["metal_dk"])
        s.rect(8, by + 1, 6, 1, PAL["metal"])
        s.px(10, by + 3, PAL["cry"])
        s.px(11, by + 3, PAL["cry"])
    else:
        s.rect(3, by + 1 + arm_swing, 3, 5, PAL["armor_dk"])
        s.rect(16, by + 1 - arm_swing, 3, 5, PAL["armor_dk"])
        s.rect(3, by, 3, 2, PAL["armor_lt"])
        s.rect(16, by, 3, 2, PAL["armor_lt"])
        s.rect(4, by + 5 + arm_swing, 2, 2, PAL["skin"])
        s.rect(16, by + 5 - arm_swing, 2, 2, PAL["skin"])

    # ---- 头 / 头盔
    s.rect(P_HEAD_X, hy, P_HEAD_W, P_HEAD_H, PAL["armor"])
    rrect(s, P_HEAD_X, hy, P_HEAD_W, P_HEAD_H, PAL["armor"], cut=1)
    s.rect(P_HEAD_X, hy, P_HEAD_W, 4, PAL["armor_lt"])          # 头盔上沿高光
    s.rect(P_HEAD_X, hy + P_HEAD_H - 2, P_HEAD_W, 2, PAL["armor_dk"])
    # 头冠
    s.rect(10, hy - 2, 2, 3, PAL["red"])
    s.px(9, hy - 1, PAL["red_dk"])
    s.px(12, hy - 1, PAL["red_dk"])
    s.px(10, hy - 3, PAL["red_lt"])

    # ---- 面罩 / 眼睛（按方向）
    if direction == "down":
        s.rect(6, hy + 5, 10, 4, PAL["visor"])
        s.rect(6, hy + 5, 10, 1, PAL["cry_dk"])
        s.px(8, hy + 6, PAL["cry_glow"])
        s.px(9, hy + 6, PAL["cry_lt"])
        s.px(13, hy + 6, PAL["cry_glow"])
        s.px(12, hy + 6, PAL["cry_lt"])
        s.rect(6, hy + 8, 10, 1, PAL["cry_dk"])
    elif direction == "up":
        s.rect(6, hy + 4, 10, 5, PAL["armor_dk"])
        s.px(10, hy + 6, PAL["cry_dk"])
        s.px(11, hy + 6, PAL["cry_dk"])
    elif direction == "left":
        s.rect(5, hy + 5, 6, 4, PAL["visor"])
        s.rect(5, hy + 5, 6, 1, PAL["cry_dk"])
        s.px(6, hy + 6, PAL["cry_glow"])
        s.px(7, hy + 6, PAL["cry_lt"])
        s.rect(12, hy + 5, 4, 4, PAL["armor_dk"])
        s.px(4, hy + 6, PAL["armor_lt"])
    else:  # right
        s.rect(11, hy + 5, 6, 4, PAL["visor"])
        s.rect(11, hy + 5, 6, 1, PAL["cry_dk"])
        s.px(15, hy + 6, PAL["cry_glow"])
        s.px(14, hy + 6, PAL["cry_lt"])
        s.rect(6, hy + 5, 4, 4, PAL["armor_dk"])
        s.px(17, hy + 6, PAL["armor_lt"])

    # 头盔侧面高光
    s.px(P_HEAD_X + 1, hy + 1, PAL["metal_lt"])
    s.px(P_HEAD_X + 2, hy + 1, PAL["armor_lt"])

    s.bevel(0.18, 0.24)
    s.outline(PAL["outline"], diag=True)
    return s


def gen_player() -> int:
    n = 0
    for d in ("down", "up", "left", "right"):
        for f in range(4):
            make_player(d, f).save("sprites/player/%s_%d.png" % (d, f))
            n += 1
    return n


# ------------------------------------------------------------------ 敌人：晶壳兽（近战冲锋）
# 俯视角，"朝上"为前进方向；Godot 侧按移动角度旋转

HUSK_W, HUSK_H = 28, 26


def make_husk(frame: int, elite: bool = False) -> Spr:
    s = Spr(HUSK_W, HUSK_H)
    body = PAL["husk"] if not elite else PAL["red"]
    body_dk = PAL["husk_dk"] if not elite else PAL["red_dk"]
    body_lt = PAL["husk_lt"] if not elite else PAL["red_lt"]
    spike = PAL["cry"] if not elite else PAL["gold"]
    spike_lt = PAL["cry_lt"] if not elite else PAL["gold_lt"]

    rng = np.random.default_rng(11 + frame)

    # 影子
    sh = Spr(HUSK_W, HUSK_H)
    sh.ell(14, 24, 9, 2, (6, 6, 12, 110))
    s.paste(sh, 0, 0)

    # 腿（3 对，随帧摆动）
    leg_off = [0, 1, 0, -1][frame % 4]
    for i, ly in enumerate((10, 14, 18)):
        off = leg_off if i % 2 == 0 else -leg_off
        s.rect(1, ly + off, 4, 2, body_dk)
        s.rect(23, ly - off, 4, 2, body_dk)
        s.px(0, ly + off + 1, PAL["outline"])
        s.px(27, ly - off + 1, PAL["outline"])

    # 身体
    s.ell(14, 14, 10.5, 8.5, body)
    s.ell(14, 12, 8.5, 6.0, body_lt)
    s.ell(14, 16, 8.0, 4.5, body_dk)

    # 甲壳分节
    for gx in (9, 14, 19):
        s.line(gx, 8, gx, 19, body_dk)
    s.line(6, 13, 22, 13, shade(body_dk, -0.2))

    # 背部晶刺（朝下 = 后方）
    for cx, hgt in ((9, 5), (14, 7), (19, 5)):
        s.tri(cx - 2, 22, cx + 2, 22, cx, 22 - hgt, spike)
        s.px(cx, 22 - hgt, spike_lt)
    dither(s, 6, 18, 17, 4, shade(spike, -0.25), 0.18, rng)

    # 头部 + 钳（朝上 = 前方）
    s.ell(14, 6, 5.5, 3.5, body)
    s.ell(14, 5, 4.0, 2.2, body_lt)
    # 双钳
    s.poly([(7, 7), (4, 2), (6, 1), (9, 6)], body_dk)
    s.poly([(21, 7), (24, 2), (22, 1), (19, 6)], body_dk)
    s.px(4, 2, spike_lt)
    s.px(24, 2, spike_lt)
    # 眼
    s.px(11, 5, PAL["gold"])
    s.px(12, 5, PAL["gold_lt"])
    s.px(16, 5, PAL["gold"])
    s.px(17, 5, PAL["gold_lt"])

    # 甲壳噪点
    dither(s, 6, 9, 17, 8, shade(body, -0.18), 0.14, rng)

    s.bevel(0.2, 0.26)
    s.outline(PAL["outline"], diag=True)
    return s


# ------------------------------------------------------------------ 敌人：咒眼（远程射击）

HEXEYE_W, HEXEYE_H = 24, 26


def make_hexeye(frame: int, elite: bool = False) -> Spr:
    s = Spr(HEXEYE_W, HEXEYE_H)
    ring = PAL["eye_dk"] if not elite else PAL["purple_dk"]
    shell = PAL["eye_body"] if not elite else PAL["purple"]
    shell_lt = PAL["eye_lt"] if not elite else PAL["purple_lt"]
    iris = PAL["red"] if not elite else PAL["cry"]
    iris_lt = PAL["red_lt"] if not elite else PAL["cry_lt"]

    bob = [0, -1, -2, -1][frame % 4]
    cy = 11 + bob

    # 地面影子（浮空感）
    sh = Spr(HEXEYE_W, HEXEYE_H)
    sh.ell(12, 24, 6 - abs(bob) * 0.5, 1.8, (6, 6, 12, 100))
    s.paste(sh, 0, 0)

    # 外环装甲
    s.ring(12, cy, 10, 10, ring, thickness=3.0)
    s.ring(12, cy, 10, 10, shade(ring, 0.2), thickness=1.2)
    # 环上符文
    for k in range(4):
        ang = (frame * 0.4 + k * np.pi / 2)
        rx = int(round(12 + np.cos(ang) * 9))
        ry = int(round(cy + np.sin(ang) * 9))
        s.px(rx, ry, PAL["gold"])

    # 眼球
    s.ell(12, cy, 7.5, 7.5, PAL["white"])
    s.ell(12, cy - 1, 6.5, 6.0, shade(PAL["white"], -0.06))
    # 虹膜 + 瞳孔（随帧轻微移动，制造"盯着你"的感觉）
    ix = 12 + [0, 1, 0, -1][frame % 4]
    iy = cy + [0, 0, 1, 0][frame % 4]
    s.ell(ix, iy, 3.6, 3.6, iris)
    s.ell(ix, iy, 2.0, 2.0, iris_lt)
    s.ell(ix, iy, 1.0, 1.2, PAL["black"])
    s.px(ix - 1, iy - 2, PAL["white"])

    # 下方触须
    for k, tx in enumerate((8, 12, 16)):
        tlen = 3 + ((frame + k) % 2)
        s.line(tx, cy + 7, tx + (1 if k == 2 else (-1 if k == 0 else 0)), cy + 7 + tlen, shell)
    s.ell(12, cy + 8, 4.5, 2.0, shell)
    s.ell(12, cy + 7, 3.0, 1.4, shell_lt)

    s.bevel(0.2, 0.24)
    s.outline(PAL["outline"], diag=True)
    return s


# ------------------------------------------------------------------ 敌人：孢子雷（自爆）

BLOOM_W, BLOOM_H = 22, 22


def make_bloom(frame: int, elite: bool = False, charge: int = 0) -> Spr:
    """charge: 0 常态, 1..3 引信递进（越接近爆炸越亮）"""
    s = Spr(BLOOM_W, BLOOM_H)
    body = PAL["spore"] if not elite else PAL["gold"]
    body_dk = PAL["spore_dk"] if not elite else PAL["gold_dk"]
    body_lt = PAL["spore_lt"] if not elite else PAL["gold_lt"]
    vein = PAL["red"] if charge == 0 else mix(PAL["red"], PAL["gold_lt"], min(1.0, charge / 3.0))

    rng = np.random.default_rng(23 + frame)
    squash = 1.0 + [0.0, -0.06, 0.0, 0.06][frame % 4]
    cy = 12 + (1 if frame % 4 == 3 else 0)

    # 影子
    sh = Spr(BLOOM_W, BLOOM_H)
    sh.ell(11, 20, 6, 1.6, (6, 6, 12, 110))
    s.paste(sh, 0, 0)

    # 小脚
    fo = 1 if frame in (1, 3) else 0
    s.rect(6, 18 + fo, 3, 2, body_dk)
    s.rect(13, 18 - fo, 3, 2, body_dk)

    # 球体
    s.ell(11, cy, 8.0, 7.2 * squash, body)
    s.ell(11, cy - 1, 6.4, 5.2 * squash, body_lt)
    s.ell(11, cy + 3, 6.0, 3.0, body_dk)

    # 脉纹
    for ang_deg in (200, 250, 290, 340):
        ang = np.deg2rad(ang_deg)
        x1 = 11 + np.cos(ang) * 7
        y1 = cy + np.sin(ang) * 6
        s.line(11, cy, x1, y1, vein)
    s.ell(11, cy, 2.2 + charge * 0.5, 2.2 + charge * 0.5, vein)
    s.px(11, cy, mix(vein, PAL["white"], 0.5 + charge * 0.15))

    # 顶部引信
    s.rect(10, cy - 9, 2, 3, body_dk)
    s.px(10, cy - 10, PAL["gold"])
    s.px(11, cy - 10, PAL["gold_lt"] if charge > 0 else PAL["gold_dk"])
    if charge > 0:
        for k in range(charge + 1):
            s.px(11 + (k % 3) - 1, cy - 11 - (k // 3), mix(PAL["gold_lt"], PAL["white"], 0.5))

    dither(s, 4, cy - 5, 14, 10, shade(body, -0.2), 0.12, rng)

    s.bevel(0.22, 0.26)
    s.outline(PAL["outline"], diag=True)
    return s


def gen_enemies() -> int:
    n = 0
    for f in range(3):
        make_husk(f, False).save("sprites/enemies/husk_%d.png" % f)
        make_husk(f, True).save("sprites/enemies/husk_elite_%d.png" % f)
        n += 2
    for f in range(4):
        make_hexeye(f, False).save("sprites/enemies/hexeye_%d.png" % f)
        make_hexeye(f, True).save("sprites/enemies/hexeye_elite_%d.png" % f)
        n += 2
    for f in range(4):
        for charge in range(4):
            suffix = "" if charge == 0 else "_c%d" % charge
            make_bloom(f, False, charge).save("sprites/enemies/bloom_%d%s.png" % (f, suffix))
            n += 1
        make_bloom(f, True, 0).save("sprites/enemies/bloom_elite_%d.png" % f)
        n += 1
    return n


# ------------------------------------------------------------------ Boss A：晶核守卫

WARDEN_W, WARDEN_H = 56, 58


def make_warden(frame: int) -> Spr:
    s = Spr(WARDEN_W, WARDEN_H)
    stone = PAL["warden"]
    stone_dk = PAL["warden_dk"]
    stone_lt = PAL["warden_lt"]
    core = [PAL["cry"], PAL["cry_lt"], PAL["cry_glow"], PAL["cry_lt"]][frame % 4]
    rng = np.random.default_rng(31 + frame)

    sh = Spr(WARDEN_W, WARDEN_H)
    sh.ell(28, 55, 18, 3, (6, 6, 12, 130))
    s.paste(sh, 0, 0)

    bob = [0, -1, 0, 1][frame % 4]
    arm_off = [0, 1, 2, 1][frame % 4]

    # 双腿
    s.rect(16, 42, 9, 12, stone_dk)
    s.rect(31, 42, 9, 12, stone_dk)
    s.rect(15, 52, 11, 4, stone)
    s.rect(30, 52, 11, 4, stone)
    s.rect(16, 42, 9, 2, stone)
    s.rect(31, 42, 9, 2, stone)

    # 躯干
    ty = 18 + bob
    s.poly([(14, ty + 4), (42, ty + 4), (46, ty + 24), (10, ty + 24)], stone)
    s.poly([(16, ty + 5), (40, ty + 5), (42, ty + 12), (14, ty + 12)], stone_lt)
    s.poly([(12, ty + 20), (44, ty + 20), (46, ty + 24), (10, ty + 24)], stone_dk)
    # 胸甲裂纹
    for k in range(3):
        x0 = 18 + k * 8
        s.line(x0, ty + 8, x0 + 3, ty + 18, shade(stone_dk, -0.15))

    # 核心（胸口晶体，随帧脉动）
    ccx, ccy = 28, ty + 14
    r = 5 + (1 if frame % 4 == 2 else 0)
    s.poly([(ccx, ccy - r - 2), (ccx + r, ccy), (ccx, ccy + r + 2), (ccx - r, ccy)], core)
    s.poly([(ccx, ccy - r), (ccx + r - 2, ccy), (ccx, ccy + r), (ccx - r + 2, ccy)], mix(core, PAL["white"], 0.45))
    s.px(ccx - 1, ccy - 2, PAL["white"])

    # 肩甲 + 肩晶
    for sx in (10, 46):
        s.ell(sx, ty + 6, 7, 5, stone)
        s.ell(sx, ty + 5, 5, 3, stone_lt)
        s.tri(sx - 3, ty + 1, sx + 3, ty + 1, sx, ty - 8, PAL["cry_dk"])
        s.tri(sx - 2, ty + 1, sx + 2, ty + 1, sx, ty - 6, PAL["cry"])
        s.px(sx, ty - 7, PAL["cry_lt"])

    # 手臂 + 拳
    for side, ax in ((-1, 8), (1, 48)):
        ay = ty + 10 + arm_off
        s.rect(ax - 3, ay, 6, 14, stone_dk)
        s.rect(ax - 3, ay, 6, 3, stone)
        s.ell(ax, ay + 16, 5.5, 5.0, stone)
        s.ell(ax, ay + 15, 4.0, 3.4, stone_lt)
        for k in range(3):
            s.px(ax - 2 + k * 2, ay + 19, stone_dk)

    # 头（小而厚，嵌在两肩之间）
    hy = ty - 4 + bob
    s.rect(21, hy, 14, 10, stone)
    s.rect(21, hy, 14, 3, stone_lt)
    s.rect(23, hy + 4, 10, 4, PAL["black"])
    ex = [0, 1, 0, -1][frame % 4]
    s.px(25 + ex, hy + 5, core)
    s.px(26 + ex, hy + 5, mix(core, PAL["white"], 0.5))
    s.px(30 + ex, hy + 5, core)
    s.px(29 + ex, hy + 5, mix(core, PAL["white"], 0.5))
    # 头冠晶体
    s.tri(24, hy, 32, hy, 28, hy - 7, PAL["cry"])
    s.px(28, hy - 6, PAL["cry_lt"])

    dither(s, 12, ty + 6, 32, 18, shade(stone, -0.16), 0.1, rng)

    s.bevel(0.18, 0.24)
    s.outline(PAL["outline"], diag=True)
    return s


# ------------------------------------------------------------------ Boss B：深渊织者

WEAVER_W, WEAVER_H = 64, 60


def make_weaver(frame: int) -> Spr:
    s = Spr(WEAVER_W, WEAVER_H)
    body = PAL["weaver"]
    body_dk = PAL["weaver_dk"]
    body_lt = PAL["weaver_lt"]
    eye = [PAL["gold"], PAL["gold_lt"], PAL["red_lt"], PAL["gold_lt"]][frame % 4]
    rng = np.random.default_rng(47 + frame)

    sh = Spr(WEAVER_W, WEAVER_H)
    sh.ell(32, 56, 16, 3, (6, 6, 12, 120))
    s.paste(sh, 0, 0)

    bob = [0, -2, -3, -1][frame % 4]
    cy = 24 + bob

    # 触须（6 条，随帧波动）
    for k in range(6):
        base_ang = np.deg2rad(-160 + k * 56)
        for seg in range(16):
            t = seg / 15.0
            wave = np.sin(frame * 1.2 + k * 1.1 + t * 4.0) * (3.0 + t * 6.0)
            x = 32 + np.cos(base_ang) * (8 + t * 22) + np.cos(base_ang + np.pi / 2) * wave * 0.4
            y = cy + np.sin(base_ang) * (6 + t * 16) + t * 10 + wave * 0.35
            thick = 3.2 - t * 2.2
            col = mix(body, body_dk, t)
            s.ell(x, y, max(0.8, thick), max(0.8, thick), col)
        # 触须尖端发光
        tx = 32 + np.cos(base_ang) * 30
        ty2 = cy + np.sin(base_ang) * 22 + 10
        s.px(int(tx), int(ty2), PAL["cry"])

    # 主体（斗篷状）
    s.poly([(16, cy - 6), (48, cy - 6), (54, cy + 12), (32, cy + 22), (10, cy + 12)], body)
    s.poly([(18, cy - 6), (46, cy - 6), (48, cy + 2), (16, cy + 2)], body_lt)
    s.poly([(12, cy + 12), (52, cy + 12), (32, cy + 22)], body_dk)
    # 布纹
    for k in range(5):
        x0 = 20 + k * 6
        s.line(x0, cy + 2, x0 - 2, cy + 16, shade(body, -0.2))
    dither(s, 14, cy - 4, 36, 20, shade(body, -0.22), 0.1, rng)

    # 面具 / 独眼
    s.ell(32, cy - 2, 11, 9, PAL["metal_dk"])
    s.ell(32, cy - 3, 9, 7, PAL["metal"])
    s.ell(32, cy - 2, 6.5, 5.0, PAL["black"])
    s.ell(32, cy - 2, 4.6, 3.6, eye)
    s.ell(32, cy - 2, 2.2, 2.6, PAL["black"])
    s.px(30, cy - 4, PAL["white"])
    # 面具角
    s.tri(20, cy - 8, 26, cy - 10, 18, cy - 18, body_dk)
    s.tri(44, cy - 8, 38, cy - 10, 46, cy - 18, body_dk)
    s.px(18, cy - 17, PAL["cry"])
    s.px(46, cy - 17, PAL["cry"])

    # 悬浮碎晶
    for k in range(4):
        ang = frame * 0.7 + k * np.pi / 2
        ox = int(round(32 + np.cos(ang) * 24))
        oy = int(round(cy - 2 + np.sin(ang) * 12))
        s.poly([(ox, oy - 2), (ox + 2, oy), (ox, oy + 2), (ox - 2, oy)], PAL["cry"])
        s.px(ox, oy - 1, PAL["cry_lt"])

    s.bevel(0.16, 0.24)
    s.outline(PAL["outline"], diag=True)
    return s


def gen_bosses() -> int:
    n = 0
    for f in range(4):
        make_warden(f).save("sprites/bosses/warden_%d.png" % f)
        make_weaver(f).save("sprites/bosses/weaver_%d.png" % f)
        n += 2
    return n


def main() -> int:
    total = 0
    total += gen_player()
    total += gen_enemies()
    total += gen_bosses()
    print("[gen_characters] 生成精灵 %d 个" % total)
    return total


if __name__ == "__main__":
    main()

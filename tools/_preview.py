# -*- coding: utf-8 -*-
"""_preview.py —— 把生成的素材拼成放大联系图（contact sheet），便于肉眼校验。

输出目录固定为 tools/_preview/（内含 .gdignore，Godot 不会导入这些开发用图）。

    python tools/_preview.py                 # 重新渲染全部分组
    python tools/_preview.py player bosses    # 只渲染指定分组

每个分组一张 PNG：棋盘透明底 + 5 倍最近邻放大 + 文件名标注。
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixel import ASSETS_ROOT  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "_preview")

SCALE = 5
PAD = 3
LABEL_H = 18

# 分组名 -> assets/ 下的相对目录
GROUPS = {
    "player": "sprites/player",
    "enemies": "sprites/enemies",
    "bosses": "sprites/bosses",
    "tiles": "tiles",
    "props": "props",
    "fx": "fx",
    "pickups": "pickups",
    "ui": "ui",
    "weapons": "weapons",
}


def _checker(size: tuple[int, int]) -> Image.Image:
    """棋盘透明底，方便看清 Alpha 边缘。"""
    bg = Image.new("RGB", size)
    dr = ImageDraw.Draw(bg)
    cs = 6
    for j in range(0, size[1], cs):
        for i in range(0, size[0], cs):
            fill = (44, 44, 58) if ((i // cs) + (j // cs)) % 2 == 0 else (34, 34, 46)
            dr.rectangle([i, j, i + cs - 1, j + cs - 1], fill=fill)
    return bg


def _rows(files: list[str], d: str, per_row: int) -> list[list[str]]:
    """按每行 per_row 个切分；per_row<=0 表示单行。"""
    if per_row <= 0 or len(files) <= per_row:
        return [files]
    return [files[i:i + per_row] for i in range(0, len(files), per_row)]


def render(group: str, rel: str, per_row: int = 0) -> str | None:
    d = os.path.join(ASSETS_ROOT, *rel.split("/"))
    if not os.path.isdir(d):
        print("  [跳过] %s：目录不存在 %s" % (group, rel))
        return None
    files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
    if not files:
        print("  [跳过] %s：无 PNG" % group)
        return None

    row_groups = _rows(files, d, per_row)

    # 逐行装载图片并计算尺寸
    layout: list[list[tuple[str, Image.Image]]] = []
    for row_files in row_groups:
        layout.append([(f, Image.open(os.path.join(d, f)).convert("RGBA")) for f in row_files])

    row_h = [max(im.height for _, im in row) * SCALE for row in layout]
    row_w = [sum(im.width * SCALE + PAD for _, im in row) for row in layout]
    W = max(max(row_w) + 130, 420)
    H = sum(h + PAD + LABEL_H for h in row_h) + 16

    sheet = Image.new("RGB", (W, H), (18, 18, 26))
    dr = ImageDraw.Draw(sheet)
    dr.text((6, 4), "%s  (%d)" % (group.upper(), len(files)), fill=(230, 200, 120))
    y = LABEL_H
    for row, h in zip(layout, row_h):
        x = 104
        for fname, im in row:
            big = im.resize((im.width * SCALE, im.height * SCALE), Image.NEAREST)
            bg = _checker(big.size)
            bg.paste(big, (0, 0), big)
            sheet.paste(bg, (x, y))
            dr.rectangle([x, y, x + big.width, y + big.height], outline=(70, 70, 90))
            dr.text((x, y + big.height + 1), fname[:-4], fill=(150, 150, 170))
            x += big.width + PAD
        y += h + PAD + LABEL_H

    os.makedirs(OUT_DIR, exist_ok=True)
    dst = os.path.join(OUT_DIR, group + ".png")
    sheet.save(dst)
    print("  saved %-10s %s  %dx%d" % (group + ".png", rel, sheet.width, sheet.height))
    return dst


def main(argv: list[str]) -> int:
    names = argv[1:] or list(GROUPS.keys())
    unknown = [n for n in names if n not in GROUPS]
    if unknown:
        print("未知分组：%s" % ", ".join(unknown))
        print("可用分组：%s" % ", ".join(GROUPS.keys()))
        return 2
    # 图多的分组换行排版，避免单张过宽
    per_row = {"fx": 16, "pickups": 14, "ui": 12, "enemies": 10, "player": 8}
    print("[_preview] 渲染联系图 -> %s" % OUT_DIR)
    for n in names:
        render(n, GROUPS[n], per_row.get(n, 0))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

#!/usr/bin/env python3
"""check_charset.py —— 校验游戏内可见文案是否都被 pixel_ui.ttf 子集覆盖。

扫描 scripts/ 与 autoload/ 下所有 .gd 文件的**字符串字面量**（跳过注释），
提取其中的 CJK 字符，与 assets/fonts/_charset.txt 比对，报告缺字。

用法：
    python tools/check_charset.py           # 只报告
    python tools/check_charset.py --json    # 输出 JSON，便于程序化处理
退出码：0 = 无缺字；1 = 存在缺字。
"""
from __future__ import annotations

import glob
import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARSET = os.path.join(ROOT, "assets", "fonts", "_charset.txt")


def _scan_dirs() -> list[str]:
    files: list[str] = []
    for pattern in ("scripts/**/*.gd", "autoload/*.gd"):
        files.extend(glob.glob(os.path.join(ROOT, pattern), recursive=True))
    return sorted(files)


def string_literals(text: str) -> list[str]:
    """极简 GDScript 字面量提取：识别 "..." 与 '...'，跳过 # 注释。"""
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "#":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            i += 1
            buf: list[str] = []
            while i < n and text[i] != quote:
                if text[i] == "\\" and i + 1 < n:
                    buf.append(text[i + 1])
                    i += 2
                    continue
                buf.append(text[i])
                i += 1
            i += 1
            out.append("".join(buf))
            continue
        i += 1
    return out


def cjk(chars: str) -> set[str]:
    return {c for c in chars if "\u4e00" <= c <= "\u9fff"}


def main() -> int:
    with io.open(CHARSET, encoding="utf-8") as fh:
        covered = set(fh.read())

    report: dict[str, str] = {}
    missing_all: set[str] = set()
    for path in _scan_dirs():
        with io.open(path, encoding="utf-8") as fh:
            text = fh.read()
        used: set[str] = set()
        for lit in string_literals(text):
            used |= cjk(lit)
        bad = used - covered
        if bad:
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            report[rel] = "".join(sorted(bad))
            missing_all |= bad

    if "--json" in sys.argv:
        print(json.dumps({"missing_total": "".join(sorted(missing_all)),
                          "by_file": report, "covered_chars": len(covered)},
                         ensure_ascii=False, indent=2))
    else:
        for rel, bad in sorted(report.items()):
            print("%s -> %s" % (rel, bad))
        print("files_with_missing=%d missing_chars=%d covered=%d"
              % (len(report), len(missing_all), len(covered)))
        print("MISSING: %s" % "".join(sorted(missing_all)))
    return 1 if missing_all else 0


if __name__ == "__main__":
    sys.exit(main())

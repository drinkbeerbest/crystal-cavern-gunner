# -*- coding: utf-8 -*-
"""patch_import_settings.py —— 修正 Godot 导入参数（素材管线收尾步骤）。

Godot 4.7 对 WAV 的默认导入参数是 `compress/mode=2`（QOA 有损压缩），
这会给合成音效的高频瞬态（枪声、爆炸、UI 提示音）带来可闻损失。
本脚本把工程内全部音频统一改成：

    compress/mode=0     PCM（无损，16bit 原样保留，零解码开销）
    edit/loop_mode=2    Forward —— 需要无缝循环的 BGM
    edit/loop_mode=1    Disabled —— 一次性播放的结算曲与音效

注意 `edit/loop_mode` 的枚举与 AudioStreamWAV::LoopMode **有 +1 偏移**
（editor/import/resource_importer_wav.cpp：
"Detect From WAV, Disabled, Forward, Ping-Pong, Backward"），
所以"前向循环"要写 2 而不是 1，写 1 反而是关闭循环。
gen_audio.py 已为循环曲写入 smpl 采样器块，因此 0（Detect From WAV）
也能自动识别；这里显式写死 2/1，避免依赖探测。

只有当参数真的发生变化时才改写文件，并同步删除 Godot 已生成的导入缓存
（.godot/imported/*.sample），迫使下一次 `--import` 按新参数重新导入。

用法：
    python tools/patch_import_settings.py          # 修正 assets/ 下全部 .wav.import
    python tools/patch_import_settings.py --report  # 只报告现状，不写盘
"""
from __future__ import annotations

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ASSETS = os.path.join(ROOT, "assets")
GODOT_IMPORTED = os.path.join(ROOT, ".godot", "imported")

# 需要无缝循环的背景音乐（与 gen_audio.py 的 BGM 表一致）
LOOPING_BGM = {
    "menu.wav",
    "dungeon_1.wav",
    "dungeon_2.wav",
    "dungeon_3.wav",
    "boss.wav",
    "shop.wav",
}
# 一次性播放：victory.wav / gameover.wav 及全部 sfx

# 目标参数：键 -> 期望值（字符串形式，直接写进 .import）
DESIRED = {
    "compress/mode": "0",      # 0 = PCM（无损）
    "force/8_bit": "false",
    "force/mono": "false",
    "force/max_rate": "false",
    "edit/trim": "false",
    "edit/normalize": "false",
}

_PARAM_LINE = re.compile(r"^([a-z_0-9/]+)=(.*)$")


def _desired_for(filename: str) -> dict[str, str]:
    """按文件名给出该音频应有的完整参数期望。"""
    want = dict(DESIRED)
    # 枚举带 +1 偏移：2 = Forward（循环），1 = Disabled（单次）
    want["edit/loop_mode"] = "2" if filename in LOOPING_BGM else "1"
    want["edit/loop_begin"] = "0"
    want["edit/loop_end"] = "-1"
    return want


def _read_params(text: str) -> dict[str, str]:
    """解析 .import 的 [params] 段。"""
    out: dict[str, str] = {}
    in_params = False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("["):
            in_params = s == "[params]"
            continue
        if in_params and s:
            m = _PARAM_LINE.match(s)
            if m:
                out[m.group(1)] = m.group(2)
    return out


def _dest_files(text: str) -> list[str]:
    """取出 [dest_files] 段记录的导入产物路径（用于失效缓存）。"""
    dests: list[str] = []
    in_dest = False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("["):
            in_dest = s == "[dest_files]"
            continue
        if in_dest and s:
            m = re.match(r'^[a-z0-9_.]+="([^"]+)"$', s)
            if m:
                dests.append(m.group(1))
    return dests


def _apply(text: str, want: dict[str, str]) -> tuple[str, bool]:
    """把 want 写入 [params] 段（已有键替换，缺失键追加），返回新文本与是否改动。"""
    lines = text.splitlines()
    out: list[str] = []
    in_params = False
    params_start = -1
    seen: set[str] = set()
    changed = False

    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("["):
            in_params = s == "[params]"
            if in_params:
                params_start = len(out)
            out.append(line)
            continue
        if in_params and s:
            m = _PARAM_LINE.match(s)
            if m and m.group(1) in want:
                key = m.group(1)
                seen.add(key)
                new_line = "%s=%s" % (key, want[key])
                if new_line != s:
                    changed = True
                out.append(new_line)
                continue
        out.append(line)

    if params_start >= 0:
        missing = [k for k in want if k not in seen]
        if missing:
            changed = True
            insert_at = len(out)
            for j in range(params_start + 1, len(out)):
                if out[j].strip() and not out[j].startswith("["):
                    insert_at = j + 1
            for k in missing:
                out.insert(insert_at, "%s=%s" % (k, want[k]))
                insert_at += 1

    return "\n".join(out) + "\n", changed


def patch(report_only: bool = False) -> int:
    """扫描 assets/ 下全部 .wav.import，返回修正数量。"""
    targets: list[str] = []
    for dirpath, _dirs, files in os.walk(ASSETS):
        for fn in sorted(files):
            if fn.endswith(".wav.import"):
                targets.append(os.path.join(dirpath, fn))
    targets.sort()

    n_fixed = 0
    n_loop = 0
    cache_dropped = 0
    for path in targets:
        src_name = os.path.basename(path)[: -len(".import")]
        with open(path, "r", encoding="utf-8", newline="") as f:
            text = f.read()
        want = _desired_for(src_name)
        new_text, changed = _apply(text, want)
        if want["edit/loop_mode"] == "2":
            n_loop += 1
        if not changed:
            continue
        n_fixed += 1
        if report_only:
            print("  [需修正] %s" % os.path.relpath(path, ROOT).replace("\\", "/"))
            continue
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(new_text)
        # 参数变了 -> 删除已导入产物，强制 Godot 按新参数重新导入
        for dest in _dest_files(text):
            rel = dest.replace("res://", "")
            full = os.path.join(ROOT, ".godot", rel) if rel.startswith("imported") else None
            if full is None:
                full = os.path.join(GODOT_IMPORTED, os.path.basename(rel))
            if os.path.isfile(full):
                os.remove(full)
                cache_dropped += 1

    print("[patch_import] 音频导入文件 %d 个（循环 BGM %d 首）" % (len(targets), n_loop))
    if report_only:
        print("[patch_import] 报告模式：%d 个需要修正" % n_fixed)
    else:
        print("[patch_import] 已修正 %d 个，失效导入缓存 %d 个" % (n_fixed, cache_dropped))
    if n_fixed == 0 and not report_only:
        print("[patch_import] 全部音频已是 PCM + 正确循环设置")
    return n_fixed


def main(argv: list[str]) -> int:
    return 0 if patch("--report" in argv) >= 0 else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

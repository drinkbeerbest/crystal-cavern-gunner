# -*- coding: utf-8 -*-
"""build_assets.py —— 素材管线统一入口。

一条命令重新生成工程内**全部**原创素材（美术 + 字体 + 音频）：

    python tools/build_assets.py            # 全量重建
    python tools/build_assets.py ui fx      # 只重建指定模块
    python tools/build_assets.py --check    # 只清点 assets/ 现状，不重新生成

模块名 -> 脚本：
    chars  gen_characters.py   角色 / 敌人 / Boss 精灵
    world  gen_world.py        地砖 / 墙体 / 门 / 场景道具
    fx     gen_fx.py           粒子、弹道、拾取物
    ui     gen_ui.py           界面元素、图标、武器贴图
    font   gen_font.py         UI 位图字体子集（依赖 tools/fetch_font.sh 下载的开源字体）
    audio  gen_audio.py        程序合成音效与背景音乐

最后会输出一份素材清单统计（按目录、按扩展名、总体积），便于交付前核对；
并调用 patch_import_settings.py 把音频的 Godot 导入参数统一为 PCM 无损 +
BGM 循环点（`--check` 模式下只报告不写盘）。
"""
from __future__ import annotations

import os
import runpy
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ASSETS = os.path.join(ROOT, "assets")

MODULES = [
    ("chars", "gen_characters.py", "角色 / 敌人 / Boss 精灵"),
    ("world", "gen_world.py", "地砖 / 墙体 / 门 / 场景道具"),
    ("fx", "gen_fx.py", "粒子 / 弹道 / 拾取物"),
    ("ui", "gen_ui.py", "界面元素 / 图标 / 武器贴图"),
    ("font", "gen_font.py", "UI 位图字体子集"),
    ("audio", "gen_audio.py", "音效与背景音乐（程序合成）"),
]


def run_module(script: str) -> None:
    path = os.path.join(HERE, script)
    if not os.path.isfile(path):
        raise SystemExit("[build_assets] 缺少脚本：%s" % path)
    print("\n" + "=" * 68)
    print("[build_assets] 运行 %s" % script)
    print("=" * 68)
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    runpy.run_path(path, run_name="__main__")


def census() -> None:
    """清点 assets/ 目录，输出统计。"""
    by_ext: dict[str, int] = {}
    by_dir: dict[str, int] = {}
    total_bytes = 0
    n_files = 0
    for dirpath, _dirnames, filenames in os.walk(ASSETS):
        for fn in sorted(filenames):
            full = os.path.join(dirpath, fn)
            ext = os.path.splitext(fn)[1].lower() or "(none)"
            rel_dir = os.path.relpath(dirpath, ASSETS).replace("\\", "/")
            rel_dir = "." if rel_dir == "." else rel_dir
            by_ext[ext] = by_ext.get(ext, 0) + 1
            by_dir[rel_dir] = by_dir.get(rel_dir, 0) + 1
            total_bytes += os.path.getsize(full)
            n_files += 1

    print("\n" + "=" * 68)
    print("[build_assets] assets/ 素材清单")
    print("=" * 68)
    print("文件总数：%d    总体积：%.2f MB" % (n_files, total_bytes / 1048576.0))
    print("\n按类型：")
    for ext in sorted(by_ext, key=lambda e: -by_ext[e]):
        print("  %-8s %4d 个" % (ext, by_ext[ext]))
    print("\n按目录：")
    for d in sorted(by_dir):
        print("  %-28s %4d 个" % (d, by_dir[d]))


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if not a.startswith("--")]
    check_only = "--check" in argv

    if not check_only:
        if args:
            selected = [m for m in MODULES if m[0] in args]
            unknown = set(args) - {m[0] for m in MODULES}
            if unknown:
                print("[build_assets] 未知模块：%s" % ", ".join(sorted(unknown)))
                print("[build_assets] 可用模块：%s" % ", ".join(m[0] for m in MODULES))
                return 2
        else:
            selected = list(MODULES)

        t0 = time.time()
        for key, script, desc in selected:
            print("\n>>> [%s] %s" % (key, desc))
            run_module(script)
        print("\n[build_assets] 生成完成，用时 %.1f 秒" % (time.time() - t0))

    # Godot 导入参数收尾：音频统一 PCM 无损 + BGM 循环点。
    # 生成后必须执行，否则 Godot 会用默认的 QOA 有损压缩重导入音频。
    print("\n>>> [import] 修正 Godot 导入参数")
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    import patch_import_settings

    patch_import_settings.patch(report_only=check_only)

    census()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

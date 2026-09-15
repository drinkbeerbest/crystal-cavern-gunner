# -*- coding: utf-8 -*-
"""gen_font.py —— 生成工程内嵌的 UI 字体。

字体来源：Fusion Pixel Font（融合像素字体），作者 TakWolf，
许可证 SIL Open Font License 1.1，可自由使用与再分发（OFL 全文随工程一起放在
assets/fonts/OFL-fusion-pixel-font.txt）。这是**开源授权字体**，非搬运的商用素材。

做法：
1. 从完整 TTF（约 7MB，覆盖全部常用汉字）中，按"工程内实际用到的字符 +
   ASCII + 常用中文标点 + 安全字符表"做子集化，输出 assets/fonts/pixel_ui.ttf；
2. 子集化后体积降到几百 KB，Godot 导入更快；
3. 因为字符集是**扫描工程源码**得到的，所以任何时候新增了中文文案，
   重新跑一次本脚本即可（build_assets.py 会自动调用）。
"""
from __future__ import annotations

import os
import shutil
import sys

from fontTools import subset

from pixel import PROJECT_ROOT, out_path

FONT_DIR = out_path("fonts")
# 源字体放在工程外（约 7MB），不进交付包；只把子集化结果放进 assets/fonts。
# 可用环境变量 FPFONT_DIR 覆盖，或运行 tools/fetch_font.sh 自动下载。
_DEFAULT_SRC = r"D:/game1_fontsrc"
_SRC_DIR = os.environ.get("FPFONT_DIR", _DEFAULT_SRC)
SRC_FONT = os.path.join(_SRC_DIR, "fusion-pixel-12px-monospaced-zh_hans.ttf")
SRC_LICENSE = os.path.join(_SRC_DIR, "OFL.txt")
DST_FONT = os.path.join(FONT_DIR, "pixel_ui.ttf")
DST_LICENSE = os.path.join(FONT_DIR, "OFL-fusion-pixel-font.txt")

# 扫描这些后缀的文件，收集里面出现的所有非 ASCII 字符
SCAN_EXT = (".gd", ".tscn", ".tres", ".cfg", ".godot", ".md", ".json", ".txt")
SKIP_DIRS = {".godot", ".git", "assets", "__pycache__", "_preview"}

# 安全字符表：即使源码里还没用到，也预先放进字体，避免后续漏字
SAFE_CHARS = (
    "　、。《》【】〈〉「」『』（）〔〕—…·～￥＄％＆＊＋－／＼＝＜＞＠＾＿｜"
    "①②③④⑤⑥⑦⑧⑨⑩★☆♥♡◆◇○●◎△▲▽▼□■※→←↑↓↔↕"
    "的一是了我不人在他有这个上们来到时大地为子中你说生国年着就那和要她出也得里后自以会家可下而过天去能对小多然于心学么之都好看起发当没成只如事把还用第样道想作种开美总从无情己面最女但现前些所同日手又行意动方期它头经长儿回位分爱老因很给名法间斯知世什两次使身者被高已亲其进此话常与活正感"
    "见明问力理尔点文几定本公特做外孩相西果走将月十实向声车全信重三机工物气每并别真打太新比才便夫再书部水像眼等体却加电主界门利海受听表德少克代员许稜先口由死安写性马光白或住难望教命花结乐色更拉东神记处让母父应直字场平报友关放至张认接告入笑内英军候民岁往何度山觉路带万男边风解叫任金快原吃妈变通师立象数四失满战远格士音轻目条呢病始达深完今提求清王化空业思切怎非找片罗钱吗语元喜曾离飞科言干欢势尽且乐打坚尔尽农重层血战激突全强毒久忘沉防承印晚兰试双令难早虫冲吸责声阶护交林临夜字属幸按爱钱买杀苦若胜护读断深交难护"
    "游戏开始继续退出设置音量音乐音效全屏窗口分辨率按键移动射击冲刺技能交互暂停返回主菜单重开下一层当前金币生命护盾能量伤害暴击射速弹速散射击退天赋临时增益剩余时间层数房间怪物精英首领传送门宝箱商店祭坛钥匙武器手枪霰弹枪激光冲锋狙击火箭法杖刀刃拾取掉落已解锁未解锁胜利失败通关死亡复活得分时间难度简单普通困难地狱提示操作说明左键右键空格方向键鼠标键盘手柄版本作者致谢素材原创程序化生成无外部资源退出确认是否保存加载存档新档位覆盖删除重置默认应用取消确定关闭打开显示隐藏锁定解锁上下左右前后"
    "晶窟枪魂地牢深渊守卫织者游魂六眼孢子爆破者新手老兵专家传奇"
    # 商店 / 结算 / 状态类词汇：UI 文案常用，预先入字体，避免运行期缺字
    "购买出售售价折扣余额不足请稍加载中噩梦刷新随机稀有传说史诗精良破损"
    "弹药装填连发蓄力穿透弹跳燃烧冰冻中毒眩晕减速回血回复复活点存档读档"
    "排行记录最高分历史成就目标奖励惩罚任务关卡章节小怪属性等级经验升级"
)


def collect_chars() -> set:
    """扫描工程源码，收集所有非 ASCII 字符。"""
    chars = set(SAFE_CHARS)
    root = PROJECT_ROOT
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for fn in filenames:
            if not fn.endswith(SCAN_EXT):
                continue
            p = os.path.join(dirpath, fn)
            try:
                with open(p, encoding="utf-8", errors="ignore") as f:
                    text = f.read()
            except OSError:
                continue
            for ch in text:
                if ord(ch) > 127:
                    chars.add(ch)
    # ASCII 可打印字符
    chars |= {chr(i) for i in range(32, 127)}
    return chars


def main() -> int:
    if not os.path.isfile(SRC_FONT):
        print("[gen_font] 未找到源字体：%s" % SRC_FONT)
        print("           请先运行 tools/fetch_font.sh 下载 Fusion Pixel Font。")
        return 1

    chars = collect_chars()
    # 过滤掉字体本身不支持的字符（否则 subset 会静默丢弃，无害）
    text = "".join(sorted(chars))
    print("[gen_font] 字符集大小：%d" % len(text))

    os.makedirs(FONT_DIR, exist_ok=True)
    args = [
        SRC_FONT,
        "--output-file=%s" % DST_FONT,
        "--flavor=",
        "--layout-features=*",
        "--glyph-names",
        "--no-hinting",
        "--desubroutinize",
        "--text-file=%s" % _write_charset(text),
    ]
    subset.main([a for a in args if a != "--flavor="])
    size = os.path.getsize(DST_FONT)
    print("[gen_font] 子集字体：%s (%.1f KB)" % (DST_FONT, size / 1024.0))

    if os.path.isfile(SRC_LICENSE):
        shutil.copyfile(SRC_LICENSE, DST_LICENSE)
        print("[gen_font] 已复制 OFL 许可证 -> %s" % os.path.basename(DST_LICENSE))
    return 0


def _write_charset(text: str) -> str:
    p = os.path.join(FONT_DIR, "_charset.txt")
    with open(p, "w", encoding="utf-8") as f:
        f.write(text)
    return p


if __name__ == "__main__":
    sys.exit(main())

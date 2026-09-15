#!/usr/bin/env bash
# 下载开源像素中文字体 Fusion Pixel Font（SIL OFL 1.1）到工程外目录 D:/game1_fontsrc。
# 只在首次构建或换机器时需要跑一次；之后 tools/gen_font.py 会据此生成子集字体。
set -euo pipefail
VER="${1:-2026.09.01}"
DEST="D:/game1_fontsrc"
TMP="$(mktemp -d)"
URL="https://github.com/TakWolf/fusion-pixel-font/releases/download/${VER}/fusion-pixel-font-12px-monospaced-ttf-v${VER}.zip"
echo "下载 ${URL}"
curl -sL --max-time 300 -o "${TMP}/fp.zip" "${URL}"
mkdir -p "${TMP}/x" && cd "${TMP}/x" && unzip -oq "${TMP}/fp.zip"
mkdir -p "${DEST}"
cp fusion-pixel-12px-monospaced-zh_hans.ttf "${DEST}/"
cp OFL.txt "${DEST}/"
cp -r LICENSES "${DEST}/" 2>/dev/null || true
echo "完成：${DEST}"

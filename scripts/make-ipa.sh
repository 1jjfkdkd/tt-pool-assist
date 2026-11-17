#!/bin/bash
# make-ipa.sh — 在 macOS 上一键出未签名 ipa
# 用法: bash scripts/make-ipa.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "[i] 安装 xcodegen …"
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "请先安装 Homebrew，或手动装 xcodegen"; exit 1
  fi
fi

echo "[1/4] 生成工程"
xcodegen generate

echo "[2/4] 编译（未签名）"
xcodebuild -project TTPoolAssist.xcodeproj \
  -scheme TTPoolAssist \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

echo "[3/4] 打包"
APP=$(find build/Build/Products/Release-iphoneos -maxdepth 1 -name "*.app" | head -1)
if [ -z "$APP" ]; then echo "没找到 .app"; exit 1; fi
rm -rf out TTPoolAssist.ipa
mkdir -p out/Payload
cp -R "$APP" out/Payload/
(cd out && zip -qry ../TTPoolAssist.ipa Payload)

echo "[4/4] 完成"
ls -lh TTPoolAssist.ipa
echo "用 TrollStore / Sideloadly 自签安装"

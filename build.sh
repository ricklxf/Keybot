#!/bin/bash
set -e

APP="Keybot"
OUT=".build/release"
BUNDLE=".build/${APP}.app"

echo "▶ 编译..."
swift build -c release

echo "▶ 打包 .app..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
cp "$OUT/$APP"              "$BUNDLE/Contents/MacOS/$APP"
cp "Resources/Info.plist"  "$BUNDLE/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "▶ Ad-hoc 签名..."
codesign --force --sign - "$BUNDLE"

echo ""
echo "✅ 完成：$BUNDLE"
echo ""
echo "安装到 Applications："
echo "  cp -r $BUNDLE /Applications/"
echo ""
echo "首次运行后需要在「系统设置 → 隐私与安全性 → 辅助功能」里授权 Keybot。"

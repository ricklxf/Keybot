#!/bin/bash
set -e

APP="Keybot"
OUT=".build/release"
BUNDLE=".build/${APP}.app"
INSTALL="/Applications/${APP}.app"

echo "▶ 编译..."
swift build -c release

echo "▶ 打包 .app..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"
cp "$OUT/$APP"               "$BUNDLE/Contents/MacOS/$APP"
cp "Resources/Info.plist"   "$BUNDLE/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "▶ 签名..."
CERT="Keybot"
if security find-identity -p codesigning -v 2>/dev/null | grep -q "\"$CERT\""; then
    codesign --force --sign "$CERT" "$BUNDLE"
else
    echo "  ⚠️  未找到本地证书，使用 ad-hoc 签名（每次构建需重新授权辅助功能）"
    echo "  → 运行 'bash scripts/create_cert.sh' 一次性修复此问题"
    codesign --force --sign - "$BUNDLE"
fi

echo "▶ 安装到 /Applications..."
pkill "$APP" 2>/dev/null || true
cp -r "$BUNDLE" "$INSTALL"
xattr -cr "$INSTALL"

echo "▶ 刷新图标缓存..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -kill -r -domain local -domain system -domain user 2>/dev/null || true
killall Dock 2>/dev/null || true

echo "▶ 启动..."
sleep 1
open "$INSTALL"

echo ""
echo "✅ 完成 v$(grep 'let appVersion' Sources/Keybot/Version.swift | sed 's/.*"\(.*\)".*/\1/')"

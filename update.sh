#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "▶ 拉取最新代码..."
git pull

echo "▶ 编译..."
./build.sh

echo "▶ 安装..."
pkill Keybot 2>/dev/null || true
cp -r .build/Keybot.app /Applications/

echo "▶ 启动..."
open /Applications/Keybot.app

echo ""
echo "✅ 更新完成"

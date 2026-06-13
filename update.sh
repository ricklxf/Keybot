#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "▶ 拉取最新代码..."
git pull

./build.sh

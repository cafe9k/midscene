#!/bin/bash

# Midscene iOS Playground 启动脚本
# 自动启动 WebDriverAgent 并运行 playground

set -e

echo "🚀 启动 Midscene iOS Playground..."

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 配置
SIMULATOR_NAME="iPhone 16 Pro Max"
WDA_PORT=8100
PLAYGROUND_PORT=5800
WDA_PROJECT="$SCRIPT_DIR/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj"

# 如果未找到，安装依赖
if [ ! -e "$WDA_PROJECT" ]; then
    echo "❌ WebDriverAgent 未安装，正在安装..."
    mkdir -p "$SCRIPT_DIR/node_modules"
    cd "$SCRIPT_DIR" && pnpm add -w appium-webdriveragent --no-save
fi

[ -e "$WDA_PROJECT" ] && echo "✅ WebDriverAgent 已安装" || { echo "❌ WebDriverAgent 项目文件不存在"; exit 1; }

# 检查 WDA 是否已运行
if lsof -i :$WDA_PORT > /dev/null 2>&1; then
    echo "✅ WebDriverAgent 已在运行 (端口 $WDA_PORT)"
else
    echo "🔧 启动 WebDriverAgent 到模拟器: $SIMULATOR_NAME..."
    xcodebuild -project "$WDA_PROJECT" \
        -scheme WebDriverAgentRunner \
        -destination "platform=iOS Simulator,name=$SIMULATOR_NAME" \
        test \
        > /dev/null 2>&1 &

    # 等待 WDA 启动
    echo "⏳ 等待 WebDriverAgent 启动..."
    for i in {1..30}; do
        if lsof -i :$WDA_PORT > /dev/null 2>&1; then
            echo "✅ WebDriverAgent 已启动"
            break
        fi
        sleep 2
    done
fi

# 检查 Playground 端口是否被占用
if lsof -i :$PLAYGROUND_PORT > /dev/null 2>&1; then
    echo "⚠️  Playground 端口 $PLAYGROUND_PORT 已被占用，正在关闭..."
    lsof -ti :$PLAYGROUND_PORT | xargs kill -9 || true
    sleep 2
fi

# 运行 playground
echo "🎮 启动 iOS Playground..."
cd "$PROJECT_ROOT"
npx --yes @midscene/ios-playground

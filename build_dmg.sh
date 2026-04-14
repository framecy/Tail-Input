#!/bin/bash
set -e

# ── SimpleSwitch DMG 打包脚本 ──
# 用法: ./build_dmg.sh

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_FILE="$PROJECT_DIR/SmartInputSwitcher.xcodeproj"
SCHEME="SmartInputSwitcher"
BUILD_DIR="$PROJECT_DIR/build"
DMG_NAME="SimpleSwitch"
DMG_OUTPUT="$BUILD_DIR/${DMG_NAME}.dmg"
STAGING_DIR="$BUILD_DIR/dmg_staging"

echo "🔨 Step 1: 编译 Release 版本..."
xcodebuild -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration Release \
    CODE_SIGN_IDENTITY="-" \
    clean build 2>&1 | tail -3

# 从 xcodebuild 获取 BUILT_PRODUCTS_DIR
PRODUCTS_DIR=$(xcodebuild -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $NF}')

APP_PATH="$PRODUCTS_DIR/SmartInputSwitcher.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 编译失败：找不到 $APP_PATH"
    exit 1
fi

# 验证签名
echo ""
echo "🔐 验证代码签名..."
codesign -dvv "$APP_PATH" 2>&1 | head -3
echo "✅ 编译成功"

echo ""
echo "📦 Step 2: 准备 DMG 内容..."

# 清理旧的 staging 目录
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# 复制 App
cp -R "$APP_PATH" "$STAGING_DIR/"

# 复制 README
cp "$PROJECT_DIR/README.md" "$STAGING_DIR/使用说明.md"

# 创建 Applications 快捷方式
ln -s /Applications "$STAGING_DIR/Applications"

echo "   ├── SmartInputSwitcher.app"
echo "   ├── 使用说明.md"
echo "   └── Applications → /Applications"

echo ""
echo "💿 Step 3: 创建 DMG..."

# 删除旧 DMG
rm -f "$DMG_OUTPUT"

# 创建 DMG
hdiutil create \
    -volname "$DMG_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT"

echo ""
echo "🧹 Step 4: 清理临时文件..."
rm -rf "$STAGING_DIR"

echo ""
echo "✅ 打包完成！"
echo "   📍 DMG 位置: $DMG_OUTPUT"
echo "   📏 文件大小: $(du -sh "$DMG_OUTPUT" | cut -f1)"
echo ""
echo "   验证: open \"$DMG_OUTPUT\""

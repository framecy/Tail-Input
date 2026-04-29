#!/bin/bash
set -e

# ── TailInput DMG 打包脚本 ──
# 用法: ./build_dmg.sh [version]  (默认从 Info.plist 读取)

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_FILE="$PROJECT_DIR/TailInput.xcodeproj"
SCHEME="TailInput"
BUILD_DIR="$PROJECT_DIR/build"
STAGING_DIR="$BUILD_DIR/dmg_staging"

# 读取版本号
VERSION="${1:-$(defaults read "$PROJECT_DIR/Sources/SmartInputSwitcher/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.2.3")}"
DMG_NAME="TailInput-${VERSION}"
DMG_OUTPUT="$BUILD_DIR/${DMG_NAME}.dmg"

echo "🔨 Step 1: 编译 Release (v${VERSION})..."
xcodebuild -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration Release \
    CODE_SIGN_IDENTITY="-" \
    clean build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -5

# 获取产物目录
PRODUCTS_DIR=$(xcodebuild -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $NF}')

APP_PATH="$PRODUCTS_DIR/TailInput.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 编译失败：找不到 $APP_PATH"
    exit 1
fi

echo "✅ 编译成功：$APP_PATH"

echo ""
echo "📦 Step 2: 准备 DMG 内容..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/"
cp "$PROJECT_DIR/README.md" "$STAGING_DIR/使用说明.md"
ln -s /Applications "$STAGING_DIR/Applications"

echo "   ├── TailInput.app"
echo "   ├── 使用说明.md"
echo "   └── Applications → /Applications"

echo ""
echo "💿 Step 3: 创建 DMG..."
mkdir -p "$BUILD_DIR"
rm -f "$DMG_OUTPUT"

hdiutil create \
    -volname "TailInput $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT"

echo ""
echo "🧹 Step 4: 清理..."
rm -rf "$STAGING_DIR"

echo ""
echo "✅ 打包完成！"
echo "   📍 $DMG_OUTPUT"
echo "   📏 $(du -sh "$DMG_OUTPUT" | cut -f1)"

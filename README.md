# TailInput

TailInput 是一款轻量级、极致丝滑的 macOS 智能输入法切换工具。它常驻在菜单栏，根据当前前台应用自动切换输入法，让你的键盘永远处于最合适的状态。

## ✨ 功能特性

- **按应用自动切换**：切换到新应用时，自动将输入法切回英文（默认行为），避免快捷键冲突和误触
- **灵活的应用策略**：支持为每个应用单独配置输入法策略：
  - 🔤 **默认 / 强制英文**：切换到该应用时自动切回英文
  - 🀄 **强制中文**：切换到该应用时自动切回中文（适合微信、备忘录等）
  - ⏸️ **保持原状态**：不做任何切换
- **应用策略管理**：通过独立管理窗口查看、修改、删除所有已配置应用的策略，支持一键添加当前前台应用
- **CapsLock 兼容模式**：通过模拟系统级 CapsLock 事件完成自动切换，确保 macOS 原生的 "CapsLock 切换中英输入源" 功能始终可用，切换 App 后仍可用 CapsLock 切回中文（需辅助功能权限）
- **状态栏图标**：菜单栏固定宽度，显示当前输入法对应的 SF Symbol 图标与语言标识（`简` / `EN`），切换不抖动
- **桌面 HUD 提示**：输入法切换时在屏幕右上角显示图标 + 语言名称的半透明提示（简体中文 / English）
- **极致性能**：
  - `cachedIsChinese` 布尔缓存，热路径切换判断 O(1)，无字符串解析
  - 去除 CapsLock 路径的乐观缓存更新，快速双击 CapsLock 不再卡死
  - 输入法通知直接在主线程处理，减少一层 GCD 调度
  - 快速 Cmd+Tab 事件合并，不产生卡顿
  - 菜单懒构建，仅在点击时渲染
- **开机自启动**：一键设置随 macOS 登录自动启动

## 🛠️ 环境要求

| 项目 | 要求 |
|---|---|
| **操作系统** | macOS 13.0+ |
| **硬件** | Apple Silicon (M1/M2/M3/M4) & Intel |
| **权限** | 无需辅助功能权限（CapsLock 兼容模式需要） |

## 🚀 安装

### 方式一：DMG 安装（推荐）

下载 `TailInput.dmg`，打开后将 `TailInput.app` 拖入 Applications 文件夹即可。

### 方式二：源码编译

```bash
# 克隆仓库
git clone https://github.com/your-username/TailInput.git
cd TailInput

# 生成 Xcode 项目（需要 XcodeGen）
xcodegen generate

# 编译 Release 版本
xcodebuild -project TailInput.xcodeproj \
  -scheme TailInput \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  build

# 安装到 Applications
killall TailInput 2>/dev/null || true
cp -R build/Build/Products/Release/TailInput.app /Applications/

# 启动
open /Applications/TailInput.app
```

> 💡 也可以运行 `xcodegen generate` 后直接在 Xcode 中打开 `TailInput.xcodeproj` 点击 Run。

## 📖 使用说明

1. 启动后应用出现在菜单栏右上角，显示当前输入法状态图标（`简` / `EN`）
2. 点击菜单栏图标，可以看到当前前台应用名称
3. 为当前应用选择合适的输入法策略（默认英文 / 强制中文 / 保持原状态）
4. 点击 **管理应用策略...** 可查看和修改所有已配置应用
5. 可随时开关"自动切换"总开关

### CapsLock 兼容模式

如果你在使用 macOS 系统设置中的「使用 CapsLock 键切换中英文输入」，并且发现切换 App 后 CapsLock 失效，请开启此模式：

1. 点击菜单栏图标 → 勾选 **CapsLock 兼容模式**
2. 系统会弹出辅助功能授权请求，在「系统设置 → 隐私与安全 → 辅助功能」中允许 TailInput
3. 再次点击菜单项即可开启

开启后，自动切换将通过模拟系统级 CapsLock 键来完成，macOS 状态机保持完整，之后仍可正常用 CapsLock 切回中文。

## 👨‍💻 技术架构

```
main.swift                    → 应用入口
AppDelegate.swift             → 菜单栏 UI & NSMenuDelegate 懒构建
AppObserver.swift             → NSWorkspace 应用激活监听（事件去重 + 合并）
InputMethodManager.swift      → TIS 输入法操控（状态缓存 + CapsLock 模拟 + debounce）
ConfiguredAppStore.swift      → 应用策略数据模型（Codable 持久化 + 旧格式迁移）
AppListWindowController.swift → 应用策略管理窗口（NSTableView 展示/修改/删除）
HUDWindowController.swift     → SF Symbol 图标 HUD 弹窗（动画合并）
WelcomeWindowController.swift → 首次运行 Onboarding 流程
```

核心技术栈：
- **Text Input Source Services (TIS)**：底层键盘输入源操控，带布尔缓存优化
- **CGEvent CapsLock 模拟**：通过系统原生事件路径切换，保持 macOS 状态机一致性
- **NSWorkspace Notification**：轻量级应用切换监听，无需辅助功能权限
- **GCD DispatchWorkItem**：事件防抖与合并，确保快速切换不卡顿
- **ServiceManagement**：系统级 Launch at Login
- **Codable + UserDefaults**：应用策略持久化与版本迁移

## 📋 更新记录

### v1.2.0
- 新增：App 更名为 TailInput
- 新增：应用策略管理窗口（查看 / 修改 / 删除所有已配置应用）
- 新增：应用策略数据持久化（ConfiguredAppStore），自动迁移旧配置
- 新增：状态栏 SF Symbol 图标（中文 `character.textbox`，英文 `keyboard`）
- 新增：HUD 现代化重设计，水平布局图标 + 语言名称
- 优化：状态栏固定 56pt 宽度，彻底消除切换时宽度抖动
- 修复：移除 CapsLock 路径乐观缓存更新，消除快速双击 CapsLock 卡死问题
- 修复：移除 `handleInputMethodChange` 外层 `async`，减少通知响应延迟

### v1.1.0
- 新增：CapsLock 兼容模式（模拟系统级 CapsLock 事件）
- 新增：首次运行 Onboarding 欢迎页面
- 优化：输入法识别支持 Rime / 鼠须管
- 优化：`cachedIsChinese` 布尔缓存，O(1) 热路径判断
- 优化：输入法来源列表 500ms debounce 防抖重载

### v1.0.0
- 初始发布：按应用自动切换输入法，菜单栏常驻

## 📄 许可证

MIT License — 自由修改、编译及分发。

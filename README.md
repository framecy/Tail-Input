# Tail Input ⌨️

> 按应用自动切换输入法的 macOS 工具 — 轻量、无感知、零配置即用。

**版本：v1.3.1** · macOS 13.0+ · Apple Silicon & Intel · [下载](https://github.com/framecy/Tail-Input/releases)

---

## 功能

| 功能 | 说明 |
|---|---|
| **按应用自动切换** | 切换 App 时自动切回英文（默认），彻底告别误触中文 |
| **应用规则选择器** | 从所有已安装应用中搜索并配置策略，不局限于当前前台应用 |
| **三种规则** | 切换为英文 / 切换为中文 / 保持不变，按应用独立配置 |
| **窗口 + 菜单栏双模式** | 有 Dock 图标，可 Cmd+Tab 切换；菜单栏图标快速查看状态 |
| **CapsLock 兼容模式** | 模拟系统级 CapsLock 事件，保留 macOS 原生切换能力 |
| **HUD 提示** | 切换时屏幕右上角短暂显示当前输入法（简体中文 / English） |
| **开机自启动** | 一键注册 / 取消 Launch at Login |

---

## 安装

### DMG（推荐）

1. 下载 [`Tail-Input-1.3.1.dmg`](https://github.com/framecy/Tail-Input/releases/latest)
2. 打开后将 `Tail Input.app` 拖入 `Applications`
3. 首次运行完成 Onboarding 引导即可

### 源码编译

```bash
git clone https://github.com/framecy/Tail-Input.git
cd Tail-Input
xcodegen generate
xcodebuild -project "Tail Input.xcodeproj" -scheme TailInput \
  -configuration Release CODE_SIGN_IDENTITY="-" build
open ~/Library/Developer/Xcode/DerivedData/Tail_Input*/Build/Products/Release/Tail\ Input.app
```

---

## 使用

1. 启动后 Dock 图标出现，设置窗口自动打开
2. 点击 **+** 按钮 → 从所有已安装应用中搜索并选择应用 → 选择输入法规则
3. 菜单栏图标（⌨️）→ 快速为当前前台应用设置规则
4. **开启 App 自动切换** → 总开关，随时暂停

### 输入法规则

| 规则 | 效果 |
|---|---|
| 切换为英文 | 切换到该 App 时自动使用英文输入法 |
| 切换为中文 | 切换到该 App 时自动使用中文输入法（适合微信、备忘录等） |
| 保持不变 | 不做任何切换，保留上一个 App 的输入法状态 |
| 跟随全局（删除规则） | 使用 App 默认行为（通常切回英文），删除行即可 |

### CapsLock 兼容模式

macOS 系统设置中开启了「用 CapsLock 切换中英文」但切换 App 后 CapsLock 失效？

1. 菜单栏图标 → 勾选 **CapsLock 兼容模式**
2. 系统弹窗 → 在「系统设置 → 隐私与安全 → 辅助功能」允许 Tail Input
3. 再次点击开启

---

## 系统要求

| 项目 | 要求 |
|---|---|
| 操作系统 | macOS 13.0 Ventura 及以上 |
| 硬件 | Apple Silicon（M 系列）及 Intel |
| 权限 | 无需辅助功能权限（CapsLock 兼容模式除外） |

---

## 技术架构

```
main.swift                       → 应用入口
AppDelegate.swift                → Dock + 菜单栏 UI，NSMenuDelegate 懒构建
AppObserver.swift                → NSWorkspace 应用激活监听（去重 + 8ms 合并）
InputMethodManager.swift         → TIS 输入法切换（乐观缓存 + modeID 检测 + CapsLock 模拟）
ConfiguredAppStore.swift         → 应用策略持久化（Codable + 旧格式迁移）
AppListWindowController.swift    → 规则管理窗口（LiquidGlass 设计）
AppPickerSheetController.swift   → 应用选择器 Sheet（全量搜索 + 策略选择）
HUDWindowController.swift        → 切换 HUD 弹窗（LiquidGlass 风格）
WelcomeWindowController.swift    → 首次运行引导
```

**核心技术**：TIS (Carbon) · CGEvent · NSWorkspace · GCD DispatchWorkItem · ServiceManagement · Codable

---

## 更新记录

### v1.3.1
- 重构：设置窗口改为双栏布局 — 左侧边栏（开关 / 全局默认 / 关于）+ 右侧内容区，所有界面无弹窗
- 新增：点击状态栏图标直接唤起主窗口；右键点击仍弹出快捷菜单
- 优化：左侧底部展示 App 图标、版本号、MIT 协议与 GitHub 入口，一目了然

### v1.3.0
- 新增：应用规则选择器 — 可从所有已安装应用中搜索并配置策略，支持按名称和 Bundle ID 过滤
- 新增：窗口应用模式 — 有 Dock 图标和 Cmd+Tab 支持；点击 Dock 图标重新打开设置窗口
- 新增：启动时自动打开设置窗口（Onboarding 完成后）
- 设计：全面采用 LiquidGlass 设计语言 — 毛玻璃背景、18pt 连续圆角、精细分隔线
- 设计：规则设置窗口重设计 — 应用图标 / 名称 / Bundle ID 三层信息，简洁策略选择
- 设计：HUD 升级 — 连续圆角 18pt、顶部反光高亮、尺寸 178×66
- 设计：菜单策略选项改用系统原生 checkmark 状态与 SF Symbol 图标
- 优化：规则添加流程 — 策略选择内嵌于 Sheet，一步完成
- 修复：macOS 26 in-source 模式检测（鼠须管等输入法的 Roman 子模式识别）
- 修复：CapsLock 切换验证延迟 120ms → 80ms
- 更名：项目正式更名为 Tail Input

### v1.2.3
- 修复：补全 Apple 简体拼音等中文输入源识别，解决 CapsLock 手动切回中文偶发需要多次点击的问题
- 优化：CapsLock 兼容模式增加快速校验、一次重试与 TIS 兜底
- 优化：缓存最近成功的中英文输入源 ID，减少重复扫描
- 优化：App 切换事件合并窗口 20ms → 8ms

### v1.2.2
- 优化：AppObserver debounce 50ms → 20ms
- 优化：TIS 通知触发后 UI 即时同步
- 优化：状态栏固定宽 28pt，中英图标切换宽度不跳变

### v1.2.1
- 修复：TIS 切换后乐观缓存更新，解决输入法切换严重失效问题
- 修复：`InputMethodManager` / `AppObserver` 继承 `NSObject`

### v1.2.0
- 新增：应用策略管理窗口
- 新增：ConfiguredAppStore 数据持久化与旧配置自动迁移
- 新增：状态栏 SF Symbol 图标

### v1.1.0
- 新增：CapsLock 兼容模式
- 新增：首次运行 Onboarding

### v1.0.0
- 初始发布

---

## 许可证

MIT License — 自由使用、修改、分发。

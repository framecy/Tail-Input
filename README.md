# Tail Input ⌨️

> 按应用自动切换输入法的 macOS 工具 — 轻量、无感知、零配置即用。

**版本：v1.4.0** · macOS 13.0+ · Apple Silicon & Intel · [下载](https://github.com/framecy/Tail-Input/releases)

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

1. 下载 [`Tail-Input-1.4.0.dmg`](https://github.com/framecy/Tail-Input/releases/latest)
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
main.swift                 → 应用入口
AppDelegate.swift          → Dock + 菜单栏 UI，NSMenuDelegate 懒构建，权限重试逻辑
AppObserver.swift          → NSWorkspace 应用激活监听（去重 + 8ms 合并）
InputMethodManager.swift   → TIS 输入法切换（乐观缓存 + modeID 检测）
ConfiguredAppStore.swift   → 应用策略持久化（Codable + 旧格式迁移）
CapsLockInterceptor.swift  → CGEvent tap 拦截 CapsLock（短按 < 300ms 直接切换）
AccessibilityManager.swift → 辅助功能权限轮询（1s 快速 / 5s 节能双档）
MainWindowController.swift → 双栏设置窗口（左侧边栏 + 右侧规则区）
HUDWindowController.swift  → 切换 HUD 弹窗（LiquidGlass 风格，178×66）
WelcomeWindowController.swift → 首次运行引导
```

**核心技术**：TIS (Carbon) · CGEvent tap · NSWorkspace · GCD DispatchWorkItem · ServiceManagement · Codable

---

## 核心模块介绍

### AppObserver — 应用激活感知

监听 `NSWorkspace.didActivateApplicationNotification`，捕获前台应用切换事件。内置去重逻辑：同一个 Bundle ID 连续触发时直接跳过；快速切换（< 8ms）使用 `DispatchWorkItem` 合并为一次回调，降低无效调用开销。

### InputMethodManager — 输入法切换核心

封装 Carbon TIS（Text Input Sources）API，提供三种策略的实际切换：

| 操作 | 机制 |
|---|---|
| 切换为英文 | 扫描并激活 ASCII 输入源 |
| 切换为中文 | 优先从缓存恢复上次中文输入源 |
| modeID 检测 | 兼容鼠须管等输入法的 Roman 子模式（macOS 26 修复） |
| 乐观缓存 | 切换成功后立即写入目标 ID，避免 TIS 异步生效期间读取到旧状态 |

### CapsLockInterceptor — CapsLock 直接切换（v1.4.0）

通过 `CGEvent.tapCreate` 在会话层拦截 `flagsChanged` 事件，识别 keyCode `0x39`（CapsLock 键）：

- **短按（< 300ms）**：直接调用 `InputMethodManager` 切换输入法，无系统延迟
- **长按（≥ 300ms）**：透传原始事件，保留 macOS 原生 Caps Lock 锁定行为
- tap 创建成功即代表 AX 权限有效，绕过 `AXIsProcessTrusted()` 进程内缓存问题

### AccessibilityManager — 权限状态监控（v1.4.0）

后台轮询 `AXIsProcessTrusted()`，监控辅助功能授权状态变化：

- 等待授权期间：**1s** 高频轮询，快速捕获用户授权
- 常态运行：**5s** 低频轮询，减少 CPU 占用
- 状态变更时在主线程回调，供 `AppDelegate` 自动重启拦截器

### ConfiguredAppStore — 策略持久化

以 Bundle ID 为 key，将 `AppInputStrategy` 通过 `Codable` 写入 `UserDefaults`，支持从旧格式（`ConfiguredAppsV1`）自动迁移，保证跨版本升级无感。

### MainWindowController — 双栏设置界面

720×480 无标题栏窗口，左侧边栏包含总开关、全局默认策略、开机自启、版本信息；右侧规则区支持搜索过滤，可从所有已安装应用（含未运行）中搜索并配置策略。

### HUDWindowController — 切换反馈弹窗

无边框悬浮窗口（178×66），常驻 `.floating` 层，切换输入法后短暂显示当前状态（简体中文 / English），0.8s 后淡出。LiquidGlass 风格：18pt 连续圆角 + 顶部反光高亮。

---

## 更新记录

### v1.4.0
- 新增：CapsLock 拦截器（CGEvent tap）— 短按 CapsLock（< 300ms）直接切换输入法，零系统延迟
- 新增：AccessibilityManager 辅助功能权限后台轮询 — 授权后 ≤ 1s 自动恢复拦截器，无需手动重启
- 重构：权限授权流程 — 以 tap 创建结果替代 `AXIsProcessTrusted()` 缓存判断，彻底解决授权后仍返回 false 的问题
- 修复：重启机制改用 `createsNewApplicationInstance = true`，确保新进程真正启动而非激活旧实例
- 修复：代码签名 Bundle Identifier 从 linker-signed 残留 `"Tail Input"` 修正为 `com.framed.TailInput`，消除 TCC 授权条目因 cdhash 变化失效的问题

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

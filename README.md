# Tail Input ⌨️

> 按应用自动切换输入法的 macOS 工具 — 轻量、无感知、零配置即用。

**版本：v1.5.1** · macOS 13.0+ · Apple Silicon & Intel · [下载](https://github.com/framecy/Tail-Input/releases)

---

## 功能

| 功能 | 说明 |
|---|---|
| **按应用自动切换** | 切换 App 时自动切回英文（默认），彻底告别误触中文 |
| **应用规则选择器** | 从所有已安装应用中搜索并配置策略，不局限于当前前台应用 |
| **三种规则** | 切换为英文 / 切换为中文 / 保持不变，按应用独立配置 |
| **窗口 + 菜单栏双模式** | 有 Dock 图标，可 Cmd+Tab 切换；菜单栏图标快速查看状态 |
| **CapsLock 三态切换** | 关闭 / 兼容（短按切换）/ 纯切换（零延迟 + 禁用大写锁定），按需选择 |
| **HUD 提示** | 切换时屏幕角落短暂显示当前输入法，位置 / 大小 / 内容均可自定义 |
| **开机自启动** | 一键注册 / 取消 Launch at Login |

---

## 安装

### DMG（推荐）

1. 下载 [`Tail-Input-1.5.1.dmg`](https://github.com/framecy/Tail-Input/releases/latest)
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

### CapsLock 切换模式

侧边栏 / 菜单栏的「CapsLock 切换」提供三档：

| 模式 | 行为 | 适用场景 |
|---|---|---|
| 关闭 | 不拦截，走系统原生行为 | 不需要 Tail Input 接管 CapsLock |
| 兼容模式 | 短按 < 300ms 触发切换，保留 macOS 原生交互 | 既想用 macOS 系统切换，也想要 Tail Input 的 HUD/规则 |
| 纯切换模式 | 物理按下即切换，零延迟 + IOKit 钳制 LED 不亮 / 大写锁定不生效 | 完全把 CapsLock 重定向为切换键，不想要大写锁定 |

启用任意非「关闭」模式都需要授权辅助功能（**系统设置 → 隐私与安全 → 辅助功能**）。

> ⚠️ **纯切换模式前置要求**
>
> macOS 系统设置 → 键盘 → 输入法 → 编辑… 中的「**使用 ⇪ 大写锁定键切换 ABC 输入源**」必须**关闭**。否则 macOS 和 Tail Input 会同时切换输入法，相互抵消（按一次等于按了两次）。
>
> Tail Input 在首次切换到纯切换模式时会弹窗提醒，并提供「打开系统设置」一键跳转。

---

## 系统要求

| 项目 | 要求 |
|---|---|
| 操作系统 | macOS 13.0 Ventura 及以上 |
| 硬件 | Apple Silicon（M 系列）及 Intel |
| 权限 | 无需辅助功能权限（CapsLock 兼容/纯切换模式除外） |

---

## 技术架构

```
Sources/TailInput/
├── main.swift                 → 应用入口
├── AppDelegate.swift          → Dock + 菜单栏 UI，NSMenuDelegate 懒构建，权限重试逻辑
├── AppObserver.swift          → NSWorkspace 应用激活监听（去重 + 8ms 合并）
├── InputMethodManager.swift   → TIS 输入法切换（乐观缓存 + 代数守卫 + modeID 检测）
├── ConfiguredAppStore.swift   → 应用策略持久化（Codable + 旧格式迁移）
├── CapsLockInterceptor.swift  → CGEvent tap 拦截 CapsLock（三态：关闭/兼容/纯切换）
├── AccessibilityManager.swift → 辅助功能权限轮询（1s 快速 / 5s 节能双档）
├── MainWindowController.swift → 双栏设置窗口（左侧边栏 + 右侧规则区）
├── HUDWindowController.swift  → 切换 HUD 弹窗（位置/大小/内容可配置）
└── WelcomeWindowController.swift → 首次运行引导

Tests/TailInputTests/
├── AppInputStrategyTests.swift
├── ConfiguredAppStoreTests.swift
├── InputMethodIDRecognitionTests.swift
├── InputMethodManagerIntegrationTests.swift
└── InputMethodStateDetectionTests.swift
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
| 乐观缓存 + 代数守卫 | 切换成功后立即写入目标 ID；代数计数器防止旧 re-read 清除新 pending 状态 |

### CapsLockInterceptor — CapsLock 三态切换

通过 `CGEvent.tapCreate` 在会话层拦截 `flagsChanged` 事件，识别 keyCode `0x39`（CapsLock 键），支持三种模式：

| 模式 | 机制 |
|---|---|
| 关闭 | 不拦截，事件透传给系统 |
| 兼容 | 短按（< 300ms）切换输入法；长按保留 macOS 原生大写锁定 |
| 纯切换 | 仅响应 SET 方向事件（避免抖动）；100ms 去抖；IOKit 钳制 LED 不亮 / 大写锁定不生效 |

- 纯切换模式通过 IOHIDSystem 将 `kIOHIDCapsLockState` 强制清零，实现零 LED 反馈
- 首次启用纯切换模式弹窗检测 macOS「⇪ 切换 ABC」冲突，提供一键跳转系统设置
- tap 创建成功即代表 AX 权限有效，绕过 `AXIsProcessTrusted()` 进程内缓存问题

### AccessibilityManager — 权限状态监控

后台轮询 `AXIsProcessTrusted()`，监控辅助功能授权状态变化：

- 等待授权期间：**1s** 高频轮询，快速捕获用户授权
- 常态运行：**5s** 低频轮询，减少 CPU 占用
- 状态变更时在主线程回调，供 `AppDelegate` 自动重启拦截器

### ConfiguredAppStore — 策略持久化

以 Bundle ID 为 key，将 `AppInputStrategy` 通过 `Codable` 写入 `UserDefaults`，支持从旧格式（`ConfiguredAppsV1`）自动迁移，保证跨版本升级无感。

### MainWindowController — 双栏设置界面

无标题栏窗口，左侧边栏包含总开关、全局默认策略、CapsLock 模式选择、HUD 配置、开机自启、版本信息；右侧规则区支持搜索过滤，可从所有已安装应用（含未运行）中搜索并配置策略。

### HUDWindowController — 切换反馈弹窗

无边框悬浮窗口，常驻 `.floating` 层，切换输入法后短暂显示当前状态（简体中文 / English）。支持：
- **9 种位置**（四角 / 四边中点 / 屏幕中央 / 鼠标附近）
- **3 种尺寸**（小 / 中 / 大）
- **图标显示开关**
- **文字样式**（简短：中文/英文 · 完整：简体中文/English）

---

## 更新记录

### v1.5.1
- 修复：CapsLock 纯切换模式死锁 — CGEventTap 回调中同步调用 IOHIDSetModifierLockState 导致 WindowServer 环形死锁，改为异步派发
- 修复：CapsLock 切换失败 — 输入法 helper 进程短暂激活覆盖 CapsLock 切换结果，添加 activationPolicy == .regular 守卫
- 修复：Apple 内置拼音 HUD/状态栏显示为 "EN" — 补齐 scim/tcim 中文检测关键词
- 修复：AppObserver 重新启用时未取消挂起 workItem，可能导致双重触发

### v1.5.0
- 新增：CapsLock 三态切换 — 关闭 / 兼容（短按切换 + 长按保留大写锁定）/ 纯切换（按下即切换 + IOKit 钳制 LED 不亮 + 完全禁用大写锁定），替代原单一兼容开关
- 新增：纯切换模式冲突检测 — 首次启用时弹窗提示 macOS「⇪ 切换 ABC」设置冲突，提供「打开系统设置」一键跳转
- 新增：HUD 位置 / 大小 / 内容全面可配置 — 9 种显示位置，3 种尺寸预设，图标开关，简短/完整文字样式
- 新增：应用选择器 Spotlight 搜索 — 通过 `mdfind` 发现全部已安装 App，覆盖无 Info.plist 应用
- 新增：应用选择器手动选择 — 顶栏「手动选择…」按钮，通过 NSOpenPanel 直接选取任意 .app 文件
- 新增：无 Bundle ID 应用支持 — `path:<绝对路径>` 作为合成标识符，正确应用策略
- 修复：设置窗口所有键盘快捷键失效（Cmd+W/A/C/V/X/Z 等）
- 修复：设置了输入法规则的应用中，纯切换模式单击/连按均无法切换（代数守卫 + pending 清除逻辑重构）
- 修复：UserDefaults 旧版 Bool 键自动迁移至新三态 Int 键
- 重命名：源码目录由 `Sources/SmartInputSwitcher` → `Sources/TailInput`

### v1.4.0
- 新增：CapsLock 拦截器（CGEvent tap）— 短按 CapsLock（< 300ms）直接切换输入法，零系统延迟
- 新增：AccessibilityManager 辅助功能权限后台轮询 — 授权后 ≤ 1s 自动恢复拦截器，无需手动重启
- 重构：权限授权流程 — 以 tap 创建结果替代 `AXIsProcessTrusted()` 缓存判断
- 修复：重启机制改用 `createsNewApplicationInstance = true`
- 修复：Bundle Identifier 从 linker-signed 残留修正为 `com.framed.TailInput`

### v1.3.1
- 重构：设置窗口改为双栏布局 — 左侧边栏 + 右侧内容区
- 新增：点击状态栏图标直接唤起主窗口；右键仍弹出快捷菜单

### v1.3.0
- 新增：应用规则选择器、窗口应用模式、LiquidGlass 设计语言、HUD 升级
- 修复：macOS 26 in-source 模式检测（鼠须管 Roman 子模式）
- 更名：项目正式更名为 Tail Input

### v1.2.x
- 各项性能优化、输入源识别补全、乐观缓存修复

### v1.0.0
- 初始发布

---

## 许可证

MIT License — 自由使用、修改、分发。

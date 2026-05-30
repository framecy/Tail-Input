# Tail Input

> 按应用自动切换输入法的 macOS 工具 — 轻量、无感知、零配置即用。

**版本：v1.6.0** · macOS 13.0+ · Apple Silicon & Intel · [下载](https://github.com/framecy/Tail-Input/releases)

---

## 功能

| 功能 | 说明 |
|---|---|
| **按应用自动切换** | 切换 App 时自动切回英文（默认），彻底告别误触中文 |
| **四种策略** | 切换为英文 / 切换为中文 / 保持不变 / 恢复上次输入源，按应用独立配置 |
| **强制英文标点** | 中文输入法下自动输入 ASCII 标点（`;` `'` `"` `,` `.` `/` `[` `]` 等） |
| **应用规则选择器** | 从所有已安装应用中搜索并配置策略，不局限于当前前台应用 |
| **窗口 + 菜单栏双模式** | 有 Dock 图标，可 Cmd+Tab 切换；菜单栏图标快速查看状态 |
| **CapsLock 三态切换** | 关闭 / 兼容（短按切换）/ 纯切换（零延迟 + IOKit 钳制 LED），按需选择 |
| **HUD 提示** | 切换时屏幕角落短暂显示当前输入法，9 位置 × 3 尺寸 × 可配置文字 |
| **开机自启动** | 一键注册 / 取消 Launch at Login |
| **Helper 后台进程** | 独立 CGEvent tap 进程，崩溃自动恢复，不中断输入法切换 |
| **osascript 授权引导** | 自动打开系统设置隐私面板，1s 快速轮询等待授权 |

---

## 安装

### DMG（推荐）

1. 下载 [`TailInput-1.6.0.dmg`](https://github.com/framecy/Tail-Input/releases/latest)
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
3. 菜单栏图标（中/En）→ 快速为当前前台应用设置规则
4. **开启 App 自动切换** → 总开关，随时暂停

### 输入法规则

| 规则 | 效果 |
|---|---|
| 切换为英文 | 切换到该 App 时自动使用英文输入法 |
| 切换为中文 | 切换到该 App 时自动使用中文输入法 |
| 保持不变 | 不做任何切换，保留上一个 App 的输入法状态 |
| 恢复上次输入源 | 离开前记住输入源，回到该 App 时恢复 |
| 跟随全局（删除规则） | 使用全局默认策略，删除行即可 |

### 强制英文标点

中文输入法下，标点符号自动替换为 ASCII 对应字符。需要**输入监控**权限（系统设置 → 隐私与安全 → 输入监控）。

状态栏菜单中开启「强制英文标点」开关即可。

### CapsLock 切换模式

侧边栏 / 菜单栏的「CapsLock 切换」提供三档：

| 模式 | 行为 | 适用场景 |
|---|---|---|
| 关闭 | 不拦截，走系统原生行为 | 不需要 Tail Input 接管 CapsLock |
| 兼容模式 | 短按 < 300ms 触发切换，保留 macOS 原生交互 | 即想用系统切换，也想要 Tail Input 的 HUD/规则 |
| 纯切换模式 | 物理按下即切换，零延迟 + IOKit 钳制 LED 不亮 | 完全把 CapsLock 重定向为切换键 |

启用任意非「关闭」模式都需要授权辅助功能（**系统设置 → 隐私与安全 → 辅助功能**）。

---

## 系统要求

| 项目 | 要求 |
|---|---|
| 操作系统 | macOS 13.0 Ventura 及以上 |
| 硬件 | Apple Silicon（M 系列）及 Intel |
| 权限 | 辅助功能（CapsLock 切换） · 输入监控（强制英文标点） |

---

## 技术架构

```
Sources/
├── TailInput/
│   ├── main.swift                  → 应用入口
│   ├── AppDelegate.swift           → Dock + 菜单栏 UI，权限重试，Helper 启动
│   ├── AppObserver.swift           → NSWorkspace 应用激活（去重 + 15ms coalesce + bounce-back guard）
│   ├── InputMethodManager.swift    → TIS 输入法切换（乐观缓存 + 代数守卫 + restorePrevious）
│   ├── ConfiguredAppStore.swift    → 策略持久化（Codable + 旧格式迁移）
│   ├── CapsLockInterceptor.swift   → CGEvent tap 拦截 CapsLock（三态，纯异步派发）
│   ├── PunctuationService.swift    → 强制英文标点（TIS 通知驱动缓存，CGEventTap 内 O(1) 读取）
│   ├── AccessibilityManager.swift  → AX 权限轮询（1s / 5s 双档）
│   ├── AppKeyboardCache.swift      → 按应用记忆输入源（O(1) 字典读写）
│   ├── CJKVDetector.swift          → CJKV 广义检测（zh/ko/ja/vi/ru）
│   ├── CJKVFixWindow.swift         → 临时窗口修复 CJKV 输入源切换
│   ├── TCCManager.swift            → osascript 权限引导 + TCC 诊断
│   ├── HelperDaemon.swift          → Helper 进程生命周期管理
│   ├── InputSourceLabel.swift      → 输入法短标签映射（40+ 种）
│   ├── Logger.swift                → 统一日志（os.Logger + NSLog）
│   ├── MainWindowController.swift  → 双栏设置窗口
│   ├── HUDWindowController.swift   → 切换 HUD（GPU 加速动画）
│   └── WelcomeWindowController.swift → 首次运行引导
├── Helper/
│   └── main.swift                  → 后台辅助进程（stdin/stdout IPC）
└── Shared/
    └── IPCProtocol.swift           → 主进程 ↔ Helper 通信协议
```

**核心技术**：TIS (Carbon) · CGEvent tap · IOKit · NSWorkspace · GCD · ServiceManagement · osascript · DistributedNotificationCenter

---

## 更新记录

### v1.6.0
- 新增：强制英文标点 — 中文输入法下自动替换为 ASCII 标点（需输入监控权限）
- 新增：恢复上次输入源策略 — 离开 App 时记住输入源，回来时恢复
- 新增：Helper 后台辅助进程 — 独立 CGEvent tap 进程，崩溃自动重连
- 新增：osascript 权限引导 — TCCManager 自动打开系统设置隐私面板
- 新增：CJKV 广义检测 — 扩展覆盖韩文/日文/越南文/俄文
- 新增：InputSource 短标签 — 40+ 输入法的短名称映射（한/あ/倉/拼/注…）
- 新增：统一日志系统 — TILogger，支持按模块开关
- 新增：11 个性能测试 + 34 个单元测试，总计 162 测试
- 修复：CapsLock 兼容模式死锁 — compat 分支改为异步派发（与 pure 一致）
- 修复：PunctuationService 死锁 — 改为 TIS 通知驱动缓存，CGEventTap 内仅 O(1) 读取
- 优化：AppObserver bounce-back guard（200ms 窗口）+ flatMapLatest coalesce（15ms）
- 优化：HUD 动画使用 animator().alphaValue（GPU 加速）

### v1.5.1
- 修复：CapsLock 纯切换模式死锁 — CGEventTap 回调中同步调用 IOHIDSetModifierLockState 导致 WindowServer 环形死锁，改为异步派发
- 修复：CapsLock 切换失败 — 输入法 helper 进程短暂激活覆盖 CapsLock 切换结果，添加 activationPolicy == .regular 守卫
- 修复：Apple 内置拼音 HUD/状态栏显示为 "EN" — 补齐 scim/tcim 中文检测关键词
- 修复：AppObserver 重新启用时未取消挂起 workItem，可能导致双重触发

### v1.5.0
- 新增：CapsLock 三态切换 — 关闭 / 兼容（短按切换 + 长按保留大写锁定）/ 纯切换（按下即切换 + IOKit 钳制 LED 不亮 + 完全禁用大写锁定）
- 新增：纯切换模式冲突检测 + HUD 全面可配置 + Spotlight 应用搜索 + 手动选择 .app + 无 Bundle ID 应用支持
- 修复：设置窗口键盘快捷键失效 + 纯切换连按无法切换 + UserDefaults 旧版迁移
- 重命名：源码目录 `Sources/SmartInputSwitcher` → `Sources/TailInput`

### v1.4.0
- 新增：CapsLock 拦截器 + AccessibilityManager 后台轮询 + 权限流程重构
- 修复：重启机制 + Bundle Identifier

### v1.3.x
- 双栏布局、应用规则选择器、LiquidGlass 设计、macOS 26 支持

### v1.2.x
- 性能优化、输入源识别补全、乐观缓存修复

### v1.0.0
- 初始发布

---

## 许可证

MIT License — 自由使用、修改、分发。

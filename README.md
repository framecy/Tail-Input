# TailInput ⌨️

> 按应用自动切换输入法的 macOS 菜单栏工具 — 轻量、无感知、零配置即用。

**版本：v1.2.3** · macOS 13.0+ · Apple Silicon & Intel

---

## 功能

| 功能 | 说明 |
|---|---|
| **按应用自动切换** | 切换 App 时自动切回英文（默认），彻底告别误触中文 |
| **逐应用策略** | 为每个 App 单独设定：强制英文 / 强制中文 / 保持原状 |
| **策略管理窗口** | 可视化查看、修改、删除所有已配置 App，一键添加当前 App |
| **CapsLock 兼容模式** | 模拟系统级 CapsLock 事件，保留 macOS 原生 CapsLock 切换能力 |
| **菜单栏状态图标** | SF Symbol 图标随输入法自动变化，固定宽度不抖动 |
| **HUD 提示** | 切换时屏幕右上角短暂显示当前输入法（简体中文 / English） |
| **开机自启动** | 一键注册 / 取消 Launch at Login |

---

## 安装

### DMG（推荐）

1. 下载 `TailInput-1.2.3.dmg`
2. 打开后将 `TailInput.app` 拖入 `Applications`
3. 首次运行在「系统设置 → 隐私与安全 → 辅助功能」授权（仅 CapsLock 模式需要）

### 源码编译

```bash
git clone https://github.com/your-username/TailInput.git
cd TailInput
xcodegen generate
xcodebuild -project TailInput.xcodeproj -scheme TailInput \
  -configuration Release CODE_SIGNING_ALLOWED=NO build
open ~/Library/Developer/Xcode/DerivedData/TailInput*/Build/Products/Release/TailInput.app
```

---

## 使用

1. 启动后图标出现在菜单栏右侧（⌨️ 图标）
2. **点击图标** → 查看当前前台 App，选择输入法策略
3. **管理应用策略…** → 批量查看 / 修改所有已配置 App
4. **开启 App 自动切换** → 总开关，随时暂停
5. **开机自启动** → 一键设置

### 策略说明

| 策略 | 效果 |
|---|---|
| 默认（切回英文） | 切换到该 App 时自动切到英文输入法 |
| 强制英文 | 同上，显式标记 |
| 强制中文 | 切换到该 App 时自动切到中文输入法（适合微信、备忘录等） |
| 保持原状态 | 不做任何切换，保留上一个 App 的输入法状态 |

### CapsLock 兼容模式

macOS 系统设置中开启了「用 CapsLock 切换中英文」但切换 App 后 CapsLock 失效？

1. 菜单栏图标 → 勾选 **CapsLock 兼容模式**
2. 系统弹窗 → 在「系统设置 → 隐私与安全 → 辅助功能」允许 TailInput
3. 再次点击开启

开启后自动切换通过模拟系统 CapsLock 键完成，macOS 状态机保持完整。

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
main.swift                    → 应用入口
AppDelegate.swift             → 菜单栏 UI，NSMenuDelegate 懒构建
AppObserver.swift             → NSWorkspace 应用激活监听（去重 + 50ms 合并）
InputMethodManager.swift      → TIS 输入法切换（乐观缓存 + NSObject + CapsLock 模拟）
ConfiguredAppStore.swift      → 应用策略持久化（Codable + 旧格式迁移）
AppListWindowController.swift → 策略管理窗口（NSTableView）
HUDWindowController.swift     → 切换 HUD 弹窗（SF Symbol + 动画）
WelcomeWindowController.swift → 首次运行引导
```

**核心技术**：TIS (Carbon) · CGEvent · NSWorkspace · GCD DispatchWorkItem · ServiceManagement · Codable

---

## 更新记录

### v1.2.3
- 修复：补全 Apple 简体拼音等中文输入源识别，解决 CapsLock 手动切回中文偶发需要多次点击的问题
- 优化：CapsLock 兼容模式增加快速校验、一次重试与 TIS 兜底，避免系统状态机与本地缓存不同步
- 优化：缓存最近成功的中英文输入源 ID，减少重复扫描输入源列表
- 优化：App 切换事件合并窗口 20ms → 8ms，降低切换感知延迟
- 优化：策略管理窗口缓存应用图标，减少列表刷新开销

### v1.2.2
- 优化：AppObserver debounce 50ms → 20ms，Cmd+Tab 切换响应更快
- 优化：TIS 通知触发后 UI 即时同步（移除冗余 50ms 防抖），感知延迟降至 ~20ms
- 优化：CapsLock 路径补齐乐观缓存更新，切换后图标即时响应无需等待通知回来
- 优化：状态栏固定宽 28pt（原 squareLength 22pt），中英图标切换宽度不再跳变
- 优化：状态栏图标改 medium weight，HUD SF Symbol 改 semibold，深色背景更清晰
- 优化：HUD 淡入动画 0.15s → 0.12s

### v1.2.1
- 修复：TIS 切换后乐观缓存更新，解决输入法切换严重失效问题
- 修复：`InputMethodManager` / `AppObserver` 继承 `NSObject`，确保 ObjC 通知可靠送达
- 更新：App 图标更换为 Apple 系统 emoji ⌨️，深灰渐变背景

### v1.2.0
- 新增：App 更名为 TailInput
- 新增：应用策略管理窗口
- 新增：ConfiguredAppStore 数据持久化与旧配置自动迁移
- 新增：状态栏 SF Symbol 图标，固定宽度不抖动
- 新增：HUD 现代化重设计
- 修复：CapsLock 路径乐观缓存与通知延迟问题

### v1.1.0
- 新增：CapsLock 兼容模式
- 新增：首次运行 Onboarding
- 优化：Rime / 鼠须管输入法识别支持

### v1.0.0
- 初始发布

---

## 许可证

MIT License — 自由使用、修改、分发。

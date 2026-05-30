# Roadmap

## v1.6.0（已完成）

- [x] 强制英文标点（PunctuationService）
- [x] 恢复上次输入源策略（restorePrevious）
- [x] Helper 后台辅助进程（TailInputHelper）
- [x] osascript 权限引导（TCCManager）
- [x] CJKV 广义检测（ko/ja/vi/ru）
- [x] InputSource 短标签映射
- [x] 统一日志系统（TILogger）
- [x] CapsLock 兼容模式死锁修复
- [x] PunctuationService 死锁修复
- [x] AppObserver bounce-back guard + flatMapLatest coalesce

## v1.7.0（规划中）

- [ ] 浏览器 URL 规则 — 按网站域名自动切换输入法（Safari / Chrome / Edge / Firefox）
  - AXSwift 读取浏览器地址栏
  - DOMAIN / DOMAIN-SUFFIX / URL-REGEX 三种匹配
- [ ] 输入法图标显示 — 在菜单栏和 HUD 中显示真实输入法图标（替换 中/En 文字）
- [ ] 自定义快捷键切换 — modifier-only 快捷键（双击 Shift / 双击 Control 等）
- [ ] 按应用 Fn 键控制 — 特定 App 中强制 F1-F12 为标准功能键
- [ ] Helper XPC Service — 从 stdin/stdout 升级为 XPC 通信，更稳定

## v1.8.0（远期）

- [ ] Sparkle 自动更新 — 检查 + 下载 + 安装更新
- [ ] Core Data 迁移 — 从 UserDefaults 升级到 Core Data（规则管理更灵活）
- [ ] 中英文混合输入统计 — 每个 App 的中文/英文输入时长统计
- [ ] 浅色/深色主题 — 跟随系统或手动切换

## 技术债务

- Helper 通信从 stdin/stdout 升级为 XPC（更可靠的重连机制）
- AppKeyboardCache 添加 LRU 淘汰（防止长期运行内存增长）
- HUD 窗口池化（避免每次切换都创建/销毁窗口）

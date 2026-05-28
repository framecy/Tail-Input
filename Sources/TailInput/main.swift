import Cocoa

let app = NSApplication.shared
// .regular：Dock 图标 + Cmd+Tab + 标准菜单栏。
// 标准菜单栏是 macOS 派发 Cmd+W / Cmd+A / Cmd+C / Cmd+V 等系统级快捷键的载体，
// 没有它窗口内的 NSTextField / NSTableView 收不到这些事件。
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

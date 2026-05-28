import Cocoa
import Carbon
import IOKit.hid

/// CapsLock 拦截行为模式
enum CapsLockMode: Int {
    case off    = 0  // 关闭：不拦截，CapsLock 走系统原生行为
    case compat = 1  // 兼容模式：物理抬起后判断时长，< 300ms 视为短按切换
    case pure   = 2  // 纯切换模式：物理按下即切换，IOKit 钳制 LED，完全禁用大写锁定
}

class CapsLockInterceptor {
    static let shared = CapsLockInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// 当前生效的行为模式。.off 时不应启动 tap；.compat / .pure 由 handleEvent 分支处理。
    var mode: CapsLockMode = .compat

    // 物理按下状态。CapsLock 一次完整点击会产生两个 flagsChanged 事件
    private var isKeyDown = false

    // 兼容模式专用：记录按下时刻用于判定短按
    private var keyDownTime: UInt64 = 0
    private let shortPressThresholdNanos: UInt64 = 300_000_000

    // 纯切换模式专用：去重窗口
    // CapsLock 一次物理按下可能产生多个 flagsChanged 事件（DOWN + UP），
    // 加上 IOHIDSetModifierLockState 反向修改状态会再触发一次回响事件，flip-flop
    // 状态机会被打乱。直接用时间窗去重最稳：250ms 内的事件视为同一次按下的派生。
    private var lastPureTriggerNanos: UInt64 = 0
    private let pureDebounceNanos: UInt64 = 250_000_000

    private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    var isRunning: Bool { eventTap != nil }

    /// 直接尝试创建 event tap，**不**前置 AXIsProcessTrusted 检查。
    /// 原因：AXIsProcessTrusted() 在进程内是缓存的——一旦返回 false，即使用户事后授权，
    /// 该进程内继续返回 false 直到重启。而 CGEvent.tapCreate 每次都向内核实时查询 TCC，
    /// 是判断"当前是否真的有权限"的唯一可靠方式。
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: capsLockTapCallback,
            userInfo: selfPtr
        ) else {
            NSLog("[TailInput] CGEvent.tapCreate returned nil — AX permission missing or revoked")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource!, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[TailInput] CapsLock interceptor started (mode=\(mode))")
        return true
    }

    func stop() {
        guard let source = runLoopSource, let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        eventTap = nil
        runLoopSource = nil
        isKeyDown = false
        lastPureTriggerNanos = 0
        NSLog("[TailInput] CapsLock interceptor stopped")
    }

    fileprivate func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 0x39 else {
            return Unmanaged.passUnretained(event)
        }

        // 同时按着其他修饰键时放行，不拦截
        let otherModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        if !event.flags.intersection(otherModifiers).isEmpty {
            isKeyDown = false
            return Unmanaged.passUnretained(event)
        }

        switch mode {
        case .off:
            // 防御性分支：理论上 .off 时不会启动 tap，但若残留则直接放行
            return Unmanaged.passUnretained(event)

        case .pure:
            // 只在 kernel 把 CapsLock 状态转为"已锁定"的事件上触发。
            //
            // 一次物理按下会产生：
            //   1) DOWN 事件：flag SET（kernel 刚把状态转 ON）
            //   2) UP 事件：flag 仍然 SET（kernel 没再翻转，物理松开不改变锁定状态）
            //   3) forceCapsLockOff 反向修改：flag CLEAR（kernel 被我们强制转 OFF）
            //
            // 用 flag 方向去重：只取"刚转 ON"那一类事件 + 时间窗防御同向重复。
            guard event.flags.contains(.maskAlphaShift) else {
                // CLEAR 方向的事件一律吞掉，包括 IOKit 反弹
                return nil
            }

            // 同向（SET）事件也可能在同一次按下里出现两次（DOWN+UP），50ms 窗内只取第一次
            let now = mach_absolute_time()
            let elapsedNanos = (now - lastPureTriggerNanos) * UInt64(Self.timebaseInfo.numer) / UInt64(Self.timebaseInfo.denom)
            if lastPureTriggerNanos != 0 && elapsedNanos < pureDebounceNanos {
                return nil
            }
            lastPureTriggerNanos = now

            // 真实物理按下：切换输入法 + 强制清掉 CapsLock 锁定状态
            InputMethodManager.shared.toggleInputMethod()
            forceCapsLockOff()
            return nil

        case .compat:
            if !isKeyDown {
                isKeyDown = true
                keyDownTime = mach_absolute_time()
            } else {
                isKeyDown = false
                let elapsed = mach_absolute_time() - keyDownTime
                let elapsedNanos = elapsed * UInt64(Self.timebaseInfo.numer) / UInt64(Self.timebaseInfo.denom)
                if elapsedNanos < shortPressThresholdNanos {
                    InputMethodManager.shared.toggleInputMethod()
                }
            }
            return nil
        }
    }

    // 通过 IOKit 将 CapsLock 状态钳制为 OFF，使 LED 不亮且大写锁定不生效。
    // 优先尝试 IOHIDSystem 统一接口（全键盘通用），失败再回退到 Apple 内置驱动。
    private func forceCapsLockOff() {
        if applyCapsLockOff(serviceClass: "IOHIDSystem") { return }
        _ = applyCapsLockOff(serviceClass: "AppleHIDKeyboardEventDriverV2")
    }

    @discardableResult
    private func applyCapsLockOff(serviceClass: String) -> Bool {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(serviceClass),
            &iterator
        ) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }

        var succeeded = false
        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            var connect: io_connect_t = IO_OBJECT_NULL
            // kIOHIDParamConnectType = 1
            if IOServiceOpen(service, mach_task_self_, 1, &connect) == KERN_SUCCESS {
                // kIOHIDCapsLockState = 0
                if IOHIDSetModifierLockState(connect, 0, false) == KERN_SUCCESS {
                    succeeded = true
                }
                IOServiceClose(connect)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return succeeded
    }
}

private func capsLockTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let interceptor = Unmanaged<CapsLockInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
    return interceptor.handleEvent(proxy: proxy, type: type, event: event)
}

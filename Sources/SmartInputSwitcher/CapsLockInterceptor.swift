import Cocoa
import Carbon

class CapsLockInterceptor {
    static let shared = CapsLockInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var isCapsLockDown = false
    private var capsLockDownTime: UInt64 = 0

    // 短按 < 300ms → 切换输入法；长按 ≥ 300ms → 不处理（或可扩展为 Caps Lock）
    private let shortPressThresholdNanos: UInt64 = 300_000_000

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
        NSLog("[TailInput] CapsLock interceptor started")
        return true
    }

    func stop() {
        guard let source = runLoopSource, let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        eventTap = nil
        runLoopSource = nil
        isCapsLockDown = false
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
            isCapsLockDown = false
            return Unmanaged.passUnretained(event)
        }

        if !isCapsLockDown {
            isCapsLockDown = true
            capsLockDownTime = mach_absolute_time()
            return nil
        } else {
            isCapsLockDown = false
            let elapsed = mach_absolute_time() - capsLockDownTime
            let elapsedNanos = elapsed * UInt64(Self.timebaseInfo.numer) / UInt64(Self.timebaseInfo.denom)

            if elapsedNanos < shortPressThresholdNanos {
                InputMethodManager.shared.toggleInputMethod()
            }
            return nil
        }
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

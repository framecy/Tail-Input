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
            if !isKeyDown {
                isKeyDown = true
                // 物理按下即切换，无延迟
                InputMethodManager.shared.toggleInputMethod()
                // 钳制系统 CapsLock 状态防止 LED 亮 / 大写锁定生效
                forceCapsLockOff()
            } else {
                isKeyDown = false
            }
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

    // 通过 IOKit 将 CapsLock 状态钳制为 OFF，使 LED 不亮且大写锁定不生效
    private func forceCapsLockOff() {
        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleHIDKeyboardEventDriverV2"),
            &iterator
        ) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            var connect: io_connect_t = IO_OBJECT_NULL
            // kIOHIDParamConnectType = 1
            if IOServiceOpen(service, mach_task_self_, 1, &connect) == KERN_SUCCESS {
                // kIOHIDCapsLockState = 0
                IOHIDSetModifierLockState(connect, 0, false)
                IOServiceClose(connect)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
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

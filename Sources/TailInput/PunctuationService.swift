import Cocoa
import Carbon

final class PunctuationService {
    private let logger = TILogger(category: "PunctuationService")
    private var isEnabled = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var cachedInputSourceID: String?
    private var cachedIsCJKV: Bool = false
    private var cacheTimestamp: TimeInterval = 0
    private let cacheTimeout: TimeInterval = 0.5

    private let punctuationMap: [UInt16: (normal: String?, shifted: String?)] = [
        UInt16(kVK_ANSI_Grave):        ("`", "~"),
        UInt16(kVK_ANSI_Minus):        ("-", "_"),
        UInt16(kVK_ANSI_Equal):        ("=", "+"),
        UInt16(kVK_ANSI_LeftBracket):  ("[", "{"),
        UInt16(kVK_ANSI_RightBracket): ("]", "}"),
        UInt16(kVK_ANSI_Backslash):    ("\\", "|"),
        UInt16(kVK_ANSI_Semicolon):    (";", ":"),
        UInt16(kVK_ANSI_Quote):        ("'", "\""),
        UInt16(kVK_ANSI_Comma):        (",", "<"),
        UInt16(kVK_ANSI_Period):       (".", ">"),
        UInt16(kVK_ANSI_Slash):        ("/", "?"),
        UInt16(kVK_ANSI_0):            (nil, ")"),
        UInt16(kVK_ANSI_1):            (nil, "!"),
        UInt16(kVK_ANSI_2):            (nil, "@"),
        UInt16(kVK_ANSI_3):            (nil, "#"),
        UInt16(kVK_ANSI_4):            (nil, "$"),
        UInt16(kVK_ANSI_5):            (nil, "%"),
        UInt16(kVK_ANSI_6):            (nil, "^"),
        UInt16(kVK_ANSI_7):            (nil, "&"),
        UInt16(kVK_ANSI_8):            (nil, "*"),
        UInt16(kVK_ANSI_9):            (nil, "("),
    ]

    deinit {
        stopSync()
    }

    private func stopSync() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        isEnabled = false
    }

    func start() -> Bool {
        guard !isEnabled else { return true }
        logger.debug("starting punctuation service")

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: punctuationTapCallback,
            userInfo: selfPtr
        ) else {
            logger.warn("failed to create event tap - Input Monitoring permission missing")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource!, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isEnabled = true
        logger.info("punctuation service started")
        return true
    }

    func stop() {
        stopSync()
        cachedInputSourceID = nil
        cacheTimestamp = 0
        logger.info("punctuation service stopped")
    }

    fileprivate func handleKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled, type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let mapping = punctuationMap[UInt16(keyCode)] else {
            return Unmanaged.passUnretained(event)
        }

        let ignoreFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        if !event.flags.intersection(ignoreFlags).isEmpty {
            return Unmanaged.passUnretained(event)
        }

        let shifted = event.flags.contains(.maskShift)
        guard let replacement = shifted ? (mapping.shifted ?? mapping.normal) : mapping.normal else {
            return Unmanaged.passUnretained(event)
        }

        guard isCurrentInputSourceCJKV() else {
            return Unmanaged.passUnretained(event)
        }

        guard let newEvent = createReplacementEvent(originalEvent: event, replacement: replacement) else {
            return Unmanaged.passUnretained(event)
        }

        logger.debug("replaced keyCode \(keyCode) with '\(replacement)'")
        return Unmanaged.passRetained(newEvent)
    }

    private func createReplacementEvent(originalEvent: CGEvent, replacement: String) -> CGEvent? {
        let keyCode = CGKeyCode(originalEvent.getIntegerValueField(.keyboardEventKeycode))
        guard let source = CGEventSource(stateID: .privateState),
              let newEvent = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        else { return nil }

        newEvent.keyboardSetUnicodeString(
            stringLength: replacement.utf16.count,
            unicodeString: Array(replacement.utf16)
        )
        newEvent.timestamp = originalEvent.timestamp
        newEvent.flags = []
        return newEvent
    }

    private func isCurrentInputSourceCJKV() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if cachedInputSourceID != nil && now - cacheTimestamp < cacheTimeout {
            return cachedIsCJKV
        }

        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }

        let id: String? = {
            guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }()

        cachedInputSourceID = id
        cacheTimestamp = now

        let lower = id?.lowercased() ?? ""
        cachedIsCJKV = CJKVDetector.isCJKV(sourceID: lower)

        if !cachedIsCJKV, let modePtr = TISGetInputSourceProperty(src, kTISPropertyInputModeID) {
            let modeID = Unmanaged<CFString>.fromOpaque(modePtr).takeUnretainedValue() as String
            cachedIsCJKV = CJKVDetector.isCJKV(sourceID: modeID.lowercased())
        }

        return cachedIsCJKV
    }
}

private func punctuationTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let service = Unmanaged<PunctuationService>.fromOpaque(userInfo).takeUnretainedValue()
    return service.handleKeyEvent(proxy: proxy, type: type, event: event)
}

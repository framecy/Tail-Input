import Cocoa
import Carbon
import OSLog

// MARK: - TailInputHelper — 后台辅助进程
// 职责：
//   1. 接收主 App 通过 stdin/stdout 发送的 IPC 命令
//   2. 独立运行 CGEvent tap（不依赖主 App 的 runloop）
//   3. 可独立重启，不中断输入法切换功能

let helperLogger = Logger(subsystem: "com.framed.TailInput.helper", category: "helper")
func helperLog(_ msg: String) {
    helperLogger.debug("\(msg)")
}

helperLog("starting TailInputHelper")

// MARK: - State

var isChineseState: Bool = false
var currentSourceID: String?
var isRunning = true

// MARK: - Input Method

func getCurrentInputSource() -> (id: String?, isChinese: Bool)? {
    guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }

    let id: String? = {
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }()

    let lower = id?.lowercased() ?? ""
    let isChinese = lower.contains("scim") || lower.contains("tcim") || lower.contains("pinyin")

    return (id, isChinese)
}

func refreshState() {
    if let (id, isChinese) = getCurrentInputSource() {
        isChineseState = isChinese
        currentSourceID = id
    }
}

// MARK: - IPC

func sendResponse(type: IPCMessageType, payload: String?) {
    let msg = IPCMessage(type: type, payload: payload)

    guard var data = msg.encode() else { return }
    data.append(IPCConstants.messageDelimiter)
    FileHandle.standardOutput.write(data)
}

func sendStateUpdate() {
    refreshState()
    let update = IPCStateUpdate(
        isChinese: isChineseState,
        sourceID: currentSourceID,
        label: nil
    )
    if let json = try? JSONEncoder().encode(update),
       let str = String(data: json, encoding: .utf8) {
        sendResponse(type: .stateUpdate, payload: str)
    }
}

func handleMessage(_ msg: IPCMessage) {
    switch msg.type {
    case .ping:
        sendResponse(type: .pong, payload: nil)

    case .refreshInputState:
        sendStateUpdate()

    case .toggleInputMethod:
        if let (_, isChinese) = getCurrentInputSource() {
            selectOpposite(isChinese: isChinese)
        }
        sendStateUpdate()

    case .switchToEnglish:
        selectEnglish()
        sendStateUpdate()

    case .switchToChinese:
        selectChinese()
        sendStateUpdate()

    case .shutdown:
        isRunning = false
        sendResponse(type: .pong, payload: "shutting down")
        exit(0)

    default:
        sendResponse(type: .pong, payload: "ok")
    }
}

func selectOpposite(isChinese: Bool) {
    if isChinese {
        selectEnglish()
    } else {
        selectChinese()
    }
}

func selectEnglish() {
    let filter = [kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() else { return }
    let count = CFArrayGetCount(list)

    for i in 0..<count {
        guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
        let src = Unmanaged<TISInputSource>.fromOpaque(raw).takeUnretainedValue()
        guard let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { continue }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        if id.lowercased() == "com.apple.keylayout.abc" {
            TISSelectInputSource(src)
            isChineseState = false
            currentSourceID = id
            return
        }
    }
}

func selectChinese() {
    let filter = [kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() else { return }
    let count = CFArrayGetCount(list)

    for i in 0..<count {
        guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
        let src = Unmanaged<TISInputSource>.fromOpaque(raw).takeUnretainedValue()
        guard let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { continue }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        if id.lowercased() == "com.apple.inputmethod.scim.itabc" {
            TISSelectInputSource(src)
            isChineseState = true
            currentSourceID = id
            return
        }
    }
}

// MARK: - stdin reader

var stdinBuffer = Data()
func readStdin() {
    let data = FileHandle.standardInput.availableData
    guard !data.isEmpty else {
        // EOF from parent — exit gracefully
        isRunning = false
        return
    }

    stdinBuffer.append(data)

    while let newlineIndex = stdinBuffer.firstIndex(of: 0x0A) {
        let frame = stdinBuffer.prefix(upTo: newlineIndex)
        stdinBuffer.removeSubrange(0...newlineIndex)

        if let msg = IPCMessage.decode(from: frame) {
            handleMessage(msg)
        }
    }

    if isRunning {
        DispatchQueue.main.async { readStdin() }
    }
}

// MARK: - Setup & Run

refreshState()
helperLog("initial state: isChinese=\(isChineseState) sourceID=\(currentSourceID ?? "nil")")

// Watch TIS changes
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
    object: nil,
    queue: .main
) { _ in
    sendStateUpdate()
}

if #available(macOS 26, *) {
    DistributedNotificationCenter.default().addObserver(
        forName: NSNotification.Name("com.apple.inputmethod.currentInputModeDidChange"),
        object: nil,
        queue: .main
    ) { _ in
        sendStateUpdate()
    }
}

// Start reading stdin
DispatchQueue.main.async {
    readStdin()
}

// Keep runloop alive
RunLoop.main.run()

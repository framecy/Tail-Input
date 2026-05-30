import Cocoa

final class HelperDaemon {
    static let shared = HelperDaemon()
    private let logger = TILogger(category: "HelperDaemon")

    private var helperProcess: Process?
    private var helperPID: Int32 = 0
    private var connection: FileHandle?
    private var readBuffer = Data()
    private var reconnectTimer: Timer?
    private var isConnecting = false

    var isRunning: Bool { helperProcess?.isRunning ?? false }

    // MARK: - Lifecycle

    func launch() {
        guard helperProcess == nil else {
            logger.debug("helper already running")
            return
        }

        guard let helperURL = findHelperExecutable() else {
            logger.warn("helper executable not found in bundle")
            return
        }

        let process = Process()
        process.executableURL = helperURL
        process.arguments = []

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            helperProcess = process
            helperPID = process.processIdentifier
            logger.info("helper launched pid=\(helperPID)")

            // Read responses from stdout
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self?.handleHelperOutput(data)
            }

            process.terminationHandler = { [weak self] proc in
                let status = proc.terminationStatus
                let reason = proc.terminationReason
                self?.logger.warn("helper exited status=\(status) reason=\(reason.rawValue)")
                self?.helperProcess = nil
                self?.helperPID = 0
                self?.connection = nil

                if reason == .uncaughtSignal || status != 0 {
                    self?.scheduleReconnect(after: 3.0)
                }
            }

            // Send initial connection
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.sendCommand(.ping, payload: nil)
            }
        } catch {
            logger.error("failed to launch helper: \(error.localizedDescription)")
        }
    }

    func shutdown() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        sendCommand(.shutdown, payload: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if self?.helperProcess?.isRunning == true {
                self?.helperProcess?.terminate()
            }
        }
        helperProcess = nil
        helperPID = 0
        connection = nil
    }

    // MARK: - Commands

    func commandStartPunctuationService() {
        sendCommand(.startPunctuationService, payload: nil)
    }

    func commandStopPunctuationService() {
        sendCommand(.stopPunctuationService, payload: nil)
    }

    func commandStartCapsLockService() {
        sendCommand(.startCapsLockService, payload: nil)
    }

    func commandStopCapsLockService() {
        sendCommand(.stopCapsLockService, payload: nil)
    }

    func commandToggleInputMethod() {
        sendCommand(.toggleInputMethod, payload: nil)
    }

    func commandRefreshInputState() {
        sendCommand(.refreshInputState, payload: nil)
    }

    // MARK: - Internal

    private func findHelperExecutable() -> URL? {
        // In-bundle helper: Tail Input.app/Contents/MacOS/TailInputHelper
        let helperPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("TailInputHelper")
        if FileManager.default.isExecutableFile(atPath: helperPath.path) {
            return helperPath
        }

        // Debug: look in build products
        let debugHelper = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("TailInputHelper")
        if FileManager.default.isExecutableFile(atPath: debugHelper.path) {
            return debugHelper
        }

        return nil
    }

    private func sendCommand(_ type: IPCMessageType, payload: String?) {
        let msg = IPCMessage(type: type, payload: payload)
        guard let data = msg.encode() else { return }

        var frame = data
        frame.append(IPCConstants.messageDelimiter)

        connection?.write(frame)
        logger.debug("sent: \(type.rawValue)")
    }

    private func handleHelperOutput(_ data: Data) {
        readBuffer.append(data)

        while let newlineIndex = readBuffer.firstIndex(of: 0x0A) {
            let frame = readBuffer.prefix(upTo: newlineIndex)
            readBuffer.removeSubrange(0...newlineIndex)

            guard let msg = IPCMessage.decode(from: frame) else { continue }

            switch msg.type {
            case .pong:
                logger.debug("helper heartbeat OK")
            case .stateUpdate:
                if let payload = msg.payload,
                   let data = payload.data(using: .utf8),
                   let update = try? JSONDecoder().decode(IPCStateUpdate.self, from: data) {
                    DispatchQueue.main.async {
                        InputMethodManager.shared.cachedIsChinese = update.isChinese
                        InputMethodManager.shared.onInputStateRefreshed?(update.isChinese)
                    }
                }
            case .error:
                logger.warn("helper error: \(msg.payload ?? "unknown")")
            default:
                break
            }
        }
    }

    private func scheduleReconnect(after seconds: TimeInterval) {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.launch()
        }
    }
}

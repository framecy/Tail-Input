import Cocoa
import Carbon

final class CJKVFixWindow {
    private static let logger = TILogger(category: "CJKVFixWindow")
    private static var temporaryWindow: NSWindow?
    private static var previousApplication: NSRunningApplication?
    private static let windowDuration: TimeInterval = 0.08
    private static let activationSuppressDuration: TimeInterval = 0.5
    private static var activationSuppressEndTime: TimeInterval = 0
    static var isShowingTemporaryWindow = false

    static var isHandlingActivation: Bool {
        isShowingTemporaryWindow ||
            ProcessInfo.processInfo.systemUptime < activationSuppressEndTime
    }

    static func isTemporaryWindowActivation(_ app: NSRunningApplication) -> Bool {
        guard isHandlingActivation else { return false }
        return app.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    static func show() {
        close(restorePrevious: false)
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        previousApplication = NSWorkspace.shared.frontmostApplication

        let windowSize = NSSize(width: 3, height: 3)
        let screenRect = screen.visibleFrame
        let contentRect = NSRect(
            x: screenRect.maxX - windowSize.width - 8,
            y: screenRect.minY + 8,
            width: windowSize.width,
            height: windowSize.height
        )

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let textView = NSTextView(frame: NSRect(origin: .zero, size: windowSize))
        window.contentView = textView
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.01
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        temporaryWindow = window
        suppressActivation()
        isShowingTemporaryWindow = true

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(textView)

        DispatchQueue.main.asyncAfter(deadline: .now() + windowDuration) {
            close(restorePrevious: true)
        }

        logger.debug("temporary window shown")
    }

    static func close(restorePrevious: Bool) {
        guard let window = temporaryWindow else {
            isShowingTemporaryWindow = false
            previousApplication = nil
            return
        }

        temporaryWindow = nil
        window.orderOut(nil)
        window.close()
        suppressActivation()
        isShowingTemporaryWindow = false

        if restorePrevious,
           let prev = previousApplication,
           prev.bundleIdentifier != Bundle.main.bundleIdentifier,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
            prev.activate(options: [])
        }
        previousApplication = nil
    }

    private static func suppressActivation() {
        activationSuppressEndTime = ProcessInfo.processInfo.systemUptime + activationSuppressDuration
    }
}

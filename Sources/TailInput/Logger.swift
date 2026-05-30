import Foundation
import os.log

enum LogLevel: Int {
    case debug = 0
    case info  = 1
    case warn  = 2
    case error = 3

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info:  return "ℹ️"
        case .warn:  return "⚠️"
        case .error: return "❌"
        }
    }
}

final class TILogger {
    let category: String
    var isEnabled: Bool

    private static var enabledCategories: Set<String> = []
    private static let lock = NSLock()

    init(category: String, enabled: Bool = true) {
        self.category = category
        self.isEnabled = enabled
    }

    static func enableCategory(_ category: String) {
        lock.lock(); defer { lock.unlock() }
        enabledCategories.insert(category)
    }

    static func disableCategory(_ category: String) {
        lock.lock(); defer { lock.unlock() }
        enabledCategories.remove(category)
    }

    func log(_ level: LogLevel, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let msg = message()
        if #available(macOS 11.0, *) {
            let osLogger = os.Logger(subsystem: "com.framed.TailInput", category: category)
            switch level {
            case .debug: osLogger.debug("\(msg)")
            case .info:  osLogger.info("\(msg)")
            case .warn:  osLogger.warning("\(msg)")
            case .error: osLogger.error("\(msg)")
            }
        } else {
            NSLog("[TailInput][%@] %@%@", category, level.emoji, msg)
        }
    }

    func debug(_ message: @autoclosure () -> String) { log(.debug, message()) }
    func info(_ message: @autoclosure () -> String)  { log(.info, message()) }
    func warn(_ message: @autoclosure () -> String)  { log(.warn, message()) }
    func error(_ message: @autoclosure () -> String) { log(.error, message()) }
}

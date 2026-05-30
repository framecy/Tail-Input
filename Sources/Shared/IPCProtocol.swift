import Foundation

enum IPCMessageType: String, Codable {
    case ping
    case pong
    case startPunctuationService
    case stopPunctuationService
    case startCapsLockService
    case stopCapsLockService
    case toggleInputMethod
    case switchToEnglish
    case switchToChinese
    case refreshInputState
    case stateUpdate
    case shutdown
    case error
}

struct IPCMessage: Codable {
    let type: IPCMessageType
    let payload: String?

    init(type: IPCMessageType, payload: String? = nil) {
        self.type = type
        self.payload = payload
    }

    func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(from data: Data) -> IPCMessage? {
        try? JSONDecoder().decode(IPCMessage.self, from: data)
    }
}

struct IPCStateUpdate: Codable {
    let isChinese: Bool
    let sourceID: String?
    let label: String?
}

enum IPCConstants {
    static let socketPath = "/tmp/com.framed.TailInput.helper.sock"
    static let helperBundleName = "TailInputHelper"
    static let messageDelimiter = Data([0x0A]) // newline-delimited JSON
}

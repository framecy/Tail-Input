import Foundation

final class AppKeyboardCache {
    private var storage: [String: String] = [:]
    private let logger = TILogger(category: "AppKeyboardCache")

    func save(bundleID: String, sourceID: String) {
        logger.debug("save \(bundleID) \(sourceID)")
        storage[bundleID] = sourceID
    }

    func retrieve(bundleID: String) -> String? {
        guard let sourceID = storage[bundleID] else { return nil }
        logger.debug("retrieve \(bundleID) \(sourceID)")
        return sourceID
    }

    func remove(bundleID: String) {
        logger.debug("remove \(bundleID)")
        storage.removeValue(forKey: bundleID)
    }

    func removeAll() {
        logger.debug("remove all \(storage.count) entries")
        storage.removeAll()
    }

    var count: Int { storage.count }
}

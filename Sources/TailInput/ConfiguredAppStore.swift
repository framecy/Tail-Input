import Foundation

final class ConfiguredAppStore {
    static let shared = ConfiguredAppStore()

    private let storeKey    = "ConfiguredAppsV2"
    private let migratedKey = "ConfiguredAppsV2_migrated"
    private var apps: [String: ConfiguredApp] = [:]

    init() {
        migrateFromLegacyIfNeeded()
        load()
    }

    // MARK: - Public API

    /// 所有已配置应用（过滤掉 globalDefault，按名称排序）
    func all() -> [ConfiguredApp] {
        apps.values
            .filter { $0.strategy != .globalDefault }
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    func strategy(for bundleId: String) -> AppInputStrategy {
        apps[bundleId]?.strategy ?? .globalDefault
    }

    func setStrategy(_ strategy: AppInputStrategy, for bundleId: String, appName: String) {
        if strategy == .globalDefault {
            apps.removeValue(forKey: bundleId)
        } else {
            apps[bundleId] = ConfiguredApp(bundleId: bundleId, appName: appName, strategy: strategy)
        }
        save()
    }

    func remove(bundleId: String) {
        apps.removeValue(forKey: bundleId)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([String: ConfiguredApp].self, from: data) else {
            return
        }
        apps = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }

    // MARK: - Legacy Migration

    /// 一次性从旧 "AppStrategy_<bundleId>" UserDefaults 迁移到新格式
    private func migrateFromLegacyIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: migratedKey) }

        let prefix = "AppStrategy_"
        let allKeys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        guard !allKeys.isEmpty else { return }

        var migrated: [String: ConfiguredApp] = [:]
        for key in allKeys {
            let bundleId = String(key.dropFirst(prefix.count))
            let rawValue = UserDefaults.standard.integer(forKey: key)
            let strategy = AppInputStrategy(rawValue: rawValue) ?? .globalDefault
            if strategy != .globalDefault {
                migrated[bundleId] = ConfiguredApp(
                    bundleId: bundleId,
                    appName: bundleId,   // 旧格式未存应用名，以 bundleId 占位
                    strategy: strategy
                )
            }
        }

        if !migrated.isEmpty {
            apps = migrated
            save()
        }
    }
}

// MARK: - ConfiguredApp model（定义在此以保持文件内聚）

struct ConfiguredApp: Codable {
    let bundleId: String
    var appName: String
    var strategy: AppInputStrategy
}

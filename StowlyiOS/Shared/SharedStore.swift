import Foundation
import Security

/// Small key/value storage that both the app and the share extension can read: the paired topic
/// and the sent log. Backed by a shared keychain access group rather than an App Group, because
/// App Groups need a paid developer account while keychain sharing works on a free one.
enum SharedStore {
    private static let service = "com.suyash.stowly"

    /// `<TeamID>.com.suyash.stowly.shared`. The team prefix comes from Info.plist
    /// (`AppIdentifierPrefix = $(AppIdentifierPrefix)`); nil when the build isn't signed with a team.
    private static let accessGroup: String? = {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !prefix.isEmpty, !prefix.hasPrefix("$(") else { return nil }
        return prefix + "com.suyash.stowly.shared"
    }()

    static func data(for key: String) -> Data? {
        var query = baseQuery(key, group: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecMissingEntitlement {
            query[kSecAttrAccessGroup as String] = nil
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }
        return status == errSecSuccess ? result as? Data : nil
    }

    /// Store `data` under `key`; nil deletes it.
    static func set(_ data: Data?, for key: String) {
        if write(data, key: key, group: accessGroup) == errSecMissingEntitlement {
            // Unsigned simulator builds have no access group entitlement; fall back to the default.
            write(data, key: key, group: nil)
        }
    }

    static func string(for key: String) -> String? {
        data(for: key).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func set(_ string: String?, for key: String) {
        set(string.map { Data($0.utf8) }, for: key)
    }

    @discardableResult
    private static func write(_ data: Data?, key: String, group: String?) -> OSStatus {
        let query = baseQuery(key, group: group)
        guard let data else { return SecItemDelete(query as CFDictionary) }

        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return status }

        var add = query
        add[kSecValueData as String] = data
        // Readable by the share extension whenever the phone has been unlocked since boot.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil)
    }

    private static func baseQuery(_ key: String, group: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }
}

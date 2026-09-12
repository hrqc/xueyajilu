import Foundation
#if canImport(CryptoKit) && canImport(Security)
import CryptoKit
import Security
#endif

public enum LocalEncryptionError: Error { case unavailable; case keychainFailure(Int32); case invalidPayload }

public struct LocalEncryptionService: Sendable {
    private let keyTag = "com.example.bphealth.local-data-key"
    public init() {}
    public func encrypt(_ data: Data) throws -> Data {
        #if canImport(CryptoKit) && canImport(Security)
        let sealed = try AES.GCM.seal(data, using: try key())
        guard let combined = sealed.combined else { throw LocalEncryptionError.invalidPayload }
        return combined
        #else
        throw LocalEncryptionError.unavailable
        #endif
    }
    public func decrypt(_ data: Data) throws -> Data {
        #if canImport(CryptoKit) && canImport(Security)
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: try key())
        #else
        throw LocalEncryptionError.unavailable
        #endif
    }
    #if canImport(CryptoKit) && canImport(Security)
    private func key() throws -> SymmetricKey {
        let readQuery: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: keyTag, kSecReturnData as String: true]
        var query = readQuery
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound else { throw LocalEncryptionError.keychainFailure(Int32(status)) }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        query = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: keyTag, kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let saveStatus = SecItemAdd(query as CFDictionary, nil)
        if saveStatus == errSecSuccess { return key }
        if saveStatus == errSecDuplicateItem {
            var existing: CFTypeRef?
            let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &existing)
            guard readStatus == errSecSuccess, let existingData = existing as? Data else { throw LocalEncryptionError.keychainFailure(Int32(readStatus)) }
            return SymmetricKey(data: existingData)
        }
        throw LocalEncryptionError.keychainFailure(Int32(saveStatus))
    }
    #endif
}

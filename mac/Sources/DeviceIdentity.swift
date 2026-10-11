import Foundation
import Security

/// A device-local, persistent credential for the SlapBattle relay.
///
/// The default service/account pair is fixed for the production app. Callers may
/// inject a different pair for isolated verification; no shared access group or
/// synchronizable item is used. Production Keychain access depends on a stable
/// signed/notarized app identity: unsigned builds can trigger Keychain prompts or
/// access denial because macOS cannot reliably identify the requesting binary.
public struct DeviceIdentity {
  public static let service = "Kelvanic SlapBattle v1"
  public static let account = "device-credential"

  private let service: String
  private let account: String

  public init(service: String = DeviceIdentity.service, account: String = DeviceIdentity.account) {
    self.service = service
    self.account = account
  }

  /// Returns the stable 32-byte random credential as 64 lowercase hexadecimal characters.
  /// Existing malformed Keychain data is an error; it is never silently replaced.
  public func loadOrCreateToken() throws -> String {
    let lookup = lookupQuery
    var result: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &result)
    if status == errSecSuccess {
      guard let data = result as? Data,
            let token = String(data: data, encoding: .utf8),
            Self.isCredential(token) else {
        throw DeviceIdentityError.malformedCredential
      }
      return token
    }
    guard status == errSecItemNotFound else {
      throw DeviceIdentityError.keychain(status)
    }

    var bytes = [UInt8](repeating: 0, count: 32)
    let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard randomStatus == errSecSuccess else {
      throw DeviceIdentityError.randomGeneration(randomStatus)
    }
    let token = bytes.map { String(format: "%02x", $0) }.joined()
    let data = Data(token.utf8)

    var item = query
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(item as CFDictionary, nil)
    if addStatus == errSecSuccess { return token }
    if addStatus == errSecDuplicateItem {
      // Another process may have won the creation race. Return its exact credential.
      var winner: CFTypeRef?
      let winnerStatus = SecItemCopyMatching(lookupQuery as CFDictionary, &winner)
      guard winnerStatus == errSecSuccess else {
        throw DeviceIdentityError.keychain(winnerStatus)
      }
      guard let data = winner as? Data,
            let winnerToken = String(data: data, encoding: .utf8),
            Self.isCredential(winnerToken) else {
        throw DeviceIdentityError.malformedCredential
      }
      return winnerToken
    }
    throw DeviceIdentityError.keychain(addStatus)
  }

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any
    ]
  }

  private var lookupQuery: [String: Any] {
    var lookup = query
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    return lookup
  }

  private static func isCredential(_ value: String) -> Bool {
    guard value.utf8.count == 64 else { return false }
    return value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}

public enum DeviceIdentityError: LocalizedError {
  case keychain(OSStatus)
  case randomGeneration(OSStatus)
  case malformedCredential

  public var errorDescription: String? {
    switch self {
    case .keychain(let status):
      return "Could not access the SlapBattle device identity in Keychain (error \(status)). Use a stable signed and notarized app build, then try again."
    case .randomGeneration(let status):
      return "Could not generate a secure SlapBattle device identity (error \(status))."
    case .malformedCredential:
      return "The SlapBattle device identity stored in Keychain is malformed and was not replaced."
    }
  }
}

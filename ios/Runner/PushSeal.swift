import CryptoKit
import Foundation

/// The secret shared by this phone and its home nodes for push messages, and
/// the format of a sealed message. Compiled into the application, which
/// creates the key, and into the notification extension, which uses it.
///
/// A push carries, in the field "rs", the base64 of a ChaCha20-Poly1305 box
/// (12-byte nonce, ciphertext, 16-byte tag). The clear text is a JSON object:
///   title   what the notification is about: a lobby name, "Message", ...
///   from    who wrote it (optional)
///   text    the text to show
///   thread  an identifier grouping notifications, e.g. the lobby id (optional)
enum PushSeal {
  static let appGroup = "group.cc.retroshare.retroshare"
  static let payloadField = "rs"
  private static let keyName = "pushKey"
  private static let tokenName = "pushToken"

  struct Message: Decodable {
    let title: String
    let from: String?
    let text: String
    let thread: String?
  }

  private static var store: UserDefaults? { UserDefaults(suiteName: appGroup) }

  /// The key, created at the first call.
  static func key() -> Data? {
    guard let store = store else { return nil }
    if let key = store.data(forKey: keyName), key.count == 32 { return key }
    let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    store.set(key, forKey: keyName)
    return key
  }

  /// The address Apple gave this installation for pushes, once known.
  static var deviceToken: String? {
    get { store?.string(forKey: tokenName) }
    set { store?.set(newValue, forKey: tokenName) }
  }

  static func open(_ sealedBase64: String) -> Message? {
    guard let store = store,
      let key = store.data(forKey: keyName),
      let sealed = Data(base64Encoded: sealedBase64),
      let box = try? ChaChaPoly.SealedBox(combined: sealed),
      let clear = try? ChaChaPoly.open(box, using: SymmetricKey(data: key))
    else { return nil }
    return try? JSONDecoder().decode(Message.self, from: clear)
  }
}

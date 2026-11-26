import CryptoKit
import Foundation
import UserNotifications

/// Runs for a few seconds when a push arrives while the application is frozen.
/// The home node that sent the push sealed the message with a key only this
/// phone and that home know; this opens it and puts the real text in the
/// notification. The RetroShare core does not run here.
class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var content: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    content = request.content.mutableCopy() as? UNMutableNotificationContent

    if let content = content,
      let sealed = request.content.userInfo[PushSeal.payloadField] as? String,
      let message = PushSeal.open(sealed)
    {
      content.title = message.title
      if let from = message.from { content.subtitle = from }
      content.body = message.text
      if let thread = message.thread { content.threadIdentifier = thread }
    }
    contentHandler(content ?? request.content)
  }

  override func serviceExtensionTimeWillExpire() {
    if let contentHandler = contentHandler, let content = content {
      contentHandler(content)
    }
  }
}

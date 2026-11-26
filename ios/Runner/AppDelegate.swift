import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private static let channelName = "cc.retroshare.retroshare/retroshare"
  private static let jsonApiPort: Int32 = 9092
  private static let jsonApiBindAddress = "127.0.0.1"
  private static let quietHandoverSeconds = 5.0

  private var rsChannel: FlutterMethodChannel?
  // The core starts and stops on its own queue: both calls block for seconds.
  private let rsQueue = DispatchQueue(label: "cc.retroshare.retroshare.core")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let registrar = self.registrar(forPlugin: "RetroShareCore") {
      let channel = FlutterMethodChannel(
        name: AppDelegate.channelName, binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        self?.handle(call, result: result)
      }
      rsChannel = channel
    }

    NotificationCenter.default.addObserver(
      self, selector: #selector(holdBackgroundTime),
      name: UIApplication.didEnterBackgroundNotification, object: nil)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// iOS suspends the process right after it leaves the screen. The application
  /// then tells the core to go quiet, and the core needs a few seconds to pass
  /// that on to its home nodes: ask the system for that time. The core also
  /// saves its configuration meanwhile.
  @objc private func holdBackgroundTime() {
    let application = UIApplication.shared
    var task = UIBackgroundTaskIdentifier.invalid
    let finish = {
      if task != .invalid {
        application.endBackgroundTask(task)
        task = .invalid
      }
    }
    task = application.beginBackgroundTask(withName: "RetroShare going quiet", expirationHandler: finish)
    // iOS may end the suspended process without notice: what the core has
    // not saved by then is lost.
    rsQueue.async { rs_ios_save_config() }
    DispatchQueue.main.asyncAfter(deadline: .now() + AppDelegate.quietHandoverSeconds, execute: finish)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start":
      rsQueue.async {
        let rc = AppDelegate.startCore()
        DispatchQueue.main.async {
          if rc == 0 {
            result(true)
          } else {
            result(FlutterError(code: "START_FAILED", message: "core start returned \(rc)", details: nil))
          }
        }
      }
    case "stop":
      rsQueue.async {
        rs_ios_stop()
        DispatchQueue.main.async { result(true) }
      }
    case "restart":
      rsQueue.async {
        rs_ios_stop()
        let rc = AppDelegate.startCore()
        DispatchQueue.main.async {
          if rc == 0 {
            result(true)
          } else {
            result(FlutterError(code: "RESTART_FAILED", message: "core start returned \(rc)", details: nil))
          }
        }
      }
    case "isRunning":
      result(rs_ios_is_running() != 0)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// The profiles live in Application Support inside the sandbox.
  private static func startCore() -> Int32 {
    let fm = FileManager.default
    guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return -1
    }
    let baseDir = support.appendingPathComponent("retroshare", isDirectory: true)
    do {
      try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
    } catch {
      NSLog("RetroShare: cannot create %@: %@", baseDir.path, error.localizedDescription)
      return -1
    }
    return rs_ios_start(baseDir.path, jsonApiPort, jsonApiBindAddress)
  }
}

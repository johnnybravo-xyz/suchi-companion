import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let scanChannel = ScanChannel()
  private let shareChannel = ShareChannel()
  private let storageChannel = StorageChannel()
  private let documentChannel = DocumentChannel()
  private let pairingChannel = PairingChannel()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    scanChannel.register(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    shareChannel.register(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    storageChannel.register(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    documentChannel.register(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    pairingChannel.register(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}

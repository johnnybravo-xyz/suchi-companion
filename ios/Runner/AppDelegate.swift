import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let scanChannel = ScanChannel()
  private let shareChannel = ShareChannel()
  private let storageChannel = StorageChannel()
  private let documentChannel = DocumentChannel()
  private let pairingChannel = PairingChannel()
  private let layoutChannel = LayoutChannel()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.registerLaunchHandlers()
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerBGProcessingTask(
      withIdentifier: "page.suchi.companion.background-upload.processing"
    )
    WorkmanagerPlugin.registerBGContinuedProcessingTask(
      withIdentifier: "page.suchi.companion.background-upload.continued.*"
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "SuchiLayoutChannel"
    ) {
      layoutChannel.register(registrar: registrar)
    }
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

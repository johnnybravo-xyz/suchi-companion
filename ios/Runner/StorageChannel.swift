import Flutter
import Foundation

final class StorageChannel {
  private static let channelName = "page.suchi.companion/storage"

  private let fileManager = FileManager.default
  private var channel: FlutterMethodChannel?

  func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    guard call.method == "protectDirectory" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String,
      !path.isEmpty,
      let applicationSupport = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      result(FlutterError(
        code: "bad_storage_path",
        message: "Storage path is required.",
        details: nil
      ))
      return
    }

    let root = applicationSupport.standardizedFileURL.resolvingSymlinksInPath()
    let directory = URL(fileURLWithPath: path, isDirectory: true)
      .standardizedFileURL
      .resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard
      directory.path.hasPrefix(root.path + "/"),
      fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      result(FlutterError(
        code: "bad_storage_path",
        message: "Storage path must be an app support directory.",
        details: nil
      ))
      return
    }

    do {
      var resourceURL = directory
      var resourceValues = URLResourceValues()
      resourceValues.isExcludedFromBackup = true
      try resourceURL.setResourceValues(resourceValues)
      try fileManager.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: directory.path
      )
      result(nil)
    } catch {
      result(FlutterError(
        code: "storage_protection_failed",
        message: "Storage protection failed.",
        details: nil
      ))
    }
  }
}

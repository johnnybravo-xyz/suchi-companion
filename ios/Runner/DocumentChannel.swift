import Flutter
import QuickLook
import UIKit

enum DocumentExport {
  static func file(root: URL, path: String) throws -> URL {
    let directory = root.standardizedFileURL.resolvingSymlinksInPath()
    let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard
      file.deletingLastPathComponent().deletingLastPathComponent() == directory,
      file.deletingLastPathComponent().lastPathComponent.hasPrefix("document-"),
      values.isRegularFile == true,
      let count = values.fileSize,
      count > 0, count <= 64 * 1024 * 1024
    else { throw CocoaError(.fileReadNoPermission) }
    return file
  }
}

final class DocumentChannel: NSObject, QLPreviewControllerDataSource {
  private var channel: FlutterMethodChannel?
  private var previewURL: URL?
  private weak var presented: UIViewController?

  func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "app.suchi.page/documents", binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "document_unavailable", message: "Document viewing is unavailable.", details: nil))
        return
      }
      self.handle(call, result: result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "dismiss" {
      previewURL = nil
      if let presented, presented.presentingViewController != nil {
        presented.dismiss(animated: false) { result(nil) }
      } else {
        result(nil)
      }
      return
    }
    guard call.method == "open" || call.method == "share" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String,
      let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
      let presenter = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .filter({ $0.activationState == .foregroundActive })
        .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController,
      presenter.presentedViewController == nil
    else {
      result(FlutterError(code: "document_busy", message: "Close the current screen before opening a document.", details: nil))
      return
    }
    do {
      let file = try DocumentExport.file(
        root: support.appendingPathComponent("suchi-document-exports", isDirectory: true),
        path: path
      )
      let controller: UIViewController
      if call.method == "share" {
        let activity = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = presenter.view
        activity.popoverPresentationController?.sourceRect = CGRect(
          x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1
        )
        controller = activity
      } else {
        guard QLPreviewController.canPreview(file as NSURL) else {
          result(FlutterError(code: "viewer_unavailable", message: "This document type cannot be previewed. Use Share to open it in another app.", details: nil))
          return
        }
        previewURL = file
        let preview = QLPreviewController()
        preview.dataSource = self
        controller = preview
      }
      presented = controller
      presenter.present(controller, animated: true) { result(nil) }
    } catch {
      result(FlutterError(code: "document_unavailable", message: "The document could not be opened or shared.", details: nil))
    }
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    return previewURL == nil ? 0 : 1
  }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    return previewURL! as NSURL
  }
}

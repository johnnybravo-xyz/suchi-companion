import Flutter
import QuickLook
import UIKit

struct DocumentRoot {
  let directory: URL
  let operationPrefix: String
}

enum DocumentExport {
  static func file(roots: [DocumentRoot], path: String) throws -> URL {
    let requested = URL(fileURLWithPath: path).standardizedFileURL
    let requestedParent = requested.deletingLastPathComponent()
    let requestedValues = try requested.resourceValues(
      forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
    )
    let parentValues = try requestedParent.resourceValues(forKeys: [.isSymbolicLinkKey])
    let file = requested.resolvingSymlinksInPath()
    let parent = file.deletingLastPathComponent()
    let allowed = roots.contains { root in
      let directory = root.directory.standardizedFileURL.resolvingSymlinksInPath()
      let operation = parent.lastPathComponent
      let committedOfflinePayload = root.operationPrefix != "offline-" || (
        operation.range(
          of: "^offline-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
          options: .regularExpression
        ) != nil &&
        file.lastPathComponent.range(
          of: "^document-[1-9][0-9]*\\.[a-z0-9]+$",
          options: .regularExpression
        ) != nil
      )
      return parent.deletingLastPathComponent() == directory
        && operation.hasPrefix(root.operationPrefix)
        && !operation.hasSuffix(".part")
        && committedOfflinePayload
    }
    guard
      requestedValues.isSymbolicLink != true,
      parentValues.isSymbolicLink != true,
      allowed,
      requestedValues.isRegularFile == true,
      let count = requestedValues.fileSize,
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
      name: "page.suchi.companion/documents", binaryMessenger: binaryMessenger
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
        roots: [
          DocumentRoot(
            directory: support.appendingPathComponent("suchi-document-exports", isDirectory: true),
            operationPrefix: "document-"
          ),
          DocumentRoot(
            directory: support.appendingPathComponent("suchi-offline-documents", isDirectory: true),
            operationPrefix: "offline-"
          ),
        ],
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

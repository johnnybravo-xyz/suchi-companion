import AVFoundation
import Flutter
import ImageIO
import UIKit
import Vision
import VisionKit

enum ScanIntakeLimits {
  static let maximumPages = 20
  static let maximumPageBytes: Int64 = 16 << 20
  static let maximumSourceBytes: Int64 = 64 << 20
  static let message =
    "Scans are limited to 20 pages, 16 MiB per page, and 64 MiB total."
}

struct ScanCaptureBudget {
  private let maximumPageBytes: Int64
  private let maximumSourceBytes: Int64
  private(set) var retainedBytes: Int64 = 0

  init(
    maximumPageBytes: Int64 = ScanIntakeLimits.maximumPageBytes,
    maximumSourceBytes: Int64 = ScanIntakeLimits.maximumSourceBytes
  ) {
    self.maximumPageBytes = maximumPageBytes
    self.maximumSourceBytes = maximumSourceBytes
  }

  mutating func addPage(byteCount: Int) throws {
    guard byteCount > 0 else { throw ScanStorageError.encodingFailed }
    let count = Int64(byteCount)
    guard
      count <= maximumPageBytes,
      retainedBytes <= maximumSourceBytes - count
    else {
      throw ScanStorageError.captureTooLarge
    }
    retainedBytes += count
  }
}

enum ScanResultPayload {
  static var cancelled: [String: Any] {
    return [
      "cancelled": true,
      "pdf_path": NSNull(),
      "page_count": 0,
      "pages": [],
    ]
  }

  static func completed(pageURLs: [URL]) -> [String: Any] {
    precondition(!pageURLs.isEmpty)
    return [
      "cancelled": false,
      "pdf_path": NSNull(),
      "page_count": pageURLs.count,
      "pages": pageURLs.map { ["path": $0.path] },
    ]
  }
}

final class ScanChannel: NSObject {
  private static let channelName = "app.suchi.page/scan"
  private static let storeName = "suchi-scanner-captures"
  private static let manifestVersion = 1

  private let fileManager = FileManager.default
  private let workQueue = DispatchQueue(
    label: "app.suchi.page.scan-work",
    qos: .userInitiated
  )
  private var channel: FlutterMethodChannel?
  private var pendingCapture: FlutterResult?
  private var recognitionRunning = false

  func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "scan_unavailable",
            message: "Document scanning is unavailable.",
            details: ["retryable": false]
          )
        )
        return
      }
      self.handle(call, result: result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capture":
      let arguments = call.arguments as? [String: Any]
      let mode = arguments?["mode"] as? String ?? "scanner"
      guard mode == "scanner" || mode == "photo" else {
        result(FlutterError(code: "bad_capture_mode", message: "Unknown camera mode.", details: nil))
        return
      }
      capture(photo: mode == "photo", result: result)
    case "recognizeText":
      recognizeText(call: call, result: result)
    case "discardCapture":
      discardCapture(call: call, result: result)
    case "openSettings":
      openSettings(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func openSettings(result: @escaping FlutterResult) {
    guard
      let url = URL(string: UIApplication.openSettingsURLString),
      UIApplication.shared.canOpenURL(url)
    else {
      result(
        FlutterError(
          code: "settings_unavailable",
          message: "Application settings could not be opened.",
          details: ["retryable": false]
        )
      )
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
      if opened {
        result(nil)
      } else {
        result(
          FlutterError(
            code: "settings_unavailable",
            message: "Application settings could not be opened.",
            details: ["retryable": false]
          )
        )
      }
    }
  }

  private func capture(photo: Bool, result: @escaping FlutterResult) {
    guard pendingCapture == nil else {
      result(
        FlutterError(
          code: "scan_busy",
          message: "A document scan is already active.",
          details: nil
        )
      )
      return
    }
    guard photo ? UIImagePickerController.isSourceTypeAvailable(.camera) : VNDocumentCameraViewController.isSupported else {
      result(
        FlutterError(
          code: "scan_unavailable",
          message: photo ? "Photo capture is unavailable on this device." : "Document scanning is unavailable on this device.",
          details: ["retryable": false]
        )
      )
      return
    }

    pendingCapture = result
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      presentCapture(photo: photo)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self, self.pendingCapture != nil else { return }
          if granted {
            self.presentCapture(photo: photo)
          } else {
            self.failCameraPermission()
          }
        }
      }
    case .denied, .restricted:
      failCameraPermission()
    @unknown default:
      failCapture(
        code: "scan_unavailable",
        message: "Document scanning is unavailable on this device.",
        retryable: false
      )
    }
  }

  private func presentCapture(photo: Bool) {
    guard let presenter = topViewController() else {
      failCapture(
        code: "scan_unavailable",
        message: "The camera could not open.",
        retryable: true
      )
      return
    }
    if photo {
      let camera = UIImagePickerController()
      camera.sourceType = .camera
      camera.cameraCaptureMode = .photo
      camera.allowsEditing = false
      camera.delegate = self
      camera.modalPresentationStyle = .fullScreen
      presenter.present(camera, animated: true)
    } else {
      let scanner = VNDocumentCameraViewController()
      scanner.delegate = self
      presenter.present(scanner, animated: true)
    }
  }

  private func failCameraPermission() {
    let result = pendingCapture
    pendingCapture = nil
    result?(
      FlutterError(
        code: "camera_denied",
        message: "Allow camera access in Settings to capture documents or photos.",
        details: ["retryable": false, "open_settings": true]
      )
    )
  }

  private func failCapture(
    code: String,
    message: String,
    retryable: Bool
  ) {
    let result = pendingCapture
    pendingCapture = nil
    result?(
      FlutterError(
        code: code,
        message: message,
        details: ["retryable": retryable]
      )
    )
  }

  func retain(pageCount: Int, imageAt: (Int) -> UIImage) throws -> [String: Any] {
    guard pageCount <= ScanIntakeLimits.maximumPages else {
      throw ScanStorageError.captureTooLarge
    }
    let root = try storeRoot()
    let captureDirectory = root.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    try createProtectedDirectory(captureDirectory)

    do {
      var pageURLs: [URL] = []
      pageURLs.reserveCapacity(pageCount)
      var budget = ScanCaptureBudget()
      for index in 0..<pageCount {
        let image = imageAt(index)
        guard let data = image.jpegData(compressionQuality: 0.9) else {
          throw ScanStorageError.encodingFailed
        }
        try budget.addPage(byteCount: data.count)
        let destination = captureDirectory.appendingPathComponent(
          String(format: "page-%03d.jpg", index)
        )
        try writeAtomically(data, to: destination)
        pageURLs.append(destination)
      }
      guard !pageURLs.isEmpty else {
        throw ScanStorageError.emptyCapture
      }
      try writeManifest(in: captureDirectory, pages: pageURLs)
      return ScanResultPayload.completed(pageURLs: pageURLs)
    } catch {
      try? fileManager.removeItem(at: captureDirectory)
      throw error
    }
  }

  private func recognizeText(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard !recognitionRunning else {
      result(
        FlutterError(
          code: "ocr_busy",
          message: "Text recognition is already active.",
          details: nil
        )
      )
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let paths = arguments["paths"] as? [String]
    else {
      result(
        FlutterError(
          code: "bad_page_path",
          message: "OCR page paths are invalid.",
          details: nil
        )
      )
      return
    }

    let pageURLs: [URL]
    do {
      pageURLs = try paths.map(validatedCaptureFile(path:))
    } catch {
      result(
        FlutterError(
          code: "bad_page_path",
          message: "OCR page paths are invalid.",
          details: nil
        )
      )
      return
    }
    if pageURLs.isEmpty {
      result([])
      return
    }

    recognitionRunning = true
    workQueue.async { [weak self] in
      guard let self else { return }
      let pages = zip(paths, pageURLs).map { path, url in
        self.recognizePage(path: path, url: url)
      }
      DispatchQueue.main.async {
        self.recognitionRunning = false
        result(pages)
      }
    }
  }

  private func recognizePage(path: String, url: URL) -> [String: Any] {
    guard let image = UIImage(contentsOfFile: url.path), let cgImage = image.cgImage else {
      return failedRecognition(path: path, code: "page_unreadable")
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if #available(iOS 16.0, *) {
      request.automaticallyDetectsLanguage = true
    }
    let handler = VNImageRequestHandler(
      cgImage: cgImage,
      orientation: image.imageOrientation.cgImagePropertyOrientation,
      options: [:]
    )
    do {
      try handler.perform([request])
    } catch {
      return failedRecognition(path: path, code: "recognition_failed")
    }

    var lines: [String] = []
    var weightedConfidence = 0.0
    var characterCount = 0
    for observation in request.results ?? [] {
      guard let candidate = observation.topCandidates(1).first else { continue }
      let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      lines.append(text)
      let count = text.count
      weightedConfidence += Double(candidate.confidence) * Double(count)
      characterCount += count
    }
    return [
      "path": path,
      "text": lines.joined(separator: "\n"),
      "confidence": characterCount == 0
        ? NSNull()
        : weightedConfidence / Double(characterCount),
      "language": NSNull(),
    ]
  }

  private func discardCapture(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let paths = arguments["paths"] as? [String],
      !paths.isEmpty,
      paths.count <= 100
    else {
      result(
        FlutterError(
          code: "bad_capture_paths",
          message: "Capture paths are invalid.",
          details: nil
        )
      )
      return
    }
    let directory: URL
    do {
      let files = try paths.map(validatedCaptureFile(path:))
      directory = files[0].deletingLastPathComponent()
      let root = try storeRoot().resolvingSymlinksInPath().standardizedFileURL
      guard
        directory.deletingLastPathComponent() == root,
        files.allSatisfy({ $0.deletingLastPathComponent() == directory })
      else {
        throw ScanStorageError.invalidPagePath
      }
    } catch {
      result(
        FlutterError(
          code: "bad_capture_paths",
          message: "Capture paths are invalid.",
          details: nil
        )
      )
      return
    }
    workQueue.async { [weak self] in
      do {
        guard let self else { throw ScanStorageError.storageUnavailable }
        try self.fileManager.removeItem(at: directory)
        DispatchQueue.main.async { result(nil) }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "capture_cleanup_failed",
              message: "Captured files could not be removed.",
              details: ["retryable": true]
            )
          )
        }
      }
    }
  }

  private func validatedCaptureFile(path: String) throws -> URL {
    let root = try storeRoot().resolvingSymlinksInPath().standardizedFileURL
    let file = URL(fileURLWithPath: path)
      .resolvingSymlinksInPath()
      .standardizedFileURL
    var isDirectory: ObjCBool = false
    guard
      file.path.hasPrefix(root.path + "/"),
      fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      throw ScanStorageError.invalidPagePath
    }
    return file
  }

  private func storeRoot() throws -> URL {
    guard
      let support = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw ScanStorageError.storageUnavailable
    }
    let root = support.appendingPathComponent(Self.storeName, isDirectory: true)
    try createProtectedDirectory(root)
    return root
  }

  private func createProtectedDirectory(_ url: URL) throws {
    try fileManager.createDirectory(
      at: url,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete]
    )
    try excludeFromBackup(url)
  }

  private func writeManifest(in directory: URL, pages: [URL]) throws {
    let manifest: [String: Any] = [
      "version": Self.manifestVersion,
      "created_at": ISO8601DateFormatter().string(from: Date()),
      "page_count": pages.count,
      "pdf_path": NSNull(),
      "pages": pages.map(\.lastPathComponent),
    ]
    let data = try JSONSerialization.data(withJSONObject: manifest)
    try writeAtomically(
      data,
      to: directory.appendingPathComponent("manifest.json")
    )
  }

  private func writeAtomically(_ data: Data, to destination: URL) throws {
    let part = destination.appendingPathExtension("part")
    try? fileManager.removeItem(at: part)
    guard
      fileManager.createFile(
        atPath: part.path,
        contents: nil,
        attributes: [.protectionKey: FileProtectionType.complete]
      )
    else {
      throw ScanStorageError.storageUnavailable
    }

    let handle = try FileHandle(forWritingTo: part)
    do {
      try handle.write(contentsOf: data)
      try handle.synchronize()
      try handle.close()
    } catch {
      try? handle.close()
      try? fileManager.removeItem(at: part)
      throw error
    }
    try fileManager.moveItem(at: part, to: destination)
    try fileManager.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: destination.path
    )
    try excludeFromBackup(destination)
  }

  private func excludeFromBackup(_ url: URL) throws {
    var resourceURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try resourceURL.setResourceValues(values)
  }

  private func failedRecognition(path: String, code: String) -> [String: Any] {
    return [
      "path": path,
      "text": "",
      "confidence": NSNull(),
      "language": NSNull(),
      "error_code": code,
    ]
  }


  private func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    var controller = window?.rootViewController
    while true {
      if let presented = controller?.presentedViewController {
        controller = presented
      } else if let navigation = controller as? UINavigationController {
        controller = navigation.visibleViewController
      } else if let tabs = controller as? UITabBarController {
        controller = tabs.selectedViewController
      } else {
        return controller
      }
    }
  }

  private func cancelCapture(_ controller: UIViewController) {
    let result = pendingCapture
    pendingCapture = nil
    controller.dismiss(animated: true) {
      result?(ScanResultPayload.cancelled)
    }
  }

  private func finishCapture(
    _ controller: UIViewController,
    pageCount: Int,
    imageAt: @escaping (Int) -> UIImage
  ) {
    let result = pendingCapture
    pendingCapture = nil
    controller.dismiss(animated: true)
    workQueue.async { [weak self] in
      guard let self else { return }
      do {
        let capture = try self.retain(pageCount: pageCount, imageAt: imageAt)
        DispatchQueue.main.async {
          result?(capture)
        }
      } catch ScanStorageError.captureTooLarge {
        DispatchQueue.main.async {
          result?(
            FlutterError(
              code: "capture_too_large",
              message: ScanIntakeLimits.message,
              details: ["retryable": false]
            )
          )
        }
      } catch {
        DispatchQueue.main.async {
          result?(
            FlutterError(
              code: "storage_unavailable",
              message: "Captured files could not be retained.",
              details: ["retryable": true]
            )
          )
        }
      }
    }
  }
}

extension ScanChannel: VNDocumentCameraViewControllerDelegate {
  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    cancelCapture(controller)
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFailWithError error: Error
  ) {
    controller.dismiss(animated: true)
    failCapture(code: "scan_failed", message: "The document scanner did not complete.", retryable: true)
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFinishWith scan: VNDocumentCameraScan
  ) {
    finishCapture(controller, pageCount: scan.pageCount) { scan.imageOfPage(at: $0) }
  }
}

extension ScanChannel: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    cancelCapture(picker)
  }

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    guard let image = info[.originalImage] as? UIImage else {
      picker.dismiss(animated: true)
      failCapture(code: "capture_failed", message: "The camera returned no photo. Try again.", retryable: true)
      return
    }
    finishCapture(picker, pageCount: 1) { _ in image }
  }
}

enum ScanStorageError: Error {
  case captureTooLarge
  case emptyCapture
  case encodingFailed
  case invalidPagePath
  case storageUnavailable
}

private extension UIImage.Orientation {
  var cgImagePropertyOrientation: CGImagePropertyOrientation {
    switch self {
    case .up: .up
    case .down: .down
    case .left: .left
    case .right: .right
    case .upMirrored: .upMirrored
    case .downMirrored: .downMirrored
    case .leftMirrored: .leftMirrored
    case .rightMirrored: .rightMirrored
    @unknown default: .up
    }
  }
}

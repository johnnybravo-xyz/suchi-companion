import Darwin
import Flutter
import Foundation
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private final class SharePickSession {
  let batchId: String
  let result: FlutterResult
  let controller: UIViewController

  init(batchId: String, result: @escaping FlutterResult, controller: UIViewController) {
    self.batchId = batchId
    self.result = result
    self.controller = controller
  }
}

final class ShareChannel: NSObject {
  private let fileManager = FileManager.default
  private let workQueue = DispatchQueue(label: "page.suchi.companion.share-work", qos: .userInitiated)
  private let appGroupRootOverride: URL?
  private let hostRootOverride: URL?
  private var channel: FlutterMethodChannel?
  private var activationObserver: NSObjectProtocol?
  private var pendingPick: SharePickSession?

  init(appGroupRoot: URL? = nil, hostRoot: URL? = nil) {
    appGroupRootOverride = appGroupRoot
    hostRootOverride = hostRoot
    super.init()
  }

  deinit {
    if let activationObserver {
      NotificationCenter.default.removeObserver(activationObserver)
    }
  }

  func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: SuchiShareConstants.channelName,
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "share_unavailable",
            message: "Share intake is unavailable.",
            details: ["retryable": false]
          )
        )
        return
      }
      self.handle(call, result: result)
    }
    self.channel = channel
    activationObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.channel?.invokeMethod("shareEvent", arguments: nil)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pick":
      pick(call: call, result: result)
    case "pending":
      pending(result: result)
    case "discard":
      discard(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func pending(result: @escaping FlutterResult) {
    let activeBatchId = pendingPick?.batchId
    workQueue.async { [weak self] in
      guard let self else { return }
      do {
        let batches = try self.importPendingBatches(excluding: activeBatchId)
        DispatchQueue.main.async { result(batches) }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "share_storage_unavailable",
              message: "Shared files could not be loaded.",
              details: ["retryable": true]
            )
          )
        }
      }
    }
  }

  private func pick(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      Set(arguments.keys) == ["source", "batch_id"],
      let source = arguments["source"] as? String,
      source == "files" || source == "photos",
      let batchId = arguments["batch_id"] as? String,
      SuchiShareStorage.isCanonicalVersionFourUUID(batchId)
    else {
      result(FlutterError(
        code: "bad_pick_request",
        message: "The file selection is invalid.",
        details: nil
      ))
      return
    }
    guard pendingPick == nil else {
      result(FlutterError(
        code: "share_busy",
        message: "A file selection is already active.",
        details: nil
      ))
      return
    }
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    guard let presenter = window?.rootViewController, presenter.presentedViewController == nil else {
      result(FlutterError(
        code: "share_unavailable",
        message: "Files could not be opened right now.",
        details: ["retryable": true]
      ))
      return
    }

    let picker: UIViewController
    if source == "files" {
      let documents = UIDocumentPickerViewController(
        forOpeningContentTypes: [.pdf, .jpeg, .png, .heic, .heif],
        asCopy: true
      )
      documents.allowsMultipleSelection = true
      documents.delegate = self
      picker = documents
    } else {
      var configuration = PHPickerConfiguration()
      configuration.filter = .images
      configuration.selectionLimit = SuchiShareConstants.maximumItems
      configuration.preferredAssetRepresentationMode = .current
      let photos = PHPickerViewController(configuration: configuration)
      photos.delegate = self
      picker = photos
    }
    pendingPick = SharePickSession(batchId: batchId, result: result, controller: picker)
    presenter.present(picker, animated: true)
  }

  private func finishPick(_ picker: UIViewController, value: Any?) {
    guard let request = pendingPick, request.controller === picker else { return }
    pendingPick = nil
    request.result(value)
  }

  private func failPick(_ picker: UIViewController) {
    finishPick(picker, value: FlutterError(
      code: "share_storage_unavailable",
      message: "Selected files could not be saved. Please try again.",
      details: ["retryable": true]
    ))
  }

  // Called only after selection: a cancelled picker never creates a host batch.
  func stagePickedDocuments(_ urls: [URL], batchId: String) async throws {
    try await stagePick(batchId: batchId, inputCount: urls.count) { index, directory in
      let url = urls[index]
      let accessGranted = url.startAccessingSecurityScopedResource()
      defer {
        if accessGranted { url.stopAccessingSecurityScopedResource() }
      }
      let destination = try SuchiShareStorage.directChild(
        named: String(format: "item-%03d.payload", index),
        of: directory
      )
      let inspected = try SuchiShareStorage.copyAndInspect(from: url, to: destination)
      guard Self.documentMime(for: url) == inspected.mime else {
        try? self.fileManager.removeItem(at: destination)
        throw SuchiShareStorageError.unsupportedContent
      }
      return SuchiShareItem(
        index: index,
        path: destination.lastPathComponent,
        mime: inspected.mime,
        name: SuchiShareStorage.sanitizedName(
          url.lastPathComponent,
          mime: inspected.mime,
          index: index
        ),
        size: inspected.size,
        sha256: inspected.sha256
      )
    }
  }

  private static func documentMime(for url: URL) -> String? {
    switch url.pathExtension.lowercased() {
    case "pdf": return "application/pdf"
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "heic": return "image/heic"
    case "heif": return "image/heif"
    default: return nil
    }
  }

  private func stagePickedPhotos(_ results: [PHPickerResult], batchId: String) async throws {
    try await stagePick(batchId: batchId, inputCount: results.count) { index, directory in
      let item = try await SuchiShareProviderLoader.retain(
        provider: results[index].itemProvider,
        index: index,
        in: directory
      )
      guard item.mime != "application/pdf" else {
        let file = try SuchiShareStorage.directChild(named: item.path, of: directory)
        try? self.fileManager.removeItem(at: file)
        throw SuchiShareStorageError.unsupportedContent
      }
      return item
    }
  }

  private func stagePick(
    batchId: String,
    inputCount: Int,
    retain: (Int, URL) async throws -> SuchiShareItem
  ) async throws {
    guard
      SuchiShareStorage.isCanonicalVersionFourUUID(batchId),
      (1...SuchiShareConstants.maximumItems).contains(inputCount)
    else {
      throw SuchiShareStorageError.invalidBatch
    }
    let root = try hostRoot()
    let directory = try SuchiShareStorage.directChild(named: batchId, of: root)
    guard !fileManager.fileExists(atPath: directory.path) else {
      throw SuchiShareStorageError.invalidBatch
    }
    try SuchiShareStorage.createProtectedDirectory(directory)
    var manifest = SuchiShareManifest(
      version: SuchiShareConstants.manifestVersion,
      batchId: batchId,
      createdAt: Int64(Date().timeIntervalSince1970 * 1_000),
      inputCount: inputCount,
      rejectedCount: 0,
      rejectedIndices: [],
      complete: false,
      items: []
    )
    try SuchiShareStorage.atomicWrite(manifest, in: directory)
    try SuchiShareStorage.syncDirectory(root)
    for index in 0..<inputCount {
      do {
        manifest.items.append(try await retain(index, directory))
      } catch SuchiShareStorageError.storageUnavailable {
        throw SuchiShareStorageError.storageUnavailable
      } catch {
        manifest.rejectedIndices.append(index)
        manifest.rejectedCount += 1
      }
      try SuchiShareStorage.atomicWrite(manifest, in: directory)
    }
    manifest.complete = true
    try SuchiShareStorage.atomicWrite(manifest, in: directory)
  }

  func importPendingBatches(excluding activeBatchId: String? = nil) throws -> [[String: Any]] {
    try importAppGroupBatches()
    return try readHostBatches(excluding: activeBatchId)
  }

  private func discard(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      Set(arguments.keys) == ["batch_id"],
      let batchId = arguments["batch_id"] as? String,
      SuchiShareStorage.isCanonicalVersionFourUUID(batchId)
    else {
      result(FlutterError(
        code: "bad_batch_id",
        message: "The share batch id is invalid.",
        details: nil
      ))
      return
    }

    workQueue.async { [weak self] in
      guard let self else { return }
      do {
        try self.discardBatch(batchId)
        DispatchQueue.main.async { result(nil) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "share_storage_unavailable",
            message: "The share batch could not be discarded.",
            details: ["retryable": true]
          ))
        }
      }
    }
  }

  func discardBatch(_ batchId: String) throws {
    guard SuchiShareStorage.isCanonicalVersionFourUUID(batchId) else {
      throw SuchiShareStorageError.invalidBatch
    }
    let root = try hostRoot()
    let directory = try SuchiShareStorage.directChild(named: batchId, of: root)
    if fileManager.fileExists(atPath: directory.path) {
      guard try !isSymbolicLink(directory) else {
        throw SuchiShareStorageError.invalidBatch
      }
      try fileManager.removeItem(at: directory)
      try SuchiShareStorage.syncDirectory(root)
    }
  }

  private func importAppGroupBatches() throws {
    let hostRoot = try hostRoot()
    try cleanupInterruptedImports(in: hostRoot)
    let groupRoot: URL
    if let appGroupRootOverride {
      groupRoot = appGroupRootOverride
    } else {
      guard let resolved = try SuchiShareStorage.appGroupRoot(create: false) else {
        return
      }
      groupRoot = resolved
    }
    let directories = try directDirectories(in: groupRoot)
      .filter { SuchiShareStorage.isCanonicalVersionFourUUID($0.lastPathComponent) }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    for source in directories {
      let manifest: SuchiShareManifest
      do {
        manifest = try SuchiShareStorage.readManifest(in: source)
      } catch SuchiShareStorageError.invalidManifest {
        try importRejectedBatch(batchId: source.lastPathComponent, into: hostRoot)
        try removeImportedSource(source, from: groupRoot)
        continue
      } catch SuchiShareStorageError.invalidItem {
        try importRejectedBatch(batchId: source.lastPathComponent, into: hostRoot)
        try removeImportedSource(source, from: groupRoot)
        continue
      }
      try importBatch(manifest, from: source, groupRoot: groupRoot, hostRoot: hostRoot)
    }
  }

  private func importBatch(
    _ sourceManifest: SuchiShareManifest,
    from source: URL,
    groupRoot: URL,
    hostRoot: URL
  ) throws {
    let destination = try SuchiShareStorage.directChild(
      named: sourceManifest.batchId,
      of: hostRoot
    )
    if fileManager.fileExists(atPath: destination.path) {
      _ = try readHostBatch(at: destination)
      try removeImportedSource(source, from: groupRoot)
      return
    }

    let temporaryName = "\(sourceManifest.batchId).import-\(UUID().uuidString.lowercased())"
    let temporary = try SuchiShareStorage.directChild(named: temporaryName, of: hostRoot)
    try SuchiShareStorage.createProtectedDirectory(temporary)
    do {
      var retained: [SuchiShareItem] = []
      var rejected = Set(sourceManifest.rejectedIndices)
      for item in sourceManifest.items {
        do {
          let sourceFile = try SuchiShareStorage.directChild(named: item.path, of: source)
          let destinationFile = try SuchiShareStorage.directChild(named: item.path, of: temporary)
          _ = try SuchiShareStorage.copyAndInspect(
            from: sourceFile,
            to: destinationFile,
            expected: item
          )
          retained.append(item)
        } catch SuchiShareStorageError.invalidItem,
          SuchiShareStorageError.unsupportedContent,
          SuchiShareStorageError.itemTooLarge
        {
          rejected.insert(item.index)
        }
      }
      retained.sort { $0.index < $1.index }
      if !sourceManifest.complete {
        let received = Set(retained.map(\.index)).union(rejected)
        for index in 0..<sourceManifest.inputCount where !received.contains(index) {
          rejected.insert(index)
        }
      }
      let importedManifest = SuchiShareManifest(
        version: SuchiShareConstants.manifestVersion,
        batchId: sourceManifest.batchId,
        createdAt: sourceManifest.createdAt,
        inputCount: sourceManifest.inputCount,
        rejectedCount: rejected.count,
        rejectedIndices: rejected.sorted(),
        // Treat a handed-off incomplete manifest as interrupted: preserve
        // every verified item, reject missing inputs, and let Dart drain it.
        complete: true,
        items: retained
      )
      try SuchiShareStorage.atomicWrite(
        importedManifest,
        in: temporary,
        expectedBatchId: sourceManifest.batchId
      )
      if Darwin.rename(temporary.path, destination.path) != 0 {
        throw SuchiShareStorageError.storageUnavailable
      }
      try SuchiShareStorage.syncDirectory(hostRoot)
      try removeImportedSource(source, from: groupRoot)
    } catch {
      try? fileManager.removeItem(at: temporary)
      throw error
    }
  }

  private func importRejectedBatch(batchId: String, into hostRoot: URL) throws {
    let destination = try SuchiShareStorage.directChild(named: batchId, of: hostRoot)
    if fileManager.fileExists(atPath: destination.path) {
      _ = try readHostBatch(at: destination)
      return
    }
    let temporaryName = "\(batchId).import-\(UUID().uuidString.lowercased())"
    let temporary = try SuchiShareStorage.directChild(named: temporaryName, of: hostRoot)
    try SuchiShareStorage.createProtectedDirectory(temporary)
    do {
      let manifest = SuchiShareManifest(
        version: SuchiShareConstants.manifestVersion,
        batchId: batchId,
        createdAt: Int64(Date().timeIntervalSince1970 * 1_000),
        inputCount: 1,
        rejectedCount: 1,
        rejectedIndices: [0],
        complete: true,
        items: []
      )
      try SuchiShareStorage.atomicWrite(
        manifest,
        in: temporary,
        expectedBatchId: batchId
      )
      if Darwin.rename(temporary.path, destination.path) != 0 {
        throw SuchiShareStorageError.storageUnavailable
      }
      try SuchiShareStorage.syncDirectory(hostRoot)
    } catch {
      try? fileManager.removeItem(at: temporary)
      throw error
    }
  }

  private func readHostBatches(excluding activeBatchId: String?) throws -> [[String: Any]] {
    let root = try hostRoot()
    let directories = try directDirectories(in: root)
      .filter {
        SuchiShareStorage.isCanonicalVersionFourUUID($0.lastPathComponent)
          && $0.lastPathComponent != activeBatchId
      }
    var batches: [[String: Any]] = []
    batches.reserveCapacity(directories.count)
    for directory in directories {
      do {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
          throw SuchiShareStorageError.invalidManifest
        }
        var manifest = try SuchiShareStorage.readManifest(in: directory)
        if !manifest.complete {
          let received = Set(manifest.items.map(\.index))
            .union(manifest.rejectedIndices)
          manifest.rejectedIndices += (0..<manifest.inputCount)
            .filter { !received.contains($0) }
          manifest.rejectedIndices.sort()
          manifest.rejectedCount = manifest.rejectedIndices.count
          manifest.complete = true
          try SuchiShareStorage.atomicWrite(manifest, in: directory)
        }
        batches.append(try readHostBatch(at: directory))
      } catch SuchiShareStorageError.invalidManifest,
        SuchiShareStorageError.invalidItem,
        SuchiShareStorageError.unsupportedContent,
        SuchiShareStorageError.itemTooLarge
      {
        let batchId = directory.lastPathComponent
        try fileManager.removeItem(at: directory)
        try SuchiShareStorage.syncDirectory(root)
        try importRejectedBatch(batchId: batchId, into: root)
        batches.append(try readHostBatch(at: directory))
      }
    }
    return batches.sorted {
      let left = $0["created_at"] as? Int64 ?? 0
      let right = $1["created_at"] as? Int64 ?? 0
      if left == right {
        return ($0["batch_id"] as? String ?? "") < ($1["batch_id"] as? String ?? "")
      }
      return left < right
    }
  }

  private func readHostBatch(at directory: URL) throws -> [String: Any] {
    let manifest = try SuchiShareStorage.readManifest(in: directory)
    var items: [[String: Any]] = []
    items.reserveCapacity(manifest.items.count)
    for item in manifest.items {
      let file = try SuchiShareStorage.directChild(named: item.path, of: directory)
      _ = try SuchiShareStorage.inspect(file, expected: item)
      items.append([
        "index": item.index,
        "path": file.path,
        "mime": item.mime,
        "name": item.name,
        "size": item.size,
        "sha256": item.sha256,
      ])
    }
    return [
      "batch_id": manifest.batchId,
      "created_at": manifest.createdAt,
      "rejected_count": manifest.rejectedCount,
      "complete": manifest.complete,
      "items": items,
    ]
  }

  private func hostRoot() throws -> URL {
    if let hostRootOverride {
      try SuchiShareStorage.createProtectedDirectory(hostRootOverride)
      return hostRootOverride
    }
    guard
      let support = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw SuchiShareStorageError.storageUnavailable
    }
    let root = support.appendingPathComponent(
      SuchiShareConstants.storeName,
      isDirectory: true
    )
    try SuchiShareStorage.createProtectedDirectory(root)
    return root
  }

  private func directDirectories(in root: URL) throws -> [URL] {
    return try fileManager.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
      options: [.skipsHiddenFiles]
    ).filter { url in
      let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      return values.isDirectory == true && values.isSymbolicLink != true
    }
  }

  private func cleanupInterruptedImports(in root: URL) throws {
    for directory in try directDirectories(in: root) {
      let name = directory.lastPathComponent
      guard
        name.count > 44,
        name.dropFirst(36).hasPrefix(".import-"),
        SuchiShareStorage.isCanonicalVersionFourUUID(String(name.prefix(36)))
      else {
        continue
      }
      try fileManager.removeItem(at: directory)
    }
  }

  private func removeImportedSource(_ source: URL, from root: URL) throws {
    let expected = try SuchiShareStorage.directChild(named: source.lastPathComponent, of: root)
    guard expected.standardizedFileURL.path == source.standardizedFileURL.path else {
      throw SuchiShareStorageError.invalidBatch
    }
    try fileManager.removeItem(at: source)
    try SuchiShareStorage.syncDirectory(root)
  }

  private func isSymbolicLink(_ url: URL) throws -> Bool {
    return try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
  }
}

extension ShareChannel: UIDocumentPickerDelegate, PHPickerViewControllerDelegate {
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishPick(controller, value: nil)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let request = pendingPick, request.controller === controller else { return }
    guard !urls.isEmpty else {
      finishPick(controller, value: nil)
      return
    }
    guard urls.count <= SuchiShareConstants.maximumItems else {
      finishPick(controller, value: FlutterError(
        code: "share_selection_too_large",
        message: "Select no more than 20 files at a time.",
        details: ["retryable": false]
      ))
      return
    }
    Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { return }
      do {
        try await self.stagePickedDocuments(urls, batchId: request.batchId)
        await MainActor.run {
          self.finishPick(controller, value: request.batchId)
        }
      } catch {
        await MainActor.run { self.failPick(controller) }
      }
    }
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    guard let request = pendingPick, request.controller === picker else { return }
    picker.dismiss(animated: true)
    guard !results.isEmpty else {
      finishPick(picker, value: nil)
      return
    }
    guard results.count <= SuchiShareConstants.maximumItems else {
      failPick(picker)
      return
    }
    Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { return }
      do {
        try await self.stagePickedPhotos(results, batchId: request.batchId)
        await MainActor.run {
          self.finishPick(picker, value: request.batchId)
        }
      } catch {
        await MainActor.run { self.failPick(picker) }
      }
    }
  }
}

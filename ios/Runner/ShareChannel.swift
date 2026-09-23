import Darwin
import Flutter
import Foundation
import UIKit

final class ShareChannel {
  private let fileManager = FileManager.default
  private let workQueue = DispatchQueue(label: "app.suchi.page.share-work", qos: .userInitiated)
  private let appGroupRootOverride: URL?
  private let hostRootOverride: URL?
  private var channel: FlutterMethodChannel?
  private var activationObserver: NSObjectProtocol?

  init(appGroupRoot: URL? = nil, hostRoot: URL? = nil) {
    appGroupRootOverride = appGroupRoot
    hostRootOverride = hostRoot
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
    case "pending":
      pending(result: result)
    case "discard":
      discard(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func pending(result: @escaping FlutterResult) {
    workQueue.async { [weak self] in
      guard let self else { return }
      do {
        let batches = try self.importPendingBatches()
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
  func importPendingBatches() throws -> [[String: Any]] {
    try importAppGroupBatches()
    return try readHostBatches()
  }

  private func discard(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      Set(arguments.keys) == ["batch_id"],
      let batchId = arguments["batch_id"] as? String,
      SuchiShareStorage.isCanonicalVersionFourUUID(batchId)
    else {
      result(
        FlutterError(
          code: "bad_batch_id",
          message: "The share batch id is invalid.",
          details: nil
        )
      )
      return
    }

    workQueue.async { [weak self] in
      guard let self else { return }
      do {
        let root = try self.hostRoot()
        let directory = try SuchiShareStorage.directChild(named: batchId, of: root)
        if self.fileManager.fileExists(atPath: directory.path) {
          guard try !self.isSymbolicLink(directory) else {
            throw SuchiShareStorageError.invalidBatch
          }
          try self.fileManager.removeItem(at: directory)
          try SuchiShareStorage.syncDirectory(root)
        }
        DispatchQueue.main.async { result(nil) }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "share_storage_unavailable",
              message: "The share batch could not be discarded.",
              details: ["retryable": true]
            )
          )
        }
      }
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

  private func readHostBatches() throws -> [[String: Any]] {
    let root = try hostRoot()
    let directories = try directDirectories(in: root)
      .filter { SuchiShareStorage.isCanonicalVersionFourUUID($0.lastPathComponent) }
    var batches: [[String: Any]] = []
    batches.reserveCapacity(directories.count)
    for directory in directories {
      do {
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

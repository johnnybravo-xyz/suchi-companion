import CryptoKit
import Darwin
import Foundation
import UniformTypeIdentifiers

enum SuchiShareConstants {
  static let appGroup = "group.page.suchi.companion"
  static let channelName = "page.suchi.companion/share"
  static let storeName = "suchi-share-imports"
  static let manifestVersion = 1
  static let maximumItems = 20
  static let maximumManifestBytes: Int64 = 1 << 20
  static let maximumItemBytes: Int64 = 64 << 20
  static let copyBufferSize = 64 * 1024
  static let supportedMimes = Set([
    "application/pdf",
    "image/jpeg",
    "image/png",
    "image/heic",
    "image/heif",
  ])
}

enum SuchiShareStorageError: Error {
  case invalidBatch
  case invalidItem
  case invalidManifest
  case itemTooLarge
  case storageUnavailable
  case unsupportedContent
  case providerTimedOut
}

struct SuchiShareItem: Codable, Equatable {
  let index: Int
  let path: String
  let mime: String
  let name: String
  let size: Int64
  let sha256: String
}

struct SuchiShareManifest: Codable, Equatable {
  let version: Int
  let batchId: String
  let createdAt: Int64
  let inputCount: Int
  var rejectedCount: Int
  var rejectedIndices: [Int]
  var complete: Bool
  var items: [SuchiShareItem]

  enum CodingKeys: String, CodingKey {
    case version
    case batchId = "batch_id"
    case createdAt = "created_at"
    case inputCount = "input_count"
    case rejectedCount = "rejected_count"
    case rejectedIndices = "rejected_indices"
    case complete
    case items
  }
}

struct SuchiInspectedFile {
  let mime: String
  let size: Int64
  let sha256: String
}

private final class SuchiShareProviderCompletion {
  private let lock = NSLock()
  private var completed = false

  @discardableResult
  func resume(
    _ continuation: CheckedContinuation<SuchiShareItem, Error>,
    with result: Result<SuchiShareItem, Error>
  ) -> Bool {
    lock.lock()
    guard !completed else {
      lock.unlock()
      return false
    }
    completed = true
    lock.unlock()
    continuation.resume(with: result)
    return true
  }
}

enum SuchiShareProviderLoader {
  static let defaultTimeout: TimeInterval = 20

  static func retain(
    provider: NSItemProvider,
    index: Int,
    in directory: URL,
    timeout: TimeInterval = defaultTimeout,
    maximumBytes: Int64 = SuchiShareConstants.maximumItemBytes
  ) async throws -> SuchiShareItem {
    guard
      timeout > 0,
      let typeIdentifier = SuchiShareStorage.preferredTypeIdentifier(for: provider)
    else {
      throw SuchiShareStorageError.unsupportedContent
    }
    let destination = try SuchiShareStorage.directChild(
      named: String(format: "item-%03d.payload", index),
      of: directory
    )
    return try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<SuchiShareItem, Error>) in
      let completion = SuchiShareProviderCompletion()
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
        _ = completion.resume(
          continuation,
          with: .failure(SuchiShareStorageError.providerTimedOut)
        )
      }
      provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
        do {
          if let error { throw error }
          guard let url else { throw SuchiShareStorageError.invalidItem }
          let inspected = try SuchiShareStorage.copyAndInspect(
            from: url,
            to: destination,
            maximumBytes: maximumBytes
          )
          guard
            let declaredMime = declaredMime(for: typeIdentifier),
            declaredMime == inspected.mime
          else {
            try? FileManager.default.removeItem(at: destination)
            throw SuchiShareStorageError.unsupportedContent
          }
          let item = SuchiShareItem(
            index: index,
            path: destination.lastPathComponent,
            mime: inspected.mime,
            name: SuchiShareStorage.sanitizedName(
              provider.suggestedName ?? url.lastPathComponent,
              mime: inspected.mime,
              index: index
            ),
            size: inspected.size,
            sha256: inspected.sha256
          )
          if !completion.resume(continuation, with: .success(item)) {
            try? FileManager.default.removeItem(at: destination)
          }
        } catch {
          _ = completion.resume(continuation, with: .failure(error))
        }
      }
    }
  }

  private static func declaredMime(for identifier: String) -> String? {
    guard let type = UTType(identifier) else { return nil }
    if type.conforms(to: .pdf) { return "application/pdf" }
    if type.conforms(to: .jpeg) { return "image/jpeg" }
    if type.conforms(to: .png) { return "image/png" }
    if type.conforms(to: .heic) { return "image/heic" }
    if type.conforms(to: .heif) { return "image/heif" }
    return nil
  }
}

enum SuchiShareStorage {
  private static let manifestKeys = Set([
    "version",
    "batch_id",
    "created_at",
    "input_count",
    "rejected_count",
    "rejected_indices",
    "complete",
    "items",
  ])
  private static let itemKeys = Set([
    "index",
    "path",
    "mime",
    "name",
    "size",
    "sha256",
  ])

  static func appGroupRoot(create: Bool) throws -> URL? {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: SuchiShareConstants.appGroup
      )
    else {
      throw SuchiShareStorageError.storageUnavailable
    }
    let root = container.appendingPathComponent(
      SuchiShareConstants.storeName,
      isDirectory: true
    )
    if create {
      try createProtectedDirectory(root)
      return root
    }
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: root.path,
        isDirectory: &isDirectory
      )
    else {
      return nil
    }
    guard isDirectory.boolValue, try !isSymbolicLink(root) else {
      throw SuchiShareStorageError.storageUnavailable
    }
    return root
  }

  static func createProtectedDirectory(_ url: URL) throws {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
      guard isDirectory.boolValue, try !isSymbolicLink(url) else {
        throw SuchiShareStorageError.storageUnavailable
      }
    } else {
      try fileManager.createDirectory(
        at: url,
        withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.complete]
      )
    }
    try fileManager.setAttributes(
      [.protectionKey: FileProtectionType.complete],
      ofItemAtPath: url.path
    )
    try excludeFromBackup(url)
  }

  static func atomicWrite(
    _ manifest: SuchiShareManifest,
    in directory: URL,
    expectedBatchId: String? = nil
  ) throws {
    try validate(
      manifest,
      expectedBatchId: expectedBatchId ?? directory.lastPathComponent
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(manifest)
    guard Int64(data.count) <= SuchiShareConstants.maximumManifestBytes else {
      throw SuchiShareStorageError.invalidManifest
    }
    let destination = directory.appendingPathComponent("manifest.json")
    let part = directory.appendingPathComponent("manifest.json.part")
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: part)
    guard
      fileManager.createFile(
        atPath: part.path,
        contents: nil,
        attributes: [.protectionKey: FileProtectionType.complete]
      )
    else {
      throw SuchiShareStorageError.storageUnavailable
    }

    let handle = try FileHandle(forWritingTo: part)
    do {
      try handle.write(contentsOf: data)
      try handle.synchronize()
      try handle.close()
      if Darwin.rename(part.path, destination.path) != 0 {
        throw SuchiShareStorageError.storageUnavailable
      }
      try excludeFromBackup(destination)
      try syncDirectory(directory)
    } catch {
      try? handle.close()
      try? fileManager.removeItem(at: part)
      throw error
    }
  }

  static func readManifest(in directory: URL) throws -> SuchiShareManifest {
    let url = directory.appendingPathComponent("manifest.json")
    let values = try url.resourceValues(
      forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
    )
    guard
      values.isRegularFile == true,
      values.isSymbolicLink != true,
      let byteCount = values.fileSize,
      byteCount >= 0,
      Int64(byteCount) <= SuchiShareConstants.maximumManifestBytes
    else {
      throw SuchiShareStorageError.invalidManifest
    }
    let data = try Data(contentsOf: url)
    let object: [String: Any]
    do {
      guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SuchiShareStorageError.invalidManifest
      }
      object = decoded
    } catch {
      throw SuchiShareStorageError.invalidManifest
    }
    guard
      Set(object.keys) == manifestKeys,
      let rawItems = object["items"] as? [[String: Any]],
      rawItems.allSatisfy({ Set($0.keys) == itemKeys })
    else {
      throw SuchiShareStorageError.invalidManifest
    }
    let manifest: SuchiShareManifest
    do {
      manifest = try JSONDecoder().decode(SuchiShareManifest.self, from: data)
    } catch {
      throw SuchiShareStorageError.invalidManifest
    }
    try validate(manifest, expectedBatchId: directory.lastPathComponent)
    return manifest
  }

  static func validate(
    _ manifest: SuchiShareManifest,
    expectedBatchId: String? = nil
  ) throws {
    guard
      manifest.version == SuchiShareConstants.manifestVersion,
      isCanonicalVersionFourUUID(manifest.batchId),
      expectedBatchId == nil || manifest.batchId == expectedBatchId,
      manifest.createdAt > 0,
      manifest.inputCount > 0,
      manifest.inputCount <= 10_000,
      manifest.rejectedCount == manifest.rejectedIndices.count,
      manifest.items.count <= SuchiShareConstants.maximumItems,
      manifest.rejectedIndices.count <= 10_000
    else {
      throw SuchiShareStorageError.invalidManifest
    }

    var seen = Set<Int>()
    var previousItemIndex = -1
    for item in manifest.items {
      guard
        item.index > previousItemIndex,
        item.index >= 0,
        item.index < manifest.inputCount,
        seen.insert(item.index).inserted,
        isValidRelativeName(item.path, maximumBytes: 200),
        isValidRelativeName(item.name, maximumBytes: 255),
        SuchiShareConstants.supportedMimes.contains(item.mime),
        item.size > 0,
        item.size <= SuchiShareConstants.maximumItemBytes,
        isLowercaseSHA256(item.sha256)
      else {
        throw SuchiShareStorageError.invalidItem
      }
      previousItemIndex = item.index
    }

    var previousRejectedIndex = -1
    for index in manifest.rejectedIndices {
      guard
        index > previousRejectedIndex,
        index >= 0,
        index < manifest.inputCount,
        seen.insert(index).inserted
      else {
        throw SuchiShareStorageError.invalidManifest
      }
      previousRejectedIndex = index
    }
    guard !manifest.complete || seen.count == manifest.inputCount else {
      throw SuchiShareStorageError.invalidManifest
    }
  }

  static func preferredTypeIdentifier(for provider: NSItemProvider) -> String? {
    let preferredTypes: [UTType] = [.pdf, .jpeg, .png, .heic, .heif]
    for preferred in preferredTypes {
      if let identifier = provider.registeredTypeIdentifiers.first(where: {
        guard let candidate = UTType($0) else { return false }
        return candidate.conforms(to: preferred)
      }) {
        return identifier
      }
    }
    return nil
  }

  static func sanitizedName(
    _ rawName: String?,
    mime: String,
    index: Int
  ) -> String {
    let requiredExtension = fileExtension(for: mime)
    let candidate =
      (rawName ?? "")
      .split(whereSeparator: { $0 == "/" || $0 == "\\" })
      .last
      .map(String.init) ?? ""
    let safeCharacters = candidate.map { character -> Character in
      if character.isLetter || character.isNumber || " .-_".contains(character) {
        return character
      }
      return "_"
    }
    var safe = String(safeCharacters)
      .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    let existingStem = (safe as NSString).deletingPathExtension
    let fallbackStem = "shared-\(index + 1)"
    var stem = existingStem.isEmpty ? fallbackStem : existingStem
    let suffix = ".\(requiredExtension)"
    let maximumStemBytes = 255 - suffix.utf8.count
    var byteCount = 0
    stem = String(stem.prefix { character in
      let count = String(character).utf8.count
      guard byteCount + count <= maximumStemBytes else { return false }
      byteCount += count
      return true
    })
    stem = stem.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    if stem.isEmpty { stem = fallbackStem }
    safe = stem + suffix
    return safe
  }

  static func copyAndInspect(
    from source: URL,
    to destination: URL,
    expected: SuchiShareItem? = nil,
    maximumBytes: Int64 = SuchiShareConstants.maximumItemBytes
  ) throws -> SuchiInspectedFile {
    return try consume(
      source: source,
      destination: destination,
      expected: expected,
      maximumBytes: maximumBytes
    )
  }

  static func inspect(
    _ source: URL,
    expected: SuchiShareItem? = nil,
    maximumBytes: Int64 = SuchiShareConstants.maximumItemBytes
  ) throws -> SuchiInspectedFile {
    return try consume(
      source: source,
      destination: nil,
      expected: expected,
      maximumBytes: maximumBytes
    )
  }

  static func directChild(named name: String, of root: URL) throws -> URL {
    guard isValidRelativeName(name, maximumBytes: 512) else {
      throw SuchiShareStorageError.invalidItem
    }
    let standardizedRoot = root.standardizedFileURL
    let child = standardizedRoot.appendingPathComponent(name).standardizedFileURL
    guard child.deletingLastPathComponent().path == standardizedRoot.path else {
      throw SuchiShareStorageError.invalidItem
    }
    return child
  }

  static func isCanonicalVersionFourUUID(_ value: String) -> Bool {
    guard
      value.count == 36,
      let uuid = UUID(uuidString: value),
      uuid.uuidString.lowercased() == value
    else {
      return false
    }
    let characters = Array(value)
    guard characters[14] == "4" else { return false }
    return "89ab".contains(characters[19])
  }

  static func syncDirectory(_ directory: URL) throws {
    let descriptor = Darwin.open(directory.path, O_RDONLY)
    guard descriptor >= 0 else {
      throw SuchiShareStorageError.storageUnavailable
    }
    defer { Darwin.close(descriptor) }
    guard Darwin.fsync(descriptor) == 0 else {
      throw SuchiShareStorageError.storageUnavailable
    }
  }

  private static func consume(
    source: URL,
    destination: URL?,
    expected: SuchiShareItem?,
    maximumBytes: Int64
  ) throws -> SuchiInspectedFile {
    guard maximumBytes > 0 else { throw SuchiShareStorageError.itemTooLarge }
    if let expected, expected.size > maximumBytes {
      throw SuchiShareStorageError.itemTooLarge
    }
    let sourceValues = try source.resourceValues(
      forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
    )
    guard
      sourceValues.isRegularFile == true,
      sourceValues.isSymbolicLink != true
    else {
      throw SuchiShareStorageError.invalidItem
    }

    let fileManager = FileManager.default
    let part = destination?.appendingPathExtension("part")
    if let part {
      try? fileManager.removeItem(at: part)
      guard
        fileManager.createFile(
          atPath: part.path,
          contents: nil,
          attributes: [.protectionKey: FileProtectionType.complete]
        )
      else {
        throw SuchiShareStorageError.storageUnavailable
      }
    }

    let input = try FileHandle(forReadingFrom: source)
    let output = try part.map(FileHandle.init(forWritingTo:))
    var digest = SHA256()
    var byteCount: Int64 = 0
    var header = Data()

    do {
      while let chunk = try input.read(upToCount: SuchiShareConstants.copyBufferSize),
        !chunk.isEmpty
      {
        if header.count < 4_096 {
          header.append(chunk.prefix(4_096 - header.count))
        }
        let nextByteCount = try adding(byteCount, Int64(chunk.count))
        guard nextByteCount <= maximumBytes else {
          throw SuchiShareStorageError.itemTooLarge
        }
        byteCount = nextByteCount
        digest.update(data: chunk)
        try output?.write(contentsOf: chunk)
      }
      try output?.synchronize()
      try input.close()
      try output?.close()

      guard let mime = detectedMime(header: header), byteCount > 0 else {
        throw SuchiShareStorageError.unsupportedContent
      }
      let sha256 = digest.finalize().map { String(format: "%02x", $0) }.joined()
      if let expected {
        guard
          expected.mime == mime,
          expected.size == byteCount,
          expected.sha256 == sha256
        else {
          throw SuchiShareStorageError.invalidItem
        }
      }

      if let destination, let part {
        if Darwin.rename(part.path, destination.path) != 0 {
          throw SuchiShareStorageError.storageUnavailable
        }
        try excludeFromBackup(destination)
        try syncDirectory(destination.deletingLastPathComponent())
      }
      return SuchiInspectedFile(mime: mime, size: byteCount, sha256: sha256)
    } catch {
      try? input.close()
      try? output?.close()
      if let part {
        try? fileManager.removeItem(at: part)
      }
      throw error
    }
  }

  private static func detectedMime(header: Data) -> String? {
    let bytes = Array(header)
    if bytes.count >= 5, bytes[0...4] == Array("%PDF-".utf8)[0...4] {
      return "application/pdf"
    }
    if bytes.count >= 3, bytes[0] == 0xff, bytes[1] == 0xd8, bytes[2] == 0xff {
      return "image/jpeg"
    }
    let png: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
    if bytes.count >= png.count, Array(bytes.prefix(png.count)) == png {
      return "image/png"
    }
    guard
      bytes.count >= 16,
      String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp"
    else {
      return nil
    }
    let boxSize =
      (Int(bytes[0]) << 24) | (Int(bytes[1]) << 16) | (Int(bytes[2]) << 8) | Int(bytes[3])
    guard
      boxSize >= 16,
      boxSize <= bytes.count,
      boxSize <= 4_096,
      (boxSize - 16).isMultiple(of: 4)
    else {
      return nil
    }
    var brands: [String] = []
    for offset in stride(from: 8, to: boxSize, by: 4) where offset != 12 {
      guard
        let brand = String(
          bytes: bytes[offset..<(offset + 4)],
          encoding: .ascii
        )?.lowercased()
      else {
        return nil
      }
      brands.append(brand)
    }
    if brands.contains(where: { $0 == "avif" || $0 == "avis" }) {
      return nil
    }
    if brands.contains(where: { ["heic", "heix", "hevc", "hevx"].contains($0) }) {
      return "image/heic"
    }
    if brands.contains(where: { ["mif1", "msf1"].contains($0) }) {
      return "image/heif"
    }
    return nil
  }

  private static func fileExtension(for mime: String) -> String {
    switch mime {
    case "application/pdf": return "pdf"
    case "image/jpeg": return "jpg"
    case "image/png": return "png"
    case "image/heic": return "heic"
    case "image/heif": return "heif"
    default: return "bin"
    }
  }

  private static func adding(_ left: Int64, _ right: Int64) throws -> Int64 {
    let (sum, overflow) = left.addingReportingOverflow(right)
    guard !overflow else { throw SuchiShareStorageError.storageUnavailable }
    return sum
  }

  private static func isValidRelativeName(
    _ value: String,
    maximumBytes: Int
  ) -> Bool {
    guard
      !value.isEmpty,
      value != ".",
      value != "..",
      value.utf8.count <= maximumBytes,
      !value.contains("/"),
      !value.contains("\\"),
      !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      return false
    }
    return URL(fileURLWithPath: value).lastPathComponent == value
  }

  private static func isLowercaseSHA256(_ value: String) -> Bool {
    guard value.utf8.count == 64 else { return false }
    return value.utf8.allSatisfy {
      ($0 >= Character("0").asciiValue! && $0 <= Character("9").asciiValue!)
        || ($0 >= Character("a").asciiValue! && $0 <= Character("f").asciiValue!)
    }
  }

  private static func isSymbolicLink(_ url: URL) throws -> Bool {
    return try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
  }

  private static func excludeFromBackup(_ url: URL) throws {
    var resourceURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try resourceURL.setResourceValues(values)
  }
}

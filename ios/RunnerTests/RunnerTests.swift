import XCTest
import UIKit
import UniformTypeIdentifiers

@testable import Runner

final class RunnerTests: XCTestCase {
  private var temporaryRoot: URL!

  override func setUpWithError() throws {
    temporaryRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try SuchiShareStorage.createProtectedDirectory(temporaryRoot)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryRoot)
    temporaryRoot = nil
  }

  func testDocumentExportsRejectFilesOutsideTheirDedicatedDirectory() throws {
    let root = temporaryRoot.appendingPathComponent("exports", isDirectory: true)
    let operation = root.appendingPathComponent("document-test", isDirectory: true)
    try FileManager.default.createDirectory(at: operation, withIntermediateDirectories: true)
    let file = operation.appendingPathComponent("document-91.pdf")
    try Data("%PDF-test".utf8).write(to: file)
    XCTAssertEqual(try DocumentExport.file(root: root, path: file.path), file)

    let outside = temporaryRoot.appendingPathComponent("private.pdf")
    try Data("private".utf8).write(to: outside)
    XCTAssertThrowsError(try DocumentExport.file(root: root, path: outside.path))
    let link = operation.appendingPathComponent("linked.pdf")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    XCTAssertThrowsError(try DocumentExport.file(root: root, path: link.path))
  }

  func testManifestAndPayloadRoundTrip() throws {
    let source = temporaryRoot.appendingPathComponent("source.png")
    try validPNG().write(to: source)
    let batchId = "c4652f32-b979-4fc0-adbe-1d761beb2209"
    let batch = temporaryRoot.appendingPathComponent(batchId, isDirectory: true)
    try SuchiShareStorage.createProtectedDirectory(batch)
    let payload = batch.appendingPathComponent("item-000.payload")
    let inspected = try SuchiShareStorage.copyAndInspect(from: source, to: payload)
    let item = SuchiShareItem(
      index: 0,
      path: payload.lastPathComponent,
      mime: inspected.mime,
      name: "shared.png",
      size: inspected.size,
      sha256: inspected.sha256
    )
    let manifest = SuchiShareManifest(
      version: SuchiShareConstants.manifestVersion,
      batchId: batchId,
      createdAt: 2_000,
      inputCount: 1,
      rejectedCount: 0,
      rejectedIndices: [],
      complete: true,
      items: [item]
    )

    try SuchiShareStorage.atomicWrite(manifest, in: batch)

    XCTAssertEqual(try SuchiShareStorage.readManifest(in: batch), manifest)
    XCTAssertEqual(try SuchiShareStorage.inspect(payload, expected: item).mime, "image/png")
  }

  func testPickedFilesStageVerifiedItemsAndDiscardAllCopies() async throws {
    let groupRoot = temporaryRoot.appendingPathComponent("unused-group", isDirectory: true)
    let hostRoot = temporaryRoot.appendingPathComponent("host", isDirectory: true)
    try SuchiShareStorage.createProtectedDirectory(groupRoot)
    let channel = ShareChannel(appGroupRoot: groupRoot, hostRoot: hostRoot)
    let valid = temporaryRoot.appendingPathComponent("real.png")
    let spoofed = temporaryRoot.appendingPathComponent("not-an-image.png")
    try validPNG().write(to: valid)
    try Data("%PDF-1.7\n".utf8).write(to: spoofed)
    let batchId = UUID().uuidString.lowercased()

    try await channel.stagePickedDocuments([valid, spoofed], batchId: batchId)
    let directory = hostRoot.appendingPathComponent(batchId, isDirectory: true)
    let manifest = try SuchiShareStorage.readManifest(in: directory)
    XCTAssertTrue(manifest.complete)
    XCTAssertEqual(manifest.inputCount, 2)
    XCTAssertEqual(manifest.rejectedIndices, [1])
    XCTAssertEqual(manifest.items.map(\.index), [0])
    XCTAssertEqual(manifest.items.first?.mime, "image/png")
    let pending = try XCTUnwrap(channel.importPendingBatches().first)
    XCTAssertEqual(pending["batch_id"] as? String, batchId)
    XCTAssertEqual(pending["rejected_count"] as? Int, 1)
    let items = try XCTUnwrap(pending["items"] as? [[String: Any]])
    let retained = URL(fileURLWithPath: try XCTUnwrap(items.first?["path"] as? String))
    XCTAssertEqual(try Data(contentsOf: retained), validPNG())
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("item-001.payload").path
    ))

    try channel.discardBatch(batchId)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    XCTAssertTrue(try channel.importPendingBatches().isEmpty)
  }

  func testInterruptedPickedBatchRecoversVerifiedItemAndRejectsMissingInput() throws {
    let groupRoot = temporaryRoot.appendingPathComponent("unused-group", isDirectory: true)
    let hostRoot = temporaryRoot.appendingPathComponent("host", isDirectory: true)
    try SuchiShareStorage.createProtectedDirectory(groupRoot)
    try SuchiShareStorage.createProtectedDirectory(hostRoot)
    let channel = ShareChannel(appGroupRoot: groupRoot, hostRoot: hostRoot)
    let batchId = UUID().uuidString.lowercased()
    let directory = hostRoot.appendingPathComponent(batchId, isDirectory: true)
    try SuchiShareStorage.createProtectedDirectory(directory)
    let source = temporaryRoot.appendingPathComponent("picked.png")
    try validPNG().write(to: source)
    let payload = directory.appendingPathComponent("item-000.payload")
    let inspected = try SuchiShareStorage.copyAndInspect(from: source, to: payload)
    let manifest = SuchiShareManifest(
      version: SuchiShareConstants.manifestVersion,
      batchId: batchId,
      createdAt: Int64(Date().timeIntervalSince1970 * 1_000),
      inputCount: 2,
      rejectedCount: 0,
      rejectedIndices: [],
      complete: false,
      items: [SuchiShareItem(
        index: 0,
        path: payload.lastPathComponent,
        mime: inspected.mime,
        name: "picked.png",
        size: inspected.size,
        sha256: inspected.sha256
      )]
    )
    try SuchiShareStorage.atomicWrite(manifest, in: directory)

    XCTAssertTrue(try channel.importPendingBatches(excluding: batchId).isEmpty)
    XCTAssertFalse(try SuchiShareStorage.readManifest(in: directory).complete)
    let recovered = try XCTUnwrap(channel.importPendingBatches().first)
    XCTAssertEqual(recovered["rejected_count"] as? Int, 1)
    XCTAssertTrue(try XCTUnwrap(recovered["complete"] as? Bool))
    XCTAssertEqual(try SuchiShareStorage.readManifest(in: directory).rejectedIndices, [1])
    XCTAssertEqual(try Data(contentsOf: payload), validPNG())
  }

  func testEmptyPickerSelectionDoesNotCreateBatch() async throws {
    let groupRoot = temporaryRoot.appendingPathComponent("unused-group", isDirectory: true)
    let hostRoot = temporaryRoot.appendingPathComponent("host", isDirectory: true)
    let channel = ShareChannel(appGroupRoot: groupRoot, hostRoot: hostRoot)
    let batchId = UUID().uuidString.lowercased()
    do {
      try await channel.stagePickedDocuments([], batchId: batchId)
      XCTFail("Empty selection should not be staged")
    } catch SuchiShareStorageError.invalidBatch {
      XCTAssertFalse(FileManager.default.fileExists(atPath: hostRoot.path))
    }
  }

  func testPickerRejectsOverTwentyFilesBeforeCreatingBatch() async throws {
    let hostRoot = temporaryRoot.appendingPathComponent("host", isDirectory: true)
    let channel = ShareChannel(hostRoot: hostRoot)
    let source = temporaryRoot.appendingPathComponent("picked.png")
    try validPNG().write(to: source)
    let batchId = UUID().uuidString.lowercased()
    do {
      try await channel.stagePickedDocuments(
        Array(repeating: source, count: SuchiShareConstants.maximumItems + 1),
        batchId: batchId
      )
      XCTFail("Selection beyond the native intake limit must fail")
    } catch SuchiShareStorageError.invalidBatch {
      XCTAssertFalse(FileManager.default.fileExists(atPath: hostRoot.path))
    }
  }

  func testAppGroupBatchImportsVerifiedBytesAndInterruptedReceipts() throws {
    let batchId = UUID().uuidString.lowercased()
    let groupRoot = temporaryRoot.appendingPathComponent("app-group", isDirectory: true)
    let hostRoot = temporaryRoot.appendingPathComponent("host", isDirectory: true)
    try SuchiShareStorage.createProtectedDirectory(groupRoot)
    try SuchiShareStorage.createProtectedDirectory(hostRoot)
    let groupBatch = try SuchiShareStorage.directChild(named: batchId, of: groupRoot)
    try SuchiShareStorage.createProtectedDirectory(groupBatch)
    let source = temporaryRoot.appendingPathComponent("handoff.png")
    try validPNG().write(to: source)
    let payload = groupBatch.appendingPathComponent("item-000.payload")
    let inspected = try SuchiShareStorage.copyAndInspect(from: source, to: payload)
    let item = SuchiShareItem(
      index: 0,
      path: payload.lastPathComponent,
      mime: inspected.mime,
      name: "shared.png",
      size: inspected.size,
      sha256: inspected.sha256
    )
    let manifest = SuchiShareManifest(
      version: SuchiShareConstants.manifestVersion,
      batchId: batchId,
      createdAt: Int64(Date().timeIntervalSince1970 * 1_000),
      inputCount: 2,
      rejectedCount: 0,
      rejectedIndices: [],
      complete: false,
      items: [item]
    )
    try SuchiShareStorage.atomicWrite(manifest, in: groupBatch)

    let batches = try ShareChannel(
      appGroupRoot: groupRoot,
      hostRoot: hostRoot
    ).importPendingBatches()
    let imported = try XCTUnwrap(
      batches.first { $0["batch_id"] as? String == batchId }
    )
    let importedItems = try XCTUnwrap(imported["items"] as? [[String: Any]])
    let importedItem = try XCTUnwrap(importedItems.first)
    let importedPath = try XCTUnwrap(importedItem["path"] as? String)
    XCTAssertEqual(
      URL(fileURLWithPath: importedPath).deletingLastPathComponent(),
      hostRoot.appendingPathComponent(batchId, isDirectory: true)
    )

    XCTAssertEqual(importedItems.count, 1)
    XCTAssertEqual(importedItem["sha256"] as? String, inspected.sha256)
    XCTAssertEqual(imported["rejected_count"] as? Int, 1)
    XCTAssertEqual(imported["complete"] as? Bool, true)
    XCTAssertFalse(FileManager.default.fileExists(atPath: groupBatch.path))
  }

  func testCorruptAppGroupBatchBecomesTerminalRejection() throws {
    let batchId = UUID().uuidString.lowercased()
    let groupRoot = temporaryRoot.appendingPathComponent("app-group", isDirectory: true)
    let hostRoot = temporaryRoot.appendingPathComponent("host", isDirectory: true)
    try SuchiShareStorage.createProtectedDirectory(groupRoot)
    try SuchiShareStorage.createProtectedDirectory(hostRoot)
    let groupBatch = try SuchiShareStorage.directChild(named: batchId, of: groupRoot)
    try SuchiShareStorage.createProtectedDirectory(groupBatch)
    try Data("{not-json".utf8).write(
      to: groupBatch.appendingPathComponent("manifest.json")
    )

    let batches = try ShareChannel(
      appGroupRoot: groupRoot,
      hostRoot: hostRoot
    ).importPendingBatches()
    let rejected = try XCTUnwrap(
      batches.first { $0["batch_id"] as? String == batchId }
    )

    XCTAssertEqual(rejected["complete"] as? Bool, true)
    XCTAssertEqual(rejected["rejected_count"] as? Int, 1)
    XCTAssertTrue(try XCTUnwrap(rejected["items"] as? [[String: Any]]).isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: groupBatch.path))
  }

  func testPayloadTypeCannotSpoofManifestMime() throws {
    let source = temporaryRoot.appendingPathComponent("source.pdf")
    try Data("%PDF-1.7\n".utf8).write(to: source)
    let inspected = try SuchiShareStorage.inspect(source)
    let falseReceipt = SuchiShareItem(
      index: 0,
      path: "item-000.payload",
      mime: "image/png",
      name: "shared.png",
      size: inspected.size,
      sha256: inspected.sha256
    )

    XCTAssertThrowsError(try SuchiShareStorage.inspect(source, expected: falseReceipt))
  }

  func testHEIFSignatureRejectsAVIFCompatibilityBrand() throws {
    let heic = temporaryRoot.appendingPathComponent("source.heic")
    try isoBaseMediaFile(majorBrand: "mif1", compatibleBrand: "heic").write(to: heic)
    XCTAssertEqual(try SuchiShareStorage.inspect(heic).mime, "image/heic")

    let avif = temporaryRoot.appendingPathComponent("source.avif")
    try isoBaseMediaFile(majorBrand: "mif1", compatibleBrand: "avif").write(to: avif)
    XCTAssertThrowsError(try SuchiShareStorage.inspect(avif))
  }

  func testManifestRejectsTraversalAndOverlappingReceipts() {
    let manifest = SuchiShareManifest(
      version: SuchiShareConstants.manifestVersion,
      batchId: "c4652f32-b979-4fc0-adbe-1d761beb2209",
      createdAt: 2_000,
      inputCount: 1,
      rejectedCount: 1,
      rejectedIndices: [0],
      complete: true,
      items: [
        SuchiShareItem(
          index: 0,
          path: "../payload.png",
          mime: "image/png",
          name: "shared.png",
          size: 8,
          sha256: String(repeating: "a", count: 64)
        )
      ]
    )

    XCTAssertThrowsError(try SuchiShareStorage.validate(manifest))
  }

  func testManifestRejectsUnknownFields() throws {
    let batchId = "c4652f32-b979-4fc0-adbe-1d761beb2209"
    let batch = temporaryRoot.appendingPathComponent(batchId, isDirectory: true)
    try SuchiShareStorage.createProtectedDirectory(batch)
    let json = """
      {"version":1,"batch_id":"\(batchId)","created_at":2000,"input_count":1,"rejected_count":1,"rejected_indices":[0],"complete":true,"items":[],"unexpected":true}
      """
    try Data(json.utf8).write(to: batch.appendingPathComponent("manifest.json"))

    XCTAssertThrowsError(try SuchiShareStorage.readManifest(in: batch))
  }

  func testSharedFilenameIsBoundedByUTF8Bytes() {
    let name = SuchiShareStorage.sanitizedName(
      String(repeating: "文", count: 200) + ".pdf",
      mime: "application/pdf",
      index: 0
    )

    XCTAssertLessThanOrEqual(name.utf8.count, 255)
    XCTAssertTrue(name.hasSuffix(".pdf"))
  }

  func testBatchIdsMustBeCanonicalVersionFourUUIDs() {
    XCTAssertTrue(
      SuchiShareStorage.isCanonicalVersionFourUUID(
        "c4652f32-b979-4fc0-adbe-1d761beb2209"
      )
    )
    XCTAssertFalse(
      SuchiShareStorage.isCanonicalVersionFourUUID(
        "C4652F32-B979-4FC0-ADBE-1D761BEB2209"
      )
    )
    XCTAssertFalse(
      SuchiShareStorage.isCanonicalVersionFourUUID(
        "c4652f32-b979-1fc0-adbe-1d761beb2209"
      )
    )
  }

  func testScanResultPayloadPreservesPageOrderAndCancellation() throws {
    let first = temporaryRoot.appendingPathComponent("page-000.jpg")
    let second = temporaryRoot.appendingPathComponent("page-001.jpg")
    let completed = ScanResultPayload.completed(pageURLs: [first, second])
    let pages = try XCTUnwrap(completed["pages"] as? [[String: String]])

    XCTAssertEqual(completed["cancelled"] as? Bool, false)
    XCTAssertTrue(completed["pdf_path"] is NSNull)
    XCTAssertEqual(completed["page_count"] as? Int, 2)
    XCTAssertEqual(pages.map { $0["path"] }, [first.path, second.path])

    let cancelled = ScanResultPayload.cancelled
    XCTAssertEqual(cancelled["cancelled"] as? Bool, true)
    XCTAssertEqual(cancelled["page_count"] as? Int, 0)
    XCTAssertTrue(cancelled["pdf_path"] is NSNull)
    XCTAssertTrue(try XCTUnwrap(cancelled["pages"] as? [Any]).isEmpty)
  }

  func testScanCaptureBudgetRejectsOversizedPagesBeforeRetention() throws {
    var budget = ScanCaptureBudget(maximumPageBytes: 4, maximumSourceBytes: 6)

    try budget.addPage(byteCount: 3)
    XCTAssertEqual(budget.retainedBytes, 3)
    XCTAssertThrowsError(try budget.addPage(byteCount: 5))
    XCTAssertEqual(budget.retainedBytes, 3)
    try budget.addPage(byteCount: 3)
    XCTAssertThrowsError(try budget.addPage(byteCount: 1))
  }

  @MainActor
  func testPhotoRetentionKeepsFullFrameAndWritesRecoverableManifest() throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 16), format: format).image { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 32, height: 16))
    }
    let payload = try ScanChannel().retain(pageCount: 1) { _ in image }
    let pages = try XCTUnwrap(payload["pages"] as? [[String: String]])
    let file = URL(fileURLWithPath: try XCTUnwrap(pages.first?["path"]))
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let retained = try XCTUnwrap(UIImage(contentsOfFile: file.path))
    XCTAssertEqual(retained.size, CGSize(width: 32, height: 16))
    XCTAssertEqual(payload["page_count"] as? Int, 1)
    XCTAssertTrue(payload["pdf_path"] is NSNull)
    let manifest = try Data(contentsOf: file.deletingLastPathComponent().appendingPathComponent("manifest.json"))
    let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: manifest) as? [String: Any])
    XCTAssertEqual(decoded["pages"] as? [String], [file.lastPathComponent])
    XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
  }

  func testProviderLoaderPreservesMultipleImageBytesAndDuplicateNames() async throws {
    let payloads = [
      validPNG() + Data([0x01]),
      validPNG() + Data([0x02]),
    ]
    var items: [SuchiShareItem] = []
    for (index, bytes) in payloads.enumerated() {
      let source = temporaryRoot.appendingPathComponent("source-\(index).png")
      try bytes.write(to: source)
      let provider = try XCTUnwrap(NSItemProvider(contentsOf: source))
      provider.suggestedName = "duplicate.png"
      let item = try await SuchiShareProviderLoader.retain(
        provider: provider,
        index: index,
        in: temporaryRoot,
        timeout: 2
      )
      items.append(item)

      let retained = temporaryRoot.appendingPathComponent(item.path)
      XCTAssertEqual(try Data(contentsOf: retained), bytes)
      XCTAssertEqual(item.name, "duplicate.png")
    }

    XCTAssertEqual(items.map(\.index), [0, 1])
    XCTAssertNotEqual(items[0].path, items[1].path)
    XCTAssertNotEqual(items[0].sha256, items[1].sha256)
  }

  func testProviderLoaderTimesOutWithoutLeavingPayload() async throws {
    let provider = NSItemProvider()
    provider.suggestedName = "stalled.png"
    provider.registerFileRepresentation(
      forTypeIdentifier: UTType.png.identifier,
      fileOptions: [],
      visibility: .all
    ) { _ in
      return Progress(totalUnitCount: 1)
    }

    do {
      _ = try await SuchiShareProviderLoader.retain(
        provider: provider,
        index: 0,
        in: temporaryRoot,
        timeout: 0.02
      )
      XCTFail("Expected provider timeout")
    } catch SuchiShareStorageError.providerTimedOut {
      XCTAssertFalse(
        FileManager.default.fileExists(
          atPath: temporaryRoot.appendingPathComponent("item-000.payload").path
        )
      )
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testProviderLoaderRejectsOversizedPayloadWithoutLeavingCopy() async throws {
    let source = temporaryRoot.appendingPathComponent("oversized.png")
    try validPNG().write(to: source)
    let provider = try XCTUnwrap(NSItemProvider(contentsOf: source))

    do {
      _ = try await SuchiShareProviderLoader.retain(
        provider: provider,
        index: 0,
        in: temporaryRoot,
        timeout: 2,
        maximumBytes: 8
      )
      XCTFail("Expected provider size rejection")
    } catch SuchiShareStorageError.itemTooLarge {
      XCTAssertFalse(
        FileManager.default.fileExists(
          atPath: temporaryRoot.appendingPathComponent("item-000.payload").path
        )
      )
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  private func isoBaseMediaFile(
    majorBrand: String,
    compatibleBrand: String
  ) -> Data {
    var data = Data([0x00, 0x00, 0x00, 0x14])
    data.append(Data("ftyp".utf8))
    data.append(Data(majorBrand.utf8))
    data.append(Data([0x00, 0x00, 0x00, 0x00]))
    data.append(Data(compatibleBrand.utf8))
    return data
  }

  private func validPNG() -> Data {
    return Data([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    ])
  }
}

import Foundation
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let statusLabel = UILabel()
  private let detailLabel = UILabel()
  private let doneButton = UIButton(type: .system)
  private var stagingStarted = false
  private var stagingFinished = false

  override func loadView() {
    let root = UIView()
    root.backgroundColor = UIColor(red: 250 / 255, green: 250 / 255, blue: 248 / 255, alpha: 1)

    let titleLabel = UILabel()
    titleLabel.text = "Suchi Companion"
    titleLabel.font = .preferredFont(forTextStyle: .title2)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.numberOfLines = 0
    titleLabel.textColor = UIColor(red: 23 / 255, green: 24 / 255, blue: 26 / 255, alpha: 1)

    statusLabel.text = "Saving shared files…"
    statusLabel.font = .preferredFont(forTextStyle: .headline)
    statusLabel.adjustsFontForContentSizeCategory = true
    statusLabel.numberOfLines = 0
    statusLabel.textColor = titleLabel.textColor

    detailLabel.text = "You can return to the sharing app while Suchi Companion keeps the retained copy."
    detailLabel.font = .preferredFont(forTextStyle: .body)
    detailLabel.adjustsFontForContentSizeCategory = true
    detailLabel.numberOfLines = 0
    detailLabel.textColor = UIColor(red: 106 / 255, green: 112 / 255, blue: 121 / 255, alpha: 1)

    doneButton.configuration = .filled()
    doneButton.configuration?.title = "Done"
    doneButton.configuration?.baseBackgroundColor = UIColor(
      red: 5 / 255,
      green: 117 / 255,
      blue: 182 / 255,
      alpha: 1
    )
    doneButton.configuration?.cornerStyle = .medium
    doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    doneButton.isEnabled = false
    doneButton.accessibilityHint = "Closes the Suchi Companion share extension"
    doneButton.addTarget(self, action: #selector(finish), for: .touchUpInside)

    let progress = UIActivityIndicatorView(style: .medium)
    progress.startAnimating()
    progress.tag = 101

    let statusRow = UIStackView(arrangedSubviews: [progress, statusLabel])
    statusRow.axis = .horizontal
    statusRow.alignment = .center
    statusRow.spacing = 12

    let stack = UIStackView(arrangedSubviews: [titleLabel, statusRow, detailLabel, doneButton])
    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = 20
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(
        equalTo: root.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 28),
      doneButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
    ])
    view = root
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !stagingStarted else { return }
    stagingStarted = true
    let inputItems = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    Task { [weak self] in
      let outcome = await ShareExtensionStager().stage(inputItems: inputItems)
      guard let self else { return }
      self.show(outcome)
    }
  }

  private func show(_ outcome: ShareStagingOutcome) {
    guard !stagingFinished else { return }
    stagingFinished = true
    view.viewWithTag(101)?.removeFromSuperview()
    if outcome.savedCount > 0 {
      statusLabel.text = "Saved to Suchi Companion"
      detailLabel.text =
        "Open or return to Suchi Companion. \(outcome.savedCount) supported item\(outcome.savedCount == 1 ? "" : "s") retained."
      if outcome.rejectedCount > 0 {
        detailLabel.text? +=
          " \(outcome.rejectedCount) unsupported or unavailable item\(outcome.rejectedCount == 1 ? "" : "s") skipped."
      }
    } else if outcome.storageFailed {
      statusLabel.text = "Couldn’t save shared files"
      detailLabel.text =
        "Suchi Companion’s protected staging area is unavailable. Return to the sharing app and try again."
    } else {
      statusLabel.text = "No supported files"
      detailLabel.text = "Share PDF, JPEG, PNG, HEIC, or HEIF files with Suchi Companion."
    }
    doneButton.isEnabled = true
    UIAccessibility.post(notification: .announcement, argument: statusLabel.text)
  }

  @objc private func finish() {
    guard stagingFinished else { return }
    doneButton.isEnabled = false
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}

private struct ShareStagingOutcome {
  let savedCount: Int
  let rejectedCount: Int
  let storageFailed: Bool
}

private final class ShareExtensionStager {
  func stage(inputItems: [NSExtensionItem]) async -> ShareStagingOutcome {
    let providers = inputItems.flatMap { $0.attachments ?? [] }
    let batchId = UUID().uuidString.lowercased()
    let directory: URL
    var manifest: SuchiShareManifest

    do {
      guard let root = try SuchiShareStorage.appGroupRoot(create: true) else {
        throw SuchiShareStorageError.storageUnavailable
      }
      directory = try SuchiShareStorage.directChild(named: batchId, of: root)
      try SuchiShareStorage.createProtectedDirectory(directory)
      var rejected = Array(providers.indices.dropFirst(SuchiShareConstants.maximumItems))
      if providers.isEmpty {
        rejected = [0]
      }
      manifest = SuchiShareManifest(
        version: SuchiShareConstants.manifestVersion,
        batchId: batchId,
        createdAt: Int64(Date().timeIntervalSince1970 * 1_000),
        inputCount: max(1, providers.count),
        rejectedCount: rejected.count,
        rejectedIndices: rejected,
        complete: false,
        items: []
      )
      try SuchiShareStorage.atomicWrite(manifest, in: directory)
    } catch {
      return ShareStagingOutcome(savedCount: 0, rejectedCount: providers.count, storageFailed: true)
    }

    for (index, provider) in providers.prefix(SuchiShareConstants.maximumItems).enumerated() {
      do {
        let item = try await SuchiShareProviderLoader.retain(
          provider: provider,
          index: index,
          in: directory
        )
        manifest.items.append(item)
        manifest.items.sort { $0.index < $1.index }
      } catch SuchiShareStorageError.storageUnavailable {
        return ShareStagingOutcome(
          savedCount: manifest.items.count,
          rejectedCount: manifest.rejectedCount,
          storageFailed: true
        )
      } catch {
        if !manifest.rejectedIndices.contains(index) {
          manifest.rejectedIndices.append(index)
          manifest.rejectedIndices.sort()
        }
      }
      manifest.rejectedCount = manifest.rejectedIndices.count
      do {
        try SuchiShareStorage.atomicWrite(manifest, in: directory)
      } catch {
        return ShareStagingOutcome(
          savedCount: manifest.items.count,
          rejectedCount: manifest.rejectedCount,
          storageFailed: true
        )
      }
    }

    manifest.complete = true
    do {
      try SuchiShareStorage.atomicWrite(manifest, in: directory)
      return ShareStagingOutcome(
        savedCount: manifest.items.count,
        rejectedCount: manifest.rejectedCount,
        storageFailed: false
      )
    } catch {
      return ShareStagingOutcome(
        savedCount: manifest.items.count,
        rejectedCount: manifest.rejectedCount,
        storageFailed: true
      )
    }
  }

}

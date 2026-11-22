import Flutter
import UIKit

struct LayoutRegionSnapshot: Equatable {
  enum Kind: String {
    case division
    case occlusion
  }

  let kind: Kind
  let frame: CGRect

  var dictionary: [String: Any] {
    [
      "kind": kind.rawValue,
      "x": Double(frame.origin.x),
      "y": Double(frame.origin.y),
      "width": Double(frame.size.width),
      "height": Double(frame.size.height),
    ]
  }
}

struct LayoutSnapshot: Equatable {
  enum VerticalBarEdge: String {
    case leading
    case trailing
    case unspecified
  }

  static let empty = LayoutSnapshot(regions: [], verticalBarEdge: .unspecified)

  let regions: [LayoutRegionSnapshot]
  let verticalBarEdge: VerticalBarEdge

  var dictionary: [String: Any] {
    [
      "regions": regions.map(\.dictionary),
      "verticalBarEdge": verticalBarEdge.rawValue,
    ]
  }

  @available(iOS 27.1, *)
  static func verticalBarEdge(from edge: UIVerticalBarEdge) -> VerticalBarEdge {
    switch edge {
    case .leading:
      return .leading
    case .trailing:
      return .trailing
    default:
      return .unspecified
    }
  }
}

final class LayoutSnapshotEmitter {
  private(set) var lastSnapshot: LayoutSnapshot?
  private let send: (LayoutSnapshot) -> Void

  init(send: @escaping (LayoutSnapshot) -> Void) {
    self.send = send
  }

  func publish(_ snapshot: LayoutSnapshot) {
    guard snapshot != lastSnapshot else { return }
    lastSnapshot = snapshot
    send(snapshot)
  }
}

final class LayoutChannel {
  static let channelName = "page.suchi.companion/layout"

  private var channel: FlutterMethodChannel?
  private weak var observerView: LayoutObserverView?
  private var emitter: LayoutSnapshotEmitter?

  func register(registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: registrar.messenger()
    )
    let emitter = LayoutSnapshotEmitter { [weak channel] snapshot in
      channel?.invokeMethod("layoutChanged", arguments: snapshot.dictionary)
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "currentLayout" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.attachObserverIfNeeded(rootView: registrar.viewController?.view)
      result((self?.observerView?.snapshot ?? .empty).dictionary)
    }

    self.channel = channel
    self.emitter = emitter
    attachObserverIfNeeded(rootView: registrar.viewController?.view)
  }

  private func attachObserverIfNeeded(rootView: UIView?) {
    guard observerView == nil else { return }
    guard let rootView else {
      emitter?.publish(.empty)
      return
    }
    let observerView = LayoutObserverView { [weak emitter] snapshot in
      emitter?.publish(snapshot)
    }
    observerView.frame = rootView.bounds
    observerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    rootView.addSubview(observerView)
    self.observerView = observerView
    observerView.refreshSnapshot()
  }
}

private final class LayoutObserverView: UIView {
  private let onSnapshot: (LayoutSnapshot) -> Void
  private(set) var snapshot = LayoutSnapshot.empty

  init(onSnapshot: @escaping (LayoutSnapshot) -> Void) {
    self.onSnapshot = onSnapshot
    super.init(frame: .zero)
    backgroundColor = .clear
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    accessibilityElementsHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  override func updateConstraints() {
    refreshSnapshot()
    super.updateConstraints()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    refreshSnapshot()
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    refreshSnapshot()
  }

  fileprivate func refreshSnapshot() {
    let nextSnapshot: LayoutSnapshot
    if #available(iOS 27.1, *) {
      let divisions = reservedRegions(kind: .division)
        .filter(\.isActive)
        .map { LayoutRegionSnapshot(kind: .division, frame: $0.frame) }
      let occlusions = reservedRegions(kind: .occlusion)
        .filter(\.isActive)
        .map { LayoutRegionSnapshot(kind: .occlusion, frame: $0.frame) }
      nextSnapshot = LayoutSnapshot(
        regions: divisions + occlusions,
        verticalBarEdge: LayoutSnapshot.verticalBarEdge(from: traitCollection.verticalBarEdge)
      )
    } else {
      nextSnapshot = .empty
    }
    guard nextSnapshot != snapshot else { return }
    snapshot = nextSnapshot
    onSnapshot(nextSnapshot)
  }
}

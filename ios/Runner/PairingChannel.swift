import AVFoundation
import Flutter
import UIKit

final class PairingChannel {
  private var channel: FlutterMethodChannel?
  private var pending: FlutterResult?
  private weak var scanner: UIViewController?

  func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "app.suchi.page/pairing", binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "scan_unavailable", message: "Use Paste pairing link to connect.", details: nil))
        return
      }
      if call.method == "deviceName" {
        // iOS 16+ may expose only "iPhone"/"iPad"; the pairing UI lets users edit it.
        result(UIDevice.current.name)
        return
      }
      guard call.method == "scan" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard self.pending == nil else {
        result(FlutterError(code: "scan_busy", message: "A pairing scan is already open.", details: nil))
        return
      }
      self.pending = result
      self.requestCamera()
    }
    self.channel = channel
  }

  private func requestCamera() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      presentScanner()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
        DispatchQueue.main.async {
          if allowed { self?.presentScanner() }
          else { self?.cameraDenied() }
        }
      }
    default:
      cameraDenied()
    }
  }

  private func cameraDenied() {
    finish(nil, error: FlutterError(
      code: "camera_denied",
      message: "Allow camera access in Settings, or use Paste pairing link to connect.",
      details: nil
    ))
  }

  private func presentScanner() {
    guard
      pending != nil,
      let presenter = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .filter({ $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
        .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController,
      presenter.presentedViewController == nil
    else {
      finish(nil, error: FlutterError(code: "scan_unavailable", message: "QR scanning could not open. Use Paste pairing link.", details: nil))
      return
    }
    let camera = PairingScanViewController { [weak self] value, error in
      self?.finish(value, error: error)
    }
    let navigation = UINavigationController(rootViewController: camera)
    navigation.modalPresentationStyle = .fullScreen
    scanner = navigation
    presenter.present(navigation, animated: true)
  }

  private func finish(_ value: String?, error: FlutterError?) {
    guard let result = pending else { return }
    pending = nil
    if let scanner, scanner.presentingViewController != nil {
      scanner.dismiss(animated: true) { result(error ?? value) }
    } else {
      result(error ?? value)
    }
  }
}

private final class PairingScanViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  private let capture = AVCaptureSession()
  private let cameraQueue = DispatchQueue(label: "app.suchi.page.pairing-camera", qos: .userInitiated)
  private var preview: AVCaptureVideoPreviewLayer?
  private var completion: ((String?, FlutterError?) -> Void)?

  init(completion: @escaping (String?, FlutterError?) -> Void) {
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("Use init(completion:)") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Scan Suchi pairing code"
    view.backgroundColor = .black
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .cancel, target: self, action: #selector(cancel)
    )
    let preview = AVCaptureVideoPreviewLayer(session: capture)
    preview.videoGravity = .resizeAspectFill
    view.layer.addSublayer(preview)
    self.preview = preview
    let instructions = UILabel()
    instructions.text = "Point the camera at the pairing QR code in the Suchi web app."
    instructions.numberOfLines = 0
    instructions.font = .preferredFont(forTextStyle: .body)
    instructions.adjustsFontForContentSizeCategory = true
    instructions.textAlignment = .center
    instructions.textColor = .white
    instructions.backgroundColor = UIColor.black.withAlphaComponent(0.75)
    instructions.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(instructions)
    NSLayoutConstraint.activate([
      instructions.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      instructions.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      instructions.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
    ])
    NotificationCenter.default.addObserver(
      self, selector: #selector(cancel), name: UIApplication.didEnterBackgroundNotification, object: nil
    )
    cameraQueue.async { [weak self] in self?.startCamera() }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    preview?.frame = view.bounds
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    NotificationCenter.default.removeObserver(self)
    complete(nil)
  }

  private func startCamera() {
    do {
      try configureCamera()
      capture.startRunning()
    } catch {
      DispatchQueue.main.async { [weak self] in
        self?.complete(nil, error: FlutterError(
          code: "scan_unavailable",
          message: "QR scanning is unavailable on this device. Use Paste pairing link.",
          details: nil
        ))
      }
    }
  }

  private func configureCamera() throws {
    guard let camera = AVCaptureDevice.default(for: .video) else {
      throw CocoaError(.featureUnsupported)
    }
    let input = try AVCaptureDeviceInput(device: camera)
    let output = AVCaptureMetadataOutput()
    capture.beginConfiguration()
    defer { capture.commitConfiguration() }
    guard capture.canAddInput(input) else { throw CocoaError(.featureUnsupported) }
    capture.addInput(input)
    guard capture.canAddOutput(output) else { throw CocoaError(.featureUnsupported) }
    capture.addOutput(output)
    guard output.availableMetadataObjectTypes.contains(.qr) else {
      throw CocoaError(.featureUnsupported)
    }
    output.setMetadataObjectsDelegate(self, queue: .main)
    output.metadataObjectTypes = [.qr]
  }

  func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
    guard let code = objects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
      .first(where: { $0.type == .qr }), let value = code.stringValue else { return }
    if value.isEmpty || value.utf8.count > 4096 {
      complete(nil, error: FlutterError(code: "invalid_pairing_code", message: "This code could not be read. Use Paste pairing link.", details: nil))
    } else {
      complete(value)
    }
  }

  @objc private func cancel() { complete(nil) }

  private func complete(_ value: String?, error: FlutterError? = nil) {
    guard let callback = completion else { return }
    completion = nil
    cameraQueue.async { [capture] in capture.stopRunning() }
    callback(value, error)
  }
}

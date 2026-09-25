import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyCover: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard let window, privacyCover == nil else { return }
    // Blur the live window before iOS captures its switcher snapshot; store no image.
    let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialLight))
    cover.frame = window.bounds
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    let tint = UIView(frame: cover.bounds)
    tint.backgroundColor = UIColor(red: 250 / 255, green: 250 / 255, blue: 248 / 255, alpha: 0.4)
    tint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.contentView.addSubview(tint)
    window.addSubview(cover)
    privacyCover = cover
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}

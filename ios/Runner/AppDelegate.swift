import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Die eigenen Kanäle der App (#644), dieselben Namen wie in Kotlin.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TrailBuddyRunner") {
      BackupExclusion.register(with: registrar.messenger())
      HostRequestCounter.register(with: registrar.messenger())
    }
  }
}

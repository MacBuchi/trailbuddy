import Flutter
import UIKit
import UserNotifications
import flutter_foreground_task
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Die Engine des Dienstes (#644, Fahrt aufzeichnen) bekommt dieselben
    // Plugins wie die App — ohne das fänden Standort, Sensoren und
    // SharedPreferences drüben keinen Kanal, und der Takt maß nichts.
    SwiftFlutterForegroundTaskPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // Die Knöpfe der Mitteilungen unterwegs (#644, Paket 3b) antworten in
    // einer eigenen Engine des Pakets — auch sie braucht die Plugins.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // Mitteilungen und Knöpfe gehen über den App-Delegate an die Plugins.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Die eigenen Kanäle der App (#644), dieselben Namen wie in Kotlin.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TrailBuddyRunner") {
      BackupExclusion.register(with: registrar.messenger())
      HostRequestCounter.register(with: registrar.messenger())
      ScreenAwake.register(with: registrar.messenger())
      // Die Garmin-Uhr (#644 Paket 4): Kanal + Rücksprung aus Garmin Connect.
      GarminBridge.register(with: registrar)
    }
  }
}

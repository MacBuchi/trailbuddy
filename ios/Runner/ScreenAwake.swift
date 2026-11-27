import Flutter
import UIKit

/// Bildschirm an während Fahrt oder Navigation (#445, #644).
///
/// Derselbe Kanal und dieselbe Methode wie in `MainActivity.kt`
/// (`keepOn` mit `on`); auf Android hängt das Flag am Fenster, hier ist es
/// der Leerlauf-Timer der App. iOS hebt ihn von selbst auf, sobald die App
/// in den Hintergrund geht, und setzt ihn beim Zurückkommen wieder.
enum ScreenAwake {
  static let channelName = "de.mcbuchi.trailbuddy/screen"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "keepOn" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
      DispatchQueue.main.async {
        UIApplication.shared.isIdleTimerDisabled = on
        result(nil)
      }
    }
  }
}

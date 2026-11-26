import Flutter
import Foundation

/// Nimmt Ordner und Dateien von der iCloud-Sicherung aus (#644).
///
/// Die Liste kommt aus Dart (`lib/core/backup_exclusions.dart`), dieselbe,
/// die auf Android in `backup_rules.xml` steht — hier steht kein Name.
/// Ordner werden angelegt, damit schon ihr erster Inhalt ausgenommen ist;
/// Dateien nur gekennzeichnet, wenn es sie gibt.
enum BackupExclusion {
  static let channelName = "de.mcbuchi.trailbuddy/backup"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      // Für den Nachweis auf dem Gerät (integration_test): Pfade, die es
      // gibt und die weder selbst noch über einen Ordner darüber
      // ausgenommen sind (ein ausgenommener Ordner nimmt seinen Inhalt mit).
      if call.method == "notExcluded", let paths = call.arguments as? [String] {
        result(paths.filter { FileManager.default.fileExists(atPath: $0) && !isExcluded($0) })
        return
      }
      guard call.method == "exclude",
        let args = call.arguments as? [String: Any]
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let dirs = args["dirs"] as? [String] ?? []
      let files = args["files"] as? [String] ?? []
      do {
        for path in dirs {
          try FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true)
          try exclude(path)
        }
        for path in files where FileManager.default.fileExists(atPath: path) {
          try exclude(path)
        }
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "backup_exclude", message: error.localizedDescription, details: nil))
      }
    }
  }

  private static func isExcluded(_ path: String) -> Bool {
    // Nur bis zum Container der App: Darüber liegt im Simulator der Mac,
    // und dessen Simulator-Ordner sind selbst ausgenommen — die Prüfung
    // sagte sonst immer ja (Gegenprobe 2026-11-26).
    let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
    var url = URL(fileURLWithPath: path).standardizedFileURL
    while url.path.hasPrefix(home) && url.path != home {
      let flag = try? url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        .isExcludedFromBackup
      if flag == true { return true }
      url.deleteLastPathComponent()
    }
    return false
  }

  private static func exclude(_ path: String) throws {
    var url = URL(fileURLWithPath: path)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }
}

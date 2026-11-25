import Flutter
import Foundation

/// Zählt, was MapLibre an den Kartenhost schickt (#596 H7, #644) — das
/// Gegenstück zu `HostRequestCounter.kt`, derselbe Kanal, dieselbe
/// Antwort (je Pfad eine Zahl; eingeteilt wird in Dart,
/// `hostRequestKindOfPath`). Die Dart-Seite zählt ihre eigenen Abrufe
/// selbst; Karte und Wege lädt MapLibre Native über seine eigene
/// `URLSession`, und dorthin sieht Dart nicht.
///
/// Eingehängt nur auf Wunsch der Dart-Seite (`install`, aus `main()` im
/// Debug-Build, `installNativeHostCounter`) — iOS hat keine Dev-App wie
/// Android, und die Entscheidung steht so im gemeinsamen Code. Gezählt wird, was wirklich ans Netz geht: Was MapLibre aus
/// seinem Zwischenspeicher bedient, kommt hier nicht an.
enum HostRequestCounter {
  static let channelName = "de.mcbuchi.trailbuddy/host_requests"
  static let host = "tiles.mcbuchi.de"
  /// Höchstens so viele verschiedene Pfade, wie in Kotlin.
  static let maxPaths = 2000

  /// Ob [install] MapLibres Sitzung erreicht hat — der Kanal sagt es
  /// (`installed`), damit „0 gezählt" nicht „nicht eingehängt" heißen kann.
  private(set) static var installed = false

  private static let lock = NSLock()
  private static var counts: [String: Int] = [:]

  static func record(_ url: URL) {
    guard url.host == host else { return }
    lock.lock()
    defer { lock.unlock() }
    let key = counts[url.path] != nil || counts.count < maxPaths ? url.path : "…"
    counts[key, default: 0] += 1
  }

  static func snapshot() -> [String: Int] {
    lock.lock()
    defer { lock.unlock() }
    return counts
  }

  static func reset() {
    lock.lock()
    counts.removeAll()
    lock.unlock()
  }

  /// Hängt [CountingURLProtocol] in MapLibres Sitzung. Muss laufen,
  /// bevor die erste Karte etwas lädt (MapLibre legt seine Sitzung erst
  /// mit der ersten Anfrage an). Über die Laufzeit, weil der Runner
  /// das Modul `MapLibre` nicht selbst einbindet (es kommt über das
  /// Plugin-Paket); fehlt die Klasse, zählt eben nur Dart.
  static func install() {
    if installed { return }
    guard let type = NSClassFromString("MLNNetworkConfiguration") as? NSObject.Type,
      type.responds(to: NSSelectorFromString("sharedManager")),
      let manager = type.perform(NSSelectorFromString("sharedManager"))?
        .takeUnretainedValue() as? NSObject
    else { return }
    let config =
      (manager.value(forKey: "sessionConfiguration") as? URLSessionConfiguration)
      ?? URLSessionConfiguration.default
    config.protocolClasses = [CountingURLProtocol.self] + (config.protocolClasses ?? [])
    manager.setValue(config, forKey: "sessionConfiguration")
    installed = true
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "counts": result(snapshot())
      case "install":
        install()
        result(installed)
      case "installed": result(installed)
      case "reset":
        reset()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Zählt eine Anfrage an den Kartenhost und reicht sie unverändert
/// weiter (über die geteilte Sitzung, die diese Klasse nicht kennt).
final class CountingURLProtocol: URLProtocol {
  private var forward: URLSessionDataTask?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == HostRequestCounter.host
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    if let url = request.url { HostRequestCounter.record(url) }
    forward = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let self else { return }
      if let error {
        self.client?.urlProtocol(self, didFailWithError: error)
        return
      }
      if let response {
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      }
      if let data { self.client?.urlProtocol(self, didLoad: data) }
      self.client?.urlProtocolDidFinishLoading(self)
    }
    forward?.resume()
  }

  override func stopLoading() {
    forward?.cancel()
  }
}

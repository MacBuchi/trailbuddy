import ConnectIQ
import Flutter
import UIKit

/// Die Garmin-Uhr auf dem iPhone (#644 Paket 4, docs/konzept-garmin.md §3):
/// Garmins Connect-IQ-SDK für iOS hinter DEMSELBEN Kanal und Vertrag wie
/// `GarminBridge.kt` — `status`, `open`, `send`, `listen`, zurück `message`
/// und `device`. Die Ergebnisse tragen die Namen des Android-SDK
/// (`SUCCESS`, `FAILURE_TIMEOUT`, `PROMPT_SHOWN_ON_DEVICE` …), damit die
/// Dart-Seite eine bleibt; `ios_support_test` hält beide zusammen.
///
/// Anders als auf Android spricht das SDK selbst per Bluetooth LE mit der
/// Uhr. Garmin Connect braucht es nur für die WAHL der Uhr: `pick` öffnet
/// Garmin Connect, das mit der Liste über unser Schema [urlScheme]
/// zurückspringt (Flutters Szenen-Rückruf `scene(_:openURLContexts:)` über
/// `addSceneDelegate`, beim Kaltstart `willConnectTo`). Die gewählte Uhr merkt sich
/// die App selbst (ohne Sicherung); ohne gewählte Uhr startet das SDK gar
/// nicht — kein Bluetooth vor „Uhr verbinden" (wie `listen` erst mit
/// `watchSeen` auf Android, #484).
///
/// Kein Test-Netz für Swift; die Dart-Seite hat eines (Fake-Brücke). Ob es
/// baut, sagt der Simulator-Build; ob es spricht, nur die Uhr.
final class GarminBridge: NSObject, IQDeviceEventDelegate, IQAppMessageDelegate,
  IQUIOverrideDelegate, FlutterSceneLifeCycleDelegate
{
  static let channelName = "de.mcbuchi.trailbuddy/garmin"

  /// Rücksprung aus Garmin Connect — NICHT das Schema der Anmeldung.
  static let urlScheme = "trailbuddy-ciq"

  /// Garmin Connect auf dem Telefon (`LSApplicationQueriesSchemes`).
  static let connectScheme = "gcm-ciq"

  /// So lange wartet ein Stück auf seine Bestätigung (wie Kotlin).
  static let ackTimeout: TimeInterval = 20

  /// So lange wartet `open`, dann `TIMEOUT` (wie Kotlin).
  static let openTimeout: TimeInterval = 10

  /// Nach dem Start des SDK verbindet es die Uhr erst — so lange warten
  /// `status` und `listen` darauf.
  static let connectWait: TimeInterval = 6

  /// Antwortet die Uhr nicht, ob unsere App darauf liegt: „unbekannt"
  /// (wie Kotlin nach 3 s).
  static let appInfoWait: TimeInterval = 3

  /// Nur in der Engine der App (wie Kotlin in `MainActivity`): Die Engine
  /// des Dienstes bekommt nur die Plugins aus `pubspec.yaml`.
  static func register(with registrar: FlutterPluginRegistrar) {
    let bridge = GarminBridge(
      channel: FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger()))
    registrar.addSceneDelegate(bridge)
    retained = bridge
  }

  private static var retained: GarminBridge?

  /// Nimmt die Adressen mit unserem Schema; die übrigen (Anmeldung) gehen
  /// weiter an die anderen Plugins.
  private func takeOurs(_ contexts: Set<UIOpenURLContext>) -> Bool {
    let ours = contexts.map(\.url).filter { $0.scheme?.lowercased() == Self.urlScheme }
    ours.forEach(take)
    return !ours.isEmpty
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    takeOurs(URLContexts)
  }

  /// Kaltstart aus Garmin Connect (das iPhone hat die App im Hintergrund
  /// beendet): Die Adresse kommt mit der Verbindung der Szene. `false`,
  /// damit die Szene für die anderen weiter eingerichtet wird.
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    if let contexts = connectionOptions?.urlContexts { _ = takeOurs(contexts) }
    return false
  }

  private let channel: FlutterMethodChannel
  private var started = false
  private var appUuid: UUID?
  private var device: IQDevice?
  private var listeningTo: UUID?
  private var connectWaiters: [(Bool) -> Void] = []

  /// Ein `send` nach dem anderen (wie Kotlin): Zwei Folgen zugleich
  /// mischten ihre Stücke.
  private var sends: [([Any], FlutterResult)] = []
  private var sending = false

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    device = Self.loadDevice()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "status":
      guard let id = args?["appId"] as? String, setApp(id) else {
        result(FlutterError(code: "no_app", message: "appId fehlt", details: nil))
        return
      }
      status(result)
    case "listen":
      guard let id = args?["appId"] as? String, setApp(id) else {
        result(FlutterError(code: "no_app", message: "appId fehlt", details: nil))
        return
      }
      listenOnly(result)
    case "open":
      open(result)
    case "send":
      send(args?["messages"] as? [Any] ?? [], result)
    case "pick":
      pick(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Status, Wahl, Lauschen

  /// `BC6A9EE0…` aus `garmin/manifest.xml` → UUID mit Bindestrichen.
  private func setApp(_ id: String) -> Bool {
    guard appUuid == nil else { return true }
    let hex = id.replacingOccurrences(of: "-", with: "")
    guard hex.count == 32 else { return false }
    var s = hex
    for i in [8, 13, 18, 23] {
      s.insert("-", at: s.index(s.startIndex, offsetBy: i))
    }
    appUuid = UUID(uuidString: s)
    return appUuid != nil
  }

  private func connectInstalled() -> Bool {
    guard let url = URL(string: "\(Self.connectScheme)://") else { return false }
    return UIApplication.shared.canOpenURL(url)
  }

  /// `{connect, device, app}` wie Kotlin; dazu `pick: true`, solange keine
  /// erreichbare Uhr gewählt ist — dann steht „Uhr verbinden" statt des
  /// Schalters. Ohne gewählte Uhr startet hier nichts.
  private func status(_ result: @escaping FlutterResult) {
    guard connectInstalled() else {
      result(["connect": false])
      return
    }
    guard let device = device else {
      result(["connect": true, "pick": true])
      return
    }
    startSdk()
    listen(device)
    whenConnected { [weak self] connected in
      guard let self = self else { return }
      guard connected else {
        result(["connect": true, "pick": true])
        return
      }
      self.appStatus(device, result)
    }
  }

  private func appStatus(_ device: IQDevice, _ result: @escaping FlutterResult) {
    var answered = false
    let name = device.friendlyName ?? device.modelName ?? "Garmin"
    func answer(_ app: String) {
      if answered { return }
      answered = true
      result(["connect": true, "device": name, "app": app])
    }
    guard let app = iqApp(device) else { return answer("unknown") }
    ConnectIQ.sharedInstance().getAppStatus(app) { status in
      DispatchQueue.main.async {
        // nil: getrennt oder keine Antwort — wie eine USB-geladene App auf
        // Android „unbekannt", der Schalter steht trotzdem.
        guard let status = status else { return answer("unknown") }
        answer(status.isInstalled ? "installed" : "not_installed")
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.appInfoWait) {
      answer("unknown")
    }
  }

  /// Nur lauschen (#484): `true`, wenn die gewählte Uhr verbunden ist.
  /// Ohne gewählte Uhr `false`, nichts startet.
  private func listenOnly(_ result: @escaping FlutterResult) {
    guard let device = device else {
      result(false)
      return
    }
    startSdk()
    listen(device)
    whenConnected { result($0) }
  }

  /// Garmin Connect öffnen, dort die Uhr wählen. `true`, wenn Garmin
  /// Connect aufging; die Wahl kommt später als `device: PICKED`.
  private func pick(_ result: @escaping FlutterResult) {
    guard connectInstalled() else {
      result(false)
      return
    }
    startSdk()
    NSLog("TB-GARMIN pick")
    ConnectIQ.sharedInstance().showDeviceSelection()
    result(true)
  }

  /// Die Liste aus Garmin Connect: Es gilt immer nur die letzte (Garmin).
  private func take(_ url: URL) {
    startSdk()
    let devices = ConnectIQ.sharedInstance().parseDeviceSelectionResponse(from: url)
    guard let chosen = devices?.compactMap({ $0 as? IQDevice }).first else {
      NSLog("TB-GARMIN picked none")
      return
    }
    if let old = device, old.uuid != chosen.uuid {
      ConnectIQ.sharedInstance().unregister(forAllDeviceEvents: self)
      ConnectIQ.sharedInstance().unregister(forAllAppMessages: self)
      listeningTo = nil
    }
    device = chosen
    Self.saveDevice(chosen)
    NSLog("TB-GARMIN picked %@", chosen.modelName ?? "?")
    listen(chosen)
    channel.invokeMethod("device", arguments: "PICKED")
  }

  private func startSdk() {
    guard !started else { return }
    started = true
    ConnectIQ.sharedInstance().initialize(withUrlScheme: Self.urlScheme, uiOverrideDelegate: self)
  }

  private func iqApp(_ device: IQDevice) -> IQApp? {
    guard let uuid = appUuid else { return nil }
    // Eine selbst geladene App hat keine Store-Kennung — dieselbe wie die
    // App (Garmins Beispiel macht es so).
    return IQApp(uuid: uuid, store: uuid, device: device)
  }

  /// Auf Verbindung und Nachrichten der Uhr hören, einmal je Uhr.
  private func listen(_ device: IQDevice) {
    guard listeningTo != device.uuid else { return }
    listeningTo = device.uuid
    ConnectIQ.sharedInstance().register(forDeviceEvents: device, delegate: self)
    if let app = iqApp(device) {
      ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: self)
    }
  }

  private func whenConnected(_ then: @escaping (Bool) -> Void) {
    guard let device = device else { return then(false) }
    if ConnectIQ.sharedInstance().getDeviceStatus(device) == .connected {
      return then(true)
    }
    var done = false
    let once: (Bool) -> Void = { ok in
      if done { return }
      done = true
      then(ok)
    }
    connectWaiters.append(once)
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.connectWait) { once(false) }
  }

  // MARK: - Öffnen und Senden

  /// Die Uhr-App öffnen. Namen wie `IQOpenApplicationStatus` auf Android.
  private func open(_ result: @escaping FlutterResult) {
    guard let device = device, let app = iqApp(device) else {
      result("NOT_READY")
      return
    }
    startSdk()
    listen(device)
    var answered = false
    func answer(_ status: String) {
      if answered { return }
      answered = true
      NSLog("TB-GARMIN open %@", status)
      result(status)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.openTimeout) { answer("TIMEOUT") }
    ConnectIQ.sharedInstance().openAppRequest(app) { r in
      DispatchQueue.main.async { answer(Self.openName(r)) }
    }
  }

  private func send(_ messages: [Any], _ result: @escaping FlutterResult) {
    sends.append((messages, result))
    if !sending { nextSend() }
  }

  private func nextSend() {
    guard !sends.isEmpty else {
      sending = false
      return
    }
    sending = true
    let (messages, result) = sends.removeFirst()
    var done = false
    let once: (String, Int) -> Void = { [weak self] status, sent in
      if done { return }
      done = true
      NSLog("TB-GARMIN send %@ after %ld of %ld", status, sent, messages.count)
      result(["status": status, "sent": sent])
      DispatchQueue.main.async { self?.nextSend() }
    }
    guard let device = device, let app = iqApp(device) else {
      return once("NOT_READY", 0)
    }
    startSdk()
    listen(device)
    sendPiece(app, messages, 0, once)
  }

  /// Jede Nachricht wartet auf die Bestätigung der vorigen, höchstens
  /// [ackTimeout]; eine späte Bestätigung danach zählt nicht mehr.
  private func sendPiece(
    _ app: IQApp, _ messages: [Any], _ i: Int, _ finish: @escaping (String, Int) -> Void
  ) {
    guard i < messages.count else { return finish("SUCCESS", i) }
    var settled = false
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.ackTimeout) {
      if settled { return }
      settled = true
      finish("FAILURE_TIMEOUT", i)
    }
    ConnectIQ.sharedInstance().sendMessage(messages[i], to: app, progress: nil) {
      [weak self] r in
      DispatchQueue.main.async {
        if settled { return }
        settled = true
        if r == .success {
          self?.sendPiece(app, messages, i + 1, finish)
        } else {
          finish(Self.sendName(r), i)
        }
      }
    }
  }

  // MARK: - Namen wie auf Android

  /// `IQMessageStatus` des Android-SDK. Zeitüberschreitung, zu viele
  /// Versuche und eine beschäftigte Uhr nimmt die Dart-Seite wieder auf
  /// (`_resumable`).
  static func sendName(_ r: IQSendMessageResult) -> String {
    switch r {
    case .success: return "SUCCESS"
    case .failure_Timeout: return "FAILURE_TIMEOUT"
    case .failure_MaxRetries, .failure_DeviceIsBusy: return "FAILURE_DURING_TRANSFER"
    case .failure_DeviceNotAvailable: return "FAILURE_DEVICE_NOT_CONNECTED"
    case .failure_InsufficientMemory: return "FAILURE_MESSAGE_TOO_LARGE"
    case .failure_UnsupportedType: return "FAILURE_UNSUPPORTED_TYPE"
    case .failure_AppNotFound: return "FAILURE_APP_NOT_FOUND"
    default: return "FAILURE_UNKNOWN"
    }
  }

  /// `IQOpenApplicationStatus` des Android-SDK: Erfolg heißt auf iOS, die
  /// Uhr zeigt die Frage.
  static func openName(_ r: IQSendMessageResult) -> String {
    switch r {
    case .success: return "PROMPT_SHOWN_ON_DEVICE"
    case .failure_AppAlreadyRunning: return "APP_IS_ALREADY_RUNNING"
    case .failure_AppNotFound: return "APP_IS_NOT_INSTALLED"
    case .failure_PromptNotDisplayed: return "PROMPT_NOT_SHOWN_ON_DEVICE"
    case .failure_DeviceNotAvailable: return "FAILURE_DEVICE_NOT_CONNECTED"
    default: return "UNKNOWN_FAILURE"
    }
  }

  /// `IQDeviceStatus` des Android-SDK; Dart hört auf `CONNECTED`.
  static func deviceName(_ s: IQDeviceStatus) -> String {
    switch s {
    case .connected: return "CONNECTED"
    case .notConnected: return "NOT_CONNECTED"
    case .notFound: return "NOT_PAIRED"
    default: return "UNKNOWN"
    }
  }

  // MARK: - Rückrufe des SDK

  func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
    DispatchQueue.main.async {
      NSLog("TB-GARMIN device %@", Self.deviceName(status))
      self.channel.invokeMethod("device", arguments: Self.deviceName(status))
      if status == .connected {
        let waiting = self.connectWaiters
        self.connectWaiters.removeAll()
        waiting.forEach { $0(true) }
      }
    }
  }

  func receivedMessage(_ message: Any!, from app: IQApp!) {
    DispatchQueue.main.async {
      // Nur die Art, nie Inhalt (Kennungen, Koordinaten).
      let kind = (message as? [String: Any])?["t"] as? String ?? "?"
      NSLog("TB-GARMIN receive %@", kind)
      self.channel.invokeMethod("message", arguments: message)
    }
  }

  /// Ohne Garmin Connect fragt `status` gar nicht erst; die Vorgabe des SDK
  /// (ein eigener Dialog) bleibt so aus.
  func needsToInstallConnectMobile() {
    NSLog("TB-GARMIN no Garmin Connect")
  }

  // MARK: - Die gewählte Uhr

  /// `Application Support/garmin/device` — ohne iCloud-Sicherung: Auf einem
  /// neuen Telefon wählt man die Uhr neu.
  private static func deviceFile() -> URL? {
    guard
      let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first
    else { return nil }
    return base.appendingPathComponent("garmin", isDirectory: true)
      .appendingPathComponent("device")
  }

  private static func loadDevice() -> IQDevice? {
    guard let file = deviceFile(), let data = try? Data(contentsOf: file) else { return nil }
    return try? NSKeyedUnarchiver.unarchivedObject(ofClass: IQDevice.self, from: data)
  }

  private static func saveDevice(_ device: IQDevice) {
    guard let file = deviceFile() else { return }
    do {
      var dir = file.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try dir.setResourceValues(values)
      let data = try NSKeyedArchiver.archivedData(
        withRootObject: device, requiringSecureCoding: true)
      try data.write(to: file, options: .atomic)
    } catch {
      NSLog("TB-GARMIN save failed %ld", (error as NSError).code)
    }
  }
}

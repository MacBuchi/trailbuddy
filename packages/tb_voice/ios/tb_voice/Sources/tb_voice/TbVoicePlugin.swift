import AVFoundation
import Flutter
import UIKit

/// Ansagen übers Ohr (#525) auf dem iPhone (#644, Paket 3b): derselbe
/// Kanal und Vertrag wie `TbVoicePlugin.java` — `speak {text, language}`
/// antwortet sofort `true` (leerer Text: `false`), der Satz läuft danach.
/// `AVSpeechSynthesizer` mit der Stimme des Geräts, kein Netz.
///
/// Je Satz holt es die Audio-Sitzung „Ansage, darf leiser machen"
/// (`.voicePrompt`, `.duckOthers`): Musik wird leiser, gesprochene Inhalte
/// anderer Apps pausieren, nichts stoppt. Nach dem letzten Satz gibt es sie
/// frei und sagt den anderen Bescheid — wie der Audio-Fokus
/// `GAIN_TRANSIENT_MAY_DUCK` auf Android.
///
/// Ein Plugin und kein Kanal im Runner: Gesprochen wird in der Engine des
/// Dienstes (`flutter_foreground_task`), und die bekommt nur Plugins.
///
/// `TB-VOICE`-Zeilen im Systemprotokoll sind der Nachweis, ob im
/// Hintergrund gesprochen wird (Sitzung an oder Fehlercode, Beginn und Ende
/// des Satzes). Am Gerät braucht es dafür `UIBackgroundModes` `audio`
/// (ios/CLAUDE.md; im Simulator ging es ohne).
public class TbVoicePlugin: NSObject, FlutterPlugin, AVSpeechSynthesizerDelegate {
  static let channelName = "de.mcbuchi.trailbuddy/voice"

  private let synthesizer = AVSpeechSynthesizer()
  private var speaking = 0

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = TbVoicePlugin()
    instance.synthesizer.delegate = instance
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "speak" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let args = call.arguments as? [String: Any]
    let text = (args?["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if text.isEmpty {
      result(false)
      return
    }
    speak(text, language: args?["language"] as? String)
    result(true)
  }

  private func speak(_ text: String, language: String?) {
    let state = Self.appState()
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playback,
        mode: .voicePrompt,
        options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
      )
      try session.setActive(true)
      NSLog("TB-VOICE session active app=%@", state)
    } catch {
      // Im Hintergrund ohne den Modus `audio` wäre das `cannotStartPlaying`
      // ('!pla'); gesprochen wird trotzdem versucht — das Protokoll sagt,
      // ob es klang.
      NSLog("TB-VOICE session error %ld app=%@", (error as NSError).code, state)
    }
    let utterance = AVSpeechUtterance(string: text)
    if let language, let voice = AVSpeechSynthesisVoice(language: language) {
      utterance.voice = voice
    }
    speaking += 1
    synthesizer.speak(utterance)
  }

  private static func appState() -> String {
    switch UIApplication.shared.applicationState {
    case .active: return "active"
    case .inactive: return "inactive"
    case .background: return "background"
    @unknown default: return "unknown"
    }
  }

  public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
    NSLog("TB-VOICE start app=%@", Self.appState())
  }

  public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    NSLog("TB-VOICE done")
    finished()
  }

  public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    NSLog("TB-VOICE cancel")
    finished()
  }

  private func finished() {
    speaking = max(0, speaking - 1)
    guard speaking == 0 else { return }
    // `setActive(false)` kann blockieren — nicht auf dem Haupt-Thread.
    DispatchQueue.global(qos: .utility).async {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }
}

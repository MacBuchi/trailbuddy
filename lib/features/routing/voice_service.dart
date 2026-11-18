// Ansagen übers Ohr im Dienst (#525): Was `voice_cues.dart` rein
// entscheidet, spricht hier die Stimme des Geräts — im Isolate des
// Foreground-Service, damit es auch mit ausgeschaltetem Bildschirm und
// weggewischter App spricht. Kein neuer Host (A6), geht ohne Netz (A8):
// Android `TextToSpeech` mit der Stimme auf dem Gerät, über das eigene
// Plugin `packages/tb_voice` (Java; flutter_tts baut unter AGP 9 nicht).
// Der Ton holt sich den Audio-Fokus „darf leiser machen": Musik wird
// leiser, sie stoppt nicht.
//
// Wie alles im Dienst: kein Riverpod, wirft nie.
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/settings.dart' show kVoiceCuesSettingKey;
import '../../l10n/l10n.dart';
import '../rides/ride_store.dart' show FileRideStore;
import '../rides/ride_task_handler.dart' show kRideDataStartedAt, kRideDataUid;
import '../garmin/watch_buddies.dart' show encodeVoiceWatch;
import '../rides/ride_track.dart' show RidePoint;
import 'voice_cues.dart';

/// Die Trails der freien Fahrt (F7) — die App legt sie ab, der Dienst liest.
const kVoiceTrailsFileName = 'voice_trails.json';

File voiceTrailsFile(String baseDir) =>
    File('$baseDir/${FileRideStore.dirName}/$kVoiceTrailsFileName');

/// Spricht einen Satz; die Naht für den Test.
typedef VoiceSpeak = Future<void> Function(String text, Locale locale);

/// Sind die Ansagen an? Direkt aus den SharedPreferences — `serviceTick`
/// hat sie mit `refreshServiceLocale` eben neu gelesen. Wirft nie.
Future<bool> readServiceVoiceOn() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kVoiceCuesSettingKey) ?? false;
  } catch (_) {
    return false;
  }
}

/// Der Kanal des Plugins `tb_voice` — derselbe Name wie
/// `TbVoicePlugin.CHANNEL` (`test/android_manifest_test.dart`).
const kVoiceChannel = MethodChannel('de.mcbuchi.trailbuddy/voice');

/// Die Sprache der Stimme zur Sprache der App.
String voiceLanguageTag(Locale locale) =>
    locale.languageCode == 'de' ? 'de-DE' : 'en-GB';

/// Die Stimme des Geräts. Fehlt sie oder die Sprache, bleibt es still —
/// die Benachrichtigung zeigt dasselbe. Das Plugin wartet nicht auf das
/// Ende des Satzes; der Takt läuft weiter.
Future<void> speakVoice(String text, Locale locale) async {
  try {
    await kVoiceChannel.invokeMethod<bool>('speak', {
      'text': text,
      'language': voiceLanguageTag(locale),
    });
  } catch (_) {
    // Ohne Stimme (oder im Web, ohne Plugin) keine Ansage; die Fahrt läuft weiter.
  }
}

/// Spricht [cues] als einen Satz in der Sprache des Dienstes.
///
/// Dieselben Momente gehen an die Uhr (#525: kurz vibrieren, Schild und
/// Name) — über die App, denn die Brücke zur Uhr lebt dort ([toApp];
/// ist die App zu, verwirft der Kanal still, und mit ihr fehlt die Uhr).
Future<void> speakCues(
  List<VoiceCue> cues, {
  VoiceSpeak? speak,
  DateTime? now,
  void Function(Object data)? toApp,
}) async {
  if (cues.isEmpty) return;
  final watch = encodeVoiceWatch(cues);
  if (watch != null) {
    try {
      (toApp ?? FlutterForegroundTask.sendDataToMain)(watch);
    } catch (_) {
      // Die Uhr ist ein Zusatz; gesprochen wird trotzdem.
    }
  }
  final l = serviceL10n();
  final text = voiceCuesText(l, cues, now: now ?? DateTime.now());
  if (text.trim().isEmpty) return;
  await (speak ?? speakVoice)(text, Locale(l.localeName));
}

/// Der Wächter der freien Fahrt — einer je Fahrt in diesem Isolate.
class _FreeVoice {
  _FreeVoice({required this.uid, required this.startedAt, required this.selfId})
    : watcher = FreeVoiceWatcher(selfId: selfId);

  final String uid;
  final String startedAt;
  final String? selfId;
  final FreeVoiceWatcher watcher;
  DateTime? version;
  List<VoiceTrail> trails = const [];
}

_FreeVoice? _free;

/// Ein Takt der freien Fahrt (F7): ohne Navigation, mit Aufzeichnung —
/// wer in einen bekannten Trail einfährt, hört Name und Grad. Wirft nie.
Future<void> freeVoiceTick(
  RidePoint point, {
  required String dir,
  VoiceSpeak? speak,
  DateTime Function()? now,
}) async {
  try {
    final uid = await FlutterForegroundTask.getData<String>(key: kRideDataUid);
    final started = await FlutterForegroundTask.getData<String>(
      key: kRideDataStartedAt,
    );
    if (uid == null || started == null) return;
    final current = _free;
    final free =
        current != null && current.uid == uid && current.startedAt == started
        ? current
        : _free = _FreeVoice(uid: uid, startedAt: started, selfId: uid);
    final file = voiceTrailsFile(dir);
    final modified = await file.exists() ? await file.lastModified() : null;
    if (modified != free.version) {
      free.version = modified;
      free.trails = modified == null
          ? const []
          : decodeVoiceTrails(await file.readAsString(), uid: uid);
    }
    final at = (now ?? DateTime.now)();
    final cue = free.watcher.update(point, free.trails, now: at);
    if (cue != null) await speakCues([cue], speak: speak, now: at);
  } catch (_) {
    // Die Ansage ist ein Zusatz.
  }
}

/// Vergisst den Stand — für Tests.
void resetFreeVoice() => _free = null;

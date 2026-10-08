// Die laufende Fahrt (#28): Zustand, Takt, Foreground-Service.
//
// Der Zustand ist die AUFGEZEICHNETE Fahrt selbst (`RecordedRide?`) und
// kein eigenes Statusobjekt: „läuft" heißt genau „es liegt eine Fahrt
// auf der Platte, die noch nicht abgeschlossen ist". Zwei Wahrheiten —
// eine im Speicher, eine auf der Platte — liefen beim ersten
// Prozess-Kill auseinander, und der ist hier der Normalfall.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/errors.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../routing/route_profile.dart';
import '../trails/trail_providers.dart';
import 'ride_confirm.dart';
import 'ride_import.dart';
import 'ride_service.dart';
import 'ride_store.dart';
import 'ride_task_handler.dart';
import 'ride_track.dart';

/// Gibt es die Aufzeichnung auf dieser Plattform? Im Browser nicht: Dort
/// gibt es kein Service-Isolate, und ein Tab im Hintergrund bekommt
/// keine Positionen — eine Fahrt, die nur läuft, solange man hinsieht,
/// wäre keine. Als Provider, damit ein Test beide Fälle sehen kann.
final rideRecordingAvailableProvider = Provider<bool>((ref) => !kIsWeb);

/// Der Mess-Takt. 5 s: Bei 20 km/h sind das 28 m zwischen zwei Punkten
/// — für Kehren knapp, aber der Korridor des Abgleichs ist 15 m breit
/// und die Vereinfachung vor dem Beisteuern (3 m) dünnt ohnehin aus. Ein
/// engerer Takt kostet Akku, ohne dass der Abgleich davon hätte.
const kRideTickInterval = Duration(seconds: 5);

/// Nach dieser Zeit hört eine Fahrt von selbst auf aufzuzeichnen. Wer
/// das Beenden vergisst, hätte sonst GPS bis zum leeren Akku — und
/// morgen eine Fahrt quer durchs Wohnzimmer. Die Fahrt bleibt offen und
/// abschließbar, sie wächst nur nicht weiter.
const kRideMaxDuration = Duration(hours: 12);

/// Woher ein einzelner Fix kommt. Test-Naht: Ohne sie ginge jeder
/// Flow-Test, der eine Fahrt startet, an echtes Plattform-IO.
typedef RideFix = Future<RidePoint?> Function();

final rideFixProvider = Provider<RideFix>((ref) => _platformFix);

/// Darf aufgezeichnet werden? `null` heißt ja, sonst der Grund. Die
/// EINE Stelle neben „Meine Position", die nach der Standortberechtigung
/// fragt — nach einem Tipp, nie beim Start.
typedef RidePermissionCheck = Future<RideStartResult?> Function();

final ridePermissionProvider = Provider<RidePermissionCheck>((ref) => _platformPermission);

Future<RideStartResult?> _platformPermission() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return RideStartResult.noService;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return RideStartResult.noPermission;
    }
    return null;
  } catch (e, stackTrace) {
    logError('Fahrt: Standort prüfen', e, stackTrace);
    return RideStartResult.failed;
  }
}

Future<RidePoint?> _platformFix() async {
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 20)),
    );
    return RidePoint(
        lat: p.latitude,
        lng: p.longitude,
        at: p.timestamp.toUtc(),
        accuracyM: p.accuracy,
        altM: p.altitude);
  } catch (_) {
    return null;
  }
}

final rideStoreProvider = Provider<RideStore>((ref) => FileRideStore());

/// Die Brücke zum Service-Isolate: scharf schalten und entschärfen.
/// Eigene Naht, weil dahinter `path_provider` und SharedPreferences
/// stecken — im Widget-Test gibt es beide nicht.
abstract interface class RideServiceBridge {
  Future<void> arm({required String uid, required DateTime startedAt});
  Future<void> disarm();
}

class PlatformRideServiceBridge implements RideServiceBridge {
  const PlatformRideServiceBridge();

  @override
  Future<void> arm({required String uid, required DateTime startedAt}) async {
    // Der Pfad wird EINMAL hier aufgelöst: Er ist eine Konstante des
    // Geräts, und drüben je Takt einen Kanal zu bemühen wäre eine
    // Fehlerquelle mehr.
    await FlutterForegroundTask.saveData(
        key: kRideDataDir, value: (await getApplicationSupportDirectory()).path);
    await FlutterForegroundTask.saveData(key: kRideDataUid, value: uid);
    await FlutterForegroundTask.saveData(
        key: kRideDataStartedAt, value: startedAt.toUtc().toIso8601String());
    await FlutterForegroundTask.saveData(key: kRideDataActive, value: true);
  }

  @override
  Future<void> disarm() => FlutterForegroundTask.saveData(key: kRideDataActive, value: false);
}

final rideServiceBridgeProvider =
    Provider<RideServiceBridge>((ref) => const PlatformRideServiceBridge());

enum RideStartResult { started, noPermission, noService, failed }

class RideNotifier extends Notifier<RecordedRide?> {
  @override
  RecordedRide? build() => null;

  bool get isRunning => state != null;

  /// Holt eine unterbrochene Fahrt zurück und zeichnet weiter auf.
  /// Aufgerufen beim Kartenstart: Wer unterwegs ist und dessen App
  /// zwischendurch weggeräumt wurde, hat die Fahrt nicht beendet.
  Future<void> restore() async {
    if (state != null) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final ride = await ref.read(rideStoreProvider).readActive(uid: uid);
    if (ride == null) return;
    state = ride;
    if (_withinMaxDuration(ride)) {
      // Der Service läuft nach einem Wegwischen weiter; hier wird nur
      // wieder angemeldet, was ohnehin gilt. Läuft er nicht mehr
      // (Neustart des Geräts), setzt das ihn wieder auf.
      await _arm(uid, ride.startedAt);
      await syncConfirmTargets();
    } else {
      await _disarm();
    }
  }

  Future<RideStartResult> start() async {
    if (state != null) return RideStartResult.started;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return RideStartResult.failed;

    // Erst die Berechtigung, dann die Datei: Eine begonnene Fahrt, die
    // nie einen Fix bekommt, sähe aus wie eine Aufzeichnung und wäre
    // keine.
    final denial = await ref.read(ridePermissionProvider)();
    if (denial != null) return denial;

    final startedAt = DateTime.now().toUtc();
    try {
      // Das Fahrerprofil beim Start in den Kopf der Datei — die
      // Kalibrierung (Konzept-Routing 5, Schritt 6) rechnet je Profil.
      await ref.read(rideStoreProvider).begin(
          uid: uid, startedAt: startedAt, profile: RiderProfile.parse(ref.read(settingsProvider).riderProfile).name);
    } catch (e, stackTrace) {
      logError('Fahrt beginnen', e, stackTrace);
      return RideStartResult.failed;
    }
    state = (startedAt: startedAt, points: const [], marks: const []);
    await _arm(uid, startedAt);
    await syncConfirmTargets();
    // Der erste Punkt sofort und aus DIESEM Isolate — der Takt des
    // Service beginnt erst nach dem eingestellten Abstand.
    unawaited(_firstFix());
    return RideStartResult.started;
  }

  /// Beendet die Aufzeichnung und speichert die Fahrt auf dem Gerät.
  /// Gibt sie zurück; `null`, wenn keine lief. Gespeichert wird VOR dem
  /// Abschluss-Blatt: Wer es wegwischt, verliert nichts.
  ///
  /// Die Antworten auf die Fragen unterwegs (#116) gehen hier als
  /// Meldungen hinaus — ohne Netz in den Ausgangskorb —, bevor das Blatt
  /// kommt: Wer es wegwischt, hat trotzdem geantwortet.
  Future<Ride?> stop() async {
    final ride = state;
    await _disarm();
    state = null;
    if (ride == null) return null;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return null;
    final store = ref.read(rideStoreProvider);
    await store.writeConfirmTargets(uid: uid, targets: const []);
    final done = await store.finish(uid: uid, endedAt: DateTime.now().toUtc());
    if (done != null) await _sendConfirmations(done);
    return done;
  }

  /// Schreibt die Trails, zu denen unterwegs gefragt wird (#116) — beim
  /// Start und immer, wenn sich die Trails ändern (die Karte hört darauf).
  /// Ohne geladene Trails bleibt die Datei, wie sie ist — beim Beenden
  /// wird sie geleert, eine neue Fahrt erbt also nichts.
  Future<void> syncConfirmTargets() async {
    if (state == null) return;
    final uid = ref.read(currentUserIdProvider);
    final trails = ref.read(trailsProvider).valueOrNull;
    if (uid == null || trails == null) return;
    await ref.read(rideStoreProvider).writeConfirmTargets(uid: uid, targets: confirmTargetsOf(trails));
  }

  Future<void> _sendConfirmations(Ride ride) async {
    final reports = confirmReportsOf(ride.events);
    if (reports.isEmpty) return;
    final notifier = ref.read(trailsProvider.notifier);
    for (final r in reports) {
      try {
        // Vor Ort war, wer gefragt wurde: Der Dienst hat ihn im Korridor
        // der Linie gesehen. Zum Server geht nur das Ja.
        await notifier.report(r.trailId,
            status: r.status, condition: r.condition, onSite: true, at: r.at);
      } catch (e, stackTrace) {
        // Ein Serverfehler bleibt sichtbar im Bericht; die Fahrt ist
        // trotzdem gespeichert.
        logError('Fahrt: Bestätigung senden', e, stackTrace);
      }
    }
  }

  Future<void> _arm(String uid, DateTime startedAt) async {
    await ref.read(rideServiceBridgeProvider).arm(uid: uid, startedAt: startedAt);
    await ref.read(rideServiceProvider).start(
          title: kRideNoticeTitle,
          text: kRideNoticeText,
          every: kRideTickInterval,
        );
  }

  Future<void> _disarm() async {
    await ref.read(rideServiceProvider).stop();
    await ref.read(rideServiceBridgeProvider).disarm();
  }

  bool _withinMaxDuration(RecordedRide ride) =>
      DateTime.now().toUtc().difference(ride.startedAt) < kRideMaxDuration;

  Future<void> _firstFix() async {
    final point = await ref.read(rideFixProvider)();
    if (point == null || state == null) return;
    await ref.read(rideStoreProvider).appendPoint(point);
    acceptTick(point);
  }

  /// Nimmt einen Punkt an, den das Service-Isolate gemeldet hat. Nur für
  /// die Anzeige: Geschrieben hat ihn der Service schon.
  void acceptTick(RidePoint point) {
    final current = state;
    if (current == null) return;
    state = (startedAt: current.startedAt, points: [...current.points, point], marks: current.marks);
  }

  /// Setzt die nächste Marke (#105): „Trail beginnt", solange kein
  /// markierter Trail läuft, sonst „Trail endet". Gibt die gesetzte Marke
  /// zurück; `null`, wenn keine Fahrt läuft oder die Datei sie nicht
  /// nahm — dann steht sie auch nicht im Zustand, sonst zeigte der Knopf
  /// eine Marke, die das Zerlege-Blatt nie sieht.
  Future<RideMark?> toggleMark() async {
    final current = state;
    if (current == null) return null;
    final mark = RideMark(
      kind: markedTrailOpen(current.marks) ? RideMarkKind.end : RideMarkKind.start,
      at: DateTime.now().toUtc(),
    );
    if (!await ref.read(rideStoreProvider).appendMark(mark)) return null;
    final now = state;
    if (now == null || !now.startedAt.isAtSameMomentAs(current.startedAt)) return null;
    state = (startedAt: now.startedAt, points: now.points, marks: [...now.marks, mark]);
    return mark;
  }

  /// Hört die Aufzeichnung auf, weil die Fahrt zu lange läuft? Der
  /// Service selbst kennt die Grenze nicht, er misst, solange die Brücke
  /// „aktiv" sagt.
  Future<void> stopIfExpired() async {
    final ride = state;
    if (ride == null || _withinMaxDuration(ride)) return;
    await _disarm();
  }
}

final rideProvider = NotifierProvider<RideNotifier, RecordedRide?>(RideNotifier.new);

/// Die gespeicherten Fahrten dieses Kontos, neueste zuerst.
class RidesNotifier extends AsyncNotifier<List<Ride>> {
  @override
  Future<List<Ride>> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const [];
    // Eine beendete Fahrt kommt dazu — neu gelesen wird beim Wechsel
    // „läuft"/„läuft nicht", nicht bei jedem Messpunkt.
    ref.watch(rideProvider.select((r) => r == null));
    return ref.read(rideStoreProvider).list(uid: uid);
  }

  Future<void> delete(String id) => deleteMany([id]);

  /// Mehrere Fahrten auf einmal (#227, Mehrfachauswahl): gelöscht wird
  /// je Datei, neu gelesen EINMAL am Ende.
  Future<void> deleteMany(Iterable<String> ids) async {
    final store = ref.read(rideStoreProvider);
    for (final id in ids) {
      await store.delete(id);
    }
    ref.invalidateSelf();
    await future;
  }

  /// Das Fahrerprofil gemessener Fahrten nachträglich setzen (#228):
  /// falsch eingeordnet lernt eine Fahrt dem falschen Profil eine falsche
  /// Steigrate bei. Geplante Fahrten bleiben, wie sie sind (ihre Dauer
  /// ist mit dem Profil gerechnet). Gibt zurück, wie viele geschrieben
  /// wurden.
  Future<int> setProfile(Iterable<String> ids, RiderProfile profile) async {
    final store = ref.read(rideStoreProvider);
    var n = 0;
    for (final id in ids) {
      if (await store.setProfile(id, profile.name)) n++;
    }
    if (n > 0) {
      ref.invalidateSelf();
      await future;
    }
    return n;
  }

  /// Eine geplante Runde oder den Weg zum Trailkopf in „Meine Fahrten"
  /// ablegen (#158 Schritt 5). Null, wenn sich nichts schreiben ließ.
  Future<Ride?> savePlanned({
    required String name,
    required List<RidePoint> points,
    required Duration duration,
    required String? profile,
  }) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return null;
    final ride = await ref.read(rideStoreProvider).savePlanned(
        uid: uid,
        name: name,
        createdAt: DateTime.now().toUtc(),
        points: points,
        duration: duration,
        profile: profile);
    if (ride != null) {
      ref.invalidateSelf();
      await future;
    }
    return ride;
  }

  /// Fahrten aus GPX-Dateien ablegen (#188), jede mit ihrem eigenen
  /// Profil (dem Vorschlag aus der Steigrate, #227) oder sonst mit
  /// [profile]. Was schon auf dem Gerät liegt (`rideOnDevice`, auch eine
  /// Datei derselben Startsekunde), wird übersprungen und gezählt.
  Future<ImportRidesResult> saveImported(
      List<({String name, List<RidePoint> points, String? profile})> tracks,
      {required String profile}) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return (saved: 0, existed: 0, failed: tracks.length);
    final store = ref.read(rideStoreProvider);
    final known = [...await store.list(uid: uid)];
    var saved = 0, existed = 0, failed = 0;
    for (final t in tracks) {
      if (t.points.length < 2) {
        failed++;
        continue;
      }
      if (rideOnDevice(t.points, known)) {
        existed++;
        continue;
      }
      switch (await store.saveImported(uid: uid, name: t.name, points: t.points, profile: t.profile ?? profile)) {
        case ImportSave.saved:
          saved++;
          // Zwei Spuren derselben Datei mit gleichem Start zählen einmal.
          known.add(Ride(
              id: '', startedAt: t.points.first.at, endedAt: t.points.last.at, points: t.points));
        case ImportSave.exists:
          existed++;
        case ImportSave.failed:
          failed++;
      }
    }
    if (saved > 0) {
      ref.invalidateSelf();
      await future;
    }
    return (saved: saved, existed: existed, failed: failed);
  }
}

/// Was aus einem Stapel übernommener Fahrten wurde.
typedef ImportRidesResult = ({int saved, int existed, int failed});

final ridesProvider = AsyncNotifierProvider<RidesNotifier, List<Ride>>(RidesNotifier.new);

/// Wunsch der Liste an die Karte: diese gespeicherte Fahrt zeigen. Die
/// Karte zeichnet sie, bis der Nutzer sie wegtippt.
final mapFocusRideProvider = StateProvider<Ride?>((ref) => null);

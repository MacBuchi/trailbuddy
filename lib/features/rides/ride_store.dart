// Wo die Fahrten liegen (#28): im App-Verzeichnis unter `rides/`, das
// in beiden Backup-Ausschlüssen steht — ein Bewegungsprofil hat in
// Googles Cloud nichts verloren.
//
// Die LAUFENDE Fahrt wird Zeile für Zeile angehängt (JSON Lines), nicht
// am Ende am Stück: Der Prozess-Kill ist auf Android der Normalfall
// (PilzBuddy #147), und drei Stunden Fahren dürfen nicht daran hängen.
// Ein Abbruch mitten im Schreiben kostet höchstens die letzte Zeile —
// und genau die wirft [readActive] weg. Beim Beenden wird die Datei nur
// UMBENANNT (`active.jsonl` → `<id>.jsonl`): Die Fahrt bleibt als Ganzes
// auf dem Gerät (Konzept 5.1), nichts wird ohne Nachfrage gelöscht.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/errors.dart';
import 'ride_confirm.dart';
import 'ride_track.dart';

abstract interface class RideStore {
  /// Beginnt eine Fahrt und verwirft, was als laufende vorher dalag.
  ///
  /// **Wirft**, wenn sich nichts anlegen lässt: Eine Fahrt zu starten,
  /// die gar nicht aufgezeichnet werden kann, wäre ein Versprechen, das
  /// erst zu Hause auffliegt.
  /// [profile] ist das Fahrerprofil beim Start (`RiderProfile.name`,
  /// seit 0.70.0) und steht im Kopf der Datei.
  Future<void> begin({required String uid, required DateTime startedAt, String? profile});

  /// Hängt einen Punkt an. **Wirft nie** — ein verlorener Fix ist ein
  /// verlorener Fix, kein Grund, die laufende Fahrt abzubrechen.
  Future<void> appendPoint(RidePoint point);

  /// Hängt eine Frage oder Antwort (#116) an die LAUFENDE Fahrt. Mit
  /// [rideStartedAt] nur, wenn es noch dieselbe Fahrt ist — eine Antwort
  /// auf eine Benachrichtigung kann eintreffen, wenn die Fahrt längst
  /// beendet und eine neue begonnen ist. Gibt zurück, ob geschrieben
  /// wurde. **Wirft nie.**
  Future<bool> appendConfirmEvent(ConfirmEvent event, {DateTime? rideStartedAt});

  /// Hängt eine Marke „Trail beginnt/endet" (#105) an die laufende Fahrt.
  /// Geschrieben aus dem Main-Isolate — getippt wird dort, und die Marke
  /// trägt nur die Zeit; der Service hängt daneben seine Punkte an (wie
  /// die Antworten aus #116). Gibt zurück, ob geschrieben wurde. **Wirft
  /// nie.**
  Future<bool> appendMark(RideMark mark);

  /// Die Fragen und Antworten der laufenden Fahrt. Wirft nie.
  Future<List<ConfirmEvent>> activeConfirmEvents({required String uid});

  /// Die Trails, zu denen während der Fahrt gefragt wird (#116). Die App
  /// schreibt, der Service liest. Wirft nie — ohne Datei wird nicht
  /// gefragt, gefahren wird trotzdem.
  Future<void> writeConfirmTargets({required String uid, required List<ConfirmTarget> targets});
  Future<List<ConfirmTarget>> readConfirmTargets({required String uid});

  /// Die laufende Fahrt, oder `null`. Wirft nie.
  Future<RecordedRide?> readActive({required String uid});

  /// Schließt die laufende Fahrt ab: Sie wird zu einer gespeicherten
  /// [Ride]. `null`, wenn keine läuft. Wirft nie.
  Future<Ride?> finish({required String uid, required DateTime endedAt});

  /// Verwirft die laufende Fahrt, ohne sie zu speichern.
  Future<void> discardActive();

  /// Legt eine GEPLANTE Fahrt ab (#158 Schritt 5): die Linie als Punkte
  /// ohne Zeit und Höhe, [duration] die geschätzte Zeit. Liefert die
  /// gespeicherte Fahrt, oder null, wenn sich nichts schreiben ließ —
  /// das sagt die Oberfläche, still verschwinden darf eine Runde nicht.
  Future<Ride?> savePlanned({
    required String uid,
    required String name,
    required DateTime createdAt,
    required List<RidePoint> points,
    required Duration duration,
    String? profile,
  });

  /// Legt eine Fahrt aus einer GPX-Datei ab (#188): [points] mit Zeit und
  /// Datei-Höhe, die Kennung aus dem ersten Punkt. Liegt dort schon eine
  /// Datei, wird nichts geschrieben ([ImportSave.exists]) — dieselbe Datei
  /// zweimal gewählt legt keine zweite Fahrt an. Wirft nie.
  Future<ImportSave> saveImported({
    required String uid,
    required String name,
    required List<RidePoint> points,
    String? profile,
  });

  /// Alle gespeicherten Fahrten dieses Kontos, neueste zuerst. Wirft nie.
  Future<List<Ride>> list({required String uid});

  Future<void> delete(String id);

  /// Setzt das Fahrerprofil einer gespeicherten, GEMESSENEN Fahrt neu
  /// (#228): nur die Kopfzeile wird ersetzt, Punkte, Marken und Antworten
  /// bleiben Byte für Byte. Eine geplante Fahrt behält ihr Profil — ihre
  /// geschätzte Dauer ist damit gerechnet. Gibt zurück, ob geschrieben
  /// wurde. Wirft nie.
  Future<bool> setProfile(String id, String profile);
}

/// Was aus einer übernommenen Fahrt wurde.
enum ImportSave { saved, exists, failed }

class FileRideStore implements RideStore {
  FileRideStore({Directory? baseDir}) : _baseDirOverride = baseDir;

  final Directory? _baseDirOverride;

  /// Muss in `backup_rules.xml` UND `full_backup_content.xml` stehen.
  static const dirName = 'rides';
  static const _activeName = 'active.jsonl';
  static const _targetsName = 'confirm_targets.json';

  /// Schreibvorgänge in einer Kette: Der Takt hängt an, während das
  /// Beenden liest — ohne die Kette verlöre einer von beiden seinen
  /// Stand.
  Future<void> _lock = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Directory> _dir() async {
    final base = _baseDirOverride ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _active() async => File('${(await _dir()).path}/$_activeName');

  static String _idFor(DateTime startedAt) => startedAt
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[-:]'), '')
      .replaceAll(RegExp(r'\.\d+'), '');

  @override
  Future<void> begin({required String uid, required DateTime startedAt, String? profile}) =>
      _serialized(() async {
        final file = await _active();
        await file.writeAsString(
          '${jsonEncode({
                'uid': uid,
                'startedAt': startedAt.toUtc().toIso8601String(),
                'profile': ?profile,
              })}\n',
          flush: true,
        );
      });

  @override
  Future<void> appendPoint(RidePoint point) => _serialized(() async {
        try {
          final file = await _active();
          await file.writeAsString('${jsonEncode(point.toJson())}\n',
              mode: FileMode.append, flush: true);
        } catch (e, stackTrace) {
          // Gemeldet, nicht geschluckt: Das ist echter Datenverlust —
          // aber einer, der die Fahrt weiterlaufen lässt.
          logError('Fahrt-Punkt anhängen', e, stackTrace);
        }
      });

  @override
  Future<bool> appendConfirmEvent(ConfirmEvent event, {DateTime? rideStartedAt}) =>
      _serialized(() async {
        try {
          final file = await _active();
          if (!await file.exists()) return false;
          if (rideStartedAt != null) {
            final head = await _head(file);
            if (head == null || !head.startedAt.isAtSameMomentAs(rideStartedAt)) return false;
          }
          await file.writeAsString('${jsonEncode(event.toJson())}\n',
              mode: FileMode.append, flush: true);
          return true;
        } catch (e, stackTrace) {
          logError('Fahrt: Frage oder Antwort anhängen', e, stackTrace);
          return false;
        }
      });

  @override
  Future<bool> appendMark(RideMark mark) => _serialized(() async {
        try {
          final file = await _active();
          if (!await file.exists()) return false;
          await file.writeAsString('${jsonEncode(mark.toJson())}\n',
              mode: FileMode.append, flush: true);
          return true;
        } catch (e, stackTrace) {
          logError('Fahrt: Marke anhängen', e, stackTrace);
          return false;
        }
      });

  @override
  Future<List<ConfirmEvent>> activeConfirmEvents({required String uid}) =>
      _serialized(() async => (await _parse(await _active(), uid: uid))?.events ?? const []);

  @override
  Future<void> writeConfirmTargets({required String uid, required List<ConfirmTarget> targets}) async {
    try {
      final file = File('${(await _dir()).path}/$_targetsName');
      final part = File('${file.path}.part');
      await part.writeAsString(encodeConfirmTargets(uid: uid, targets: targets), flush: true);
      // Umbenennen statt überschreiben: Der Service liest dieselbe Datei
      // aus einem anderen Isolate und soll nie eine halbe sehen.
      await part.rename(file.path);
    } catch (e, stackTrace) {
      logError('Fahrt: Trails zum Bestätigen ablegen', e, stackTrace);
    }
  }

  @override
  Future<List<ConfirmTarget>> readConfirmTargets({required String uid}) async {
    try {
      final file = File('${(await _dir()).path}/$_targetsName');
      if (!await file.exists()) return const [];
      return decodeConfirmTargets(await file.readAsString(), uid: uid);
    } catch (_) {
      // Unlesbar heißt „nichts zu fragen" — je Takt ein Bericht wäre Lärm.
      return const [];
    }
  }

  /// Wann die Ziel-Datei zuletzt geschrieben wurde; der Service liest sie
  /// nur neu, wenn sich das ändert.
  Future<DateTime?> confirmTargetsModified() async {
    try {
      final file = File('${(await _dir()).path}/$_targetsName');
      return await file.exists() ? await file.lastModified() : null;
    } catch (_) {
      return null;
    }
  }

  /// Nur die Kopfzeile der Fahrt: wem sie gehört und wann sie begann.
  Future<({String uid, DateTime startedAt})?> _head(File file) async {
    try {
      final first = await file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      final head = jsonDecode(first);
      if (head is! Map<String, dynamic>) return null;
      final uid = head['uid'];
      final startedAt = DateTime.tryParse(head['startedAt'] as String? ?? '');
      if (uid is! String || startedAt == null) return null;
      return (uid: uid, startedAt: startedAt.toUtc());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<RecordedRide?> readActive({required String uid}) =>
      _serialized(() async {
        final parsed = await _parse(await _active(), uid: uid);
        if (parsed == null) return null;
        return (startedAt: parsed.startedAt, points: parsed.points, marks: parsed.marks);
      });

  @override
  Future<Ride?> finish({required String uid, required DateTime endedAt}) =>
      _serialized(() async {
        try {
          final active = await _active();
          final parsed = await _parse(active, uid: uid);
          if (parsed == null) return null;
          final id = _idFor(parsed.startedAt);
          final target = File('${(await _dir()).path}/$id.jsonl');
          // Das Ende als eigene Zeile, damit die Datei ihre Dauer
          // selbst trägt — der letzte Punkt kann Minuten vor dem
          // Beenden liegen (Funkloch, Pause am Ende).
          await active.writeAsString(
              '${jsonEncode({'endedAt': endedAt.toUtc().toIso8601String()})}\n',
              mode: FileMode.append,
              flush: true);
          await active.rename(target.path);
          return Ride(
              id: id,
              startedAt: parsed.startedAt,
              endedAt: endedAt.toUtc(),
              points: parsed.points,
              events: parsed.events,
              marks: parsed.marks,
              profile: parsed.profile);
        } catch (e, stackTrace) {
          logError('Fahrt abschließen', e, stackTrace);
          return null;
        }
      });

  @override
  Future<void> discardActive() => _serialized(() async {
        try {
          final file = await _active();
          if (await file.exists()) await file.delete();
        } catch (e, stackTrace) {
          // Bleibt die Datei liegen, böte die App beim nächsten Start
          // eine Fahrt an, die längst verworfen ist — das gehört gemeldet.
          logError('Fahrt verwerfen', e, stackTrace);
        }
      });

  @override
  Future<Ride?> savePlanned({
    required String uid,
    required String name,
    required DateTime createdAt,
    required List<RidePoint> points,
    required Duration duration,
    String? profile,
  }) =>
      _serialized(() async {
        try {
          final id = _idFor(createdAt);
          final file = File('${(await _dir()).path}/$id.jsonl');
          final endedAt = createdAt.add(duration).toUtc();
          final lines = [
            jsonEncode({
              'uid': uid,
              'startedAt': createdAt.toUtc().toIso8601String(),
              'planned': true,
              'name': name,
              'profile': ?profile,
            }),
            for (final p in points) jsonEncode(p.toJson()),
            jsonEncode({'endedAt': endedAt.toIso8601String()}),
          ];
          // Am Stück und über `.part` + `rename`: Eine geplante Fahrt
          // entsteht in einem Zug, ein halber Plan wäre keiner.
          final part = File('${file.path}.part');
          await part.writeAsString('${lines.join('\n')}\n', flush: true);
          await part.rename(file.path);
          return Ride(
            id: id,
            startedAt: createdAt.toUtc(),
            endedAt: endedAt,
            points: points,
            profile: profile,
            planned: true,
            name: name,
          );
        } catch (e, stackTrace) {
          logError('Geplante Fahrt speichern', e, stackTrace);
          return null;
        }
      });

  @override
  Future<ImportSave> saveImported({
    required String uid,
    required String name,
    required List<RidePoint> points,
    String? profile,
  }) =>
      _serialized(() async {
        if (points.isEmpty) return ImportSave.failed;
        try {
          final startedAt = points.first.at.toUtc();
          final file = File('${(await _dir()).path}/${_idFor(startedAt)}.jsonl');
          if (await file.exists()) return ImportSave.exists;
          final lines = [
            jsonEncode({
              'uid': uid,
              'startedAt': startedAt.toIso8601String(),
              'imported': true,
              'name': name,
              'profile': ?profile,
            }),
            for (final p in points) jsonEncode(p.toJson()),
            jsonEncode({'endedAt': points.last.at.toUtc().toIso8601String()}),
          ];
          // Am Stück über `.part` + `rename`, wie die geplante Fahrt.
          final part = File('${file.path}.part');
          await part.writeAsString('${lines.join('\n')}\n', flush: true);
          await part.rename(file.path);
          return ImportSave.saved;
        } catch (e, stackTrace) {
          logError('Fahrt aus GPX speichern', e, stackTrace);
          return ImportSave.failed;
        }
      });

  @override
  Future<List<Ride>> list({required String uid}) => _serialized(() async {
        try {
          final dir = await _dir();
          final rides = <Ride>[];
          await for (final entry in dir.list()) {
            if (entry is! File || !entry.path.endsWith('.jsonl')) continue;
            final name = entry.uri.pathSegments.last;
            if (name == _activeName) continue;
            final parsed = await _parse(entry, uid: uid);
            if (parsed == null) continue;
            rides.add(Ride(
              id: name.substring(0, name.length - '.jsonl'.length),
              startedAt: parsed.startedAt,
              // Ohne Ende-Zeile (Absturz beim Umbenennen): der letzte
              // Punkt, sonst der Start.
              endedAt: parsed.endedAt ??
                  (parsed.points.isEmpty ? parsed.startedAt : parsed.points.last.at),
              points: parsed.points,
              events: parsed.events,
              marks: parsed.marks,
              profile: parsed.profile,
              planned: parsed.planned,
              imported: parsed.imported,
              name: parsed.name,
            ));
          }
          rides.sort((a, b) => b.startedAt.compareTo(a.startedAt));
          return rides;
        } catch (_) {
          // Unlesbar heißt „keine Fahrten". Kein `logError`: Das wäre
          // ein Bericht pro Öffnen der Liste.
          return const [];
        }
      });

  @override
  Future<void> delete(String id) => _serialized(() async {
        // Nur ein Dateiname, kein Pfad: Die Kennung kommt aus der
        // eigenen Liste, aber ein `../` darf hier trotzdem nichts.
        if (!RegExp(r'^[0-9TZ]+$').hasMatch(id)) return;
        try {
          final file = File('${(await _dir()).path}/$id.jsonl');
          if (await file.exists()) await file.delete();
        } catch (e, stackTrace) {
          logError('Fahrt löschen', e, stackTrace);
        }
      });

  @override
  Future<bool> setProfile(String id, String profile) => _serialized(() async {
        if (!RegExp(r'^[0-9TZ]+$').hasMatch(id)) return false;
        try {
          final file = File('${(await _dir()).path}/$id.jsonl');
          if (!await file.exists()) return false;
          final text = await file.readAsString();
          final cut = text.indexOf('\n');
          final head = jsonDecode(cut < 0 ? text : text.substring(0, cut));
          if (head is! Map<String, dynamic> || head['planned'] == true) return false;
          head['profile'] = profile;
          // Am Stück über `.part` + `rename`: Ein Abbruch mittendrin lässt
          // die alte Datei stehen, nie eine halbe.
          final part = File('${file.path}.part');
          await part.writeAsString('${jsonEncode(head)}${cut < 0 ? '\n' : text.substring(cut)}', flush: true);
          await part.rename(file.path);
          return true;
        } catch (e, stackTrace) {
          logError('Fahrerprofil einer Fahrt ändern', e, stackTrace);
          return false;
        }
      });

  /// Liest eine Fahrt-Datei: Kopfzeile, Punkte, optional die Ende-Zeile.
  /// `null` bei fremdem Konto oder unlesbarem Kopf; kaputte Punktzeilen
  /// fallen einzeln weg.
  Future<
          ({
            DateTime startedAt,
            DateTime? endedAt,
            List<RidePoint> points,
            List<ConfirmEvent> events,
            List<RideMark> marks,
            String? profile,
            bool planned,
            bool imported,
            String? name,
          })?>
      _parse(File file, {required String uid}) async {
    try {
      if (!await file.exists()) return null;
      final lines = const LineSplitter()
          .convert(await file.readAsString())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) return null;
      final head = jsonDecode(lines.first);
      if (head is! Map<String, dynamic>) return null;
      // Fremdes Konto: Die Fahrt eines anderen Nutzers gehört nicht in
      // eine fremde Sitzung — dieselbe Regel wie beim Ausgangskorb.
      if (head['uid'] != uid) return null;
      final startedAt = DateTime.tryParse(head['startedAt'] as String? ?? '');
      if (startedAt == null) return null;
      final points = <RidePoint>[];
      final events = <ConfirmEvent>[];
      final marks = <RideMark>[];
      DateTime? endedAt;
      for (final line in lines.skip(1)) {
        // Eine abgeschnittene LETZTE Zeile ist der Normalfall nach einem
        // Prozess-Kill, kein Fehler.
        try {
          final json = jsonDecode(line);
          if (json is! Map<String, dynamic>) continue;
          if (json.containsKey('endedAt')) {
            endedAt = DateTime.tryParse(json['endedAt'] as String? ?? '')?.toUtc();
            continue;
          }
          if (RideMark.isMark(json)) {
            final mark = RideMark.fromJson(json);
            if (mark != null) marks.add(mark);
            continue;
          }
          if (ConfirmEvent.isEvent(json)) {
            final event = ConfirmEvent.fromJson(json);
            if (event != null) events.add(event);
            continue;
          }
          final point = RidePoint.fromJson(json);
          if (point != null) points.add(point);
        } catch (_) {
          continue;
        }
      }
      return (
        startedAt: startedAt.toUtc(),
        endedAt: endedAt,
        points: points,
        events: events,
        marks: marks,
        profile: head['profile'] as String?,
        planned: head['planned'] == true,
        imported: head['imported'] == true,
        name: head['name'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

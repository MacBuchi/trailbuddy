// Die Fahrt im Test (#28): im Speicher statt auf der Platte, Fix-Quelle
// und Service steuerbar. Ohne diese Fakes ginge JEDER Kartentest an
// echtes Plattform-IO — der Karten-Screen holt beim ersten Frame eine
// unterbrochene Fahrt zurück (`restore`).
import 'package:trailbuddy/features/rides/ride_confirm.dart';
import 'package:trailbuddy/features/rides/ride_providers.dart';
import 'package:trailbuddy/features/rides/ride_service.dart';
import 'package:trailbuddy/features/rides/ride_store.dart';
import 'package:trailbuddy/features/rides/ride_track.dart';

class FakeRideStore implements RideStore {
  String? uid;
  DateTime? startedAt;
  final points = <RidePoint>[];
  final marks = <RideMark>[];
  final rides = <Ride>[];

  /// Lässt [begin] scheitern — „eine Fahrt, die gar nicht aufzeichnen
  /// kann, darf nicht starten".
  bool failOnBegin = false;

  String? profile;

  @override
  Future<void> begin({required String uid, required DateTime startedAt, String? profile}) async {
    if (failOnBegin) throw Exception('kein Platz (Fake)');
    this.uid = uid;
    this.startedAt = startedAt;
    this.profile = profile;
    points.clear();
    events.clear();
    marks.clear();
  }

  @override
  Future<void> appendPoint(RidePoint point) async => points.add(point);

  /// Fragen und Antworten der laufenden Fahrt (#116).
  final events = <ConfirmEvent>[];

  /// Was die App zuletzt als Trails zum Bestätigen abgelegt hat.
  List<ConfirmTarget> targets = const [];
  String? targetsUid;

  @override
  Future<bool> appendConfirmEvent(ConfirmEvent event, {DateTime? rideStartedAt}) async {
    if (startedAt == null) return false;
    if (rideStartedAt != null && !rideStartedAt.isAtSameMomentAs(startedAt!)) return false;
    events.add(event);
    return true;
  }

  /// Lässt [appendMark] scheitern — die Marke darf dann auch nicht im
  /// Zustand stehen.
  bool failOnMark = false;

  @override
  Future<bool> appendMark(RideMark mark) async {
    if (startedAt == null || failOnMark) return false;
    marks.add(mark);
    return true;
  }

  @override
  Future<List<ConfirmEvent>> activeConfirmEvents({required String uid}) async =>
      startedAt == null || this.uid != uid ? const [] : List.of(events);

  @override
  Future<void> writeConfirmTargets({required String uid, required List<ConfirmTarget> targets}) async {
    targetsUid = uid;
    this.targets = targets;
  }

  @override
  Future<List<ConfirmTarget>> readConfirmTargets({required String uid}) async =>
      targetsUid == uid ? targets : const [];

  @override
  Future<RecordedRide?> readActive({required String uid}) async {
    if (startedAt == null || this.uid != uid) return null;
    return (startedAt: startedAt!, points: List.of(points), marks: List.of(marks));
  }

  @override
  Future<Ride?> finish({required String uid, required DateTime endedAt}) async {
    if (startedAt == null || this.uid != uid) return null;
    final ride = Ride(
        id: startedAt!.toIso8601String().replaceAll(RegExp(r'[-:.]'), ''),
        startedAt: startedAt!,
        endedAt: endedAt,
        points: List.of(points),
        events: List.of(events),
        marks: List.of(marks));
    rides.insert(0, ride);
    startedAt = null;
    points.clear();
    events.clear();
    marks.clear();
    return ride;
  }

  @override
  Future<void> discardActive() async {
    startedAt = null;
    points.clear();
    events.clear();
    marks.clear();
  }

  /// Lässt [savePlanned] scheitern — die Oberfläche muss es sagen.
  bool failOnPlanned = false;

  @override
  Future<Ride?> savePlanned({
    required String uid,
    required String name,
    required DateTime createdAt,
    required List<RidePoint> points,
    required Duration duration,
    String? profile,
  }) async {
    if (failOnPlanned) return null;
    this.uid ??= uid;
    final ride = Ride(
        id: 'planned-${createdAt.toIso8601String().replaceAll(RegExp(r'[-:.]'), '')}',
        startedAt: createdAt,
        endedAt: createdAt.add(duration),
        points: points,
        profile: profile,
        planned: true,
        name: name);
    rides.insert(0, ride);
    return ride;
  }

  @override
  Future<ImportSave> saveImported({
    required String uid,
    required String name,
    required List<RidePoint> points,
    String? profile,
  }) async {
    this.uid ??= uid;
    final id = 'imported-${points.first.at.toIso8601String().replaceAll(RegExp(r'[-:.]'), '')}';
    if (rides.any((r) => r.id == id)) return ImportSave.exists;
    rides.add(Ride(
        id: id,
        startedAt: points.first.at,
        endedAt: points.last.at,
        points: points,
        profile: profile,
        imported: true,
        name: name));
    rides.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return ImportSave.saved;
  }

  @override
  Future<List<Ride>> list({required String uid}) async =>
      [for (final r in rides) if (this.uid == uid) r];

  @override
  Future<void> delete(String id) async => rides.removeWhere((r) => r.id == id);

  @override
  Future<bool> setProfile(String id, String profile) async {
    final i = rides.indexWhere((r) => r.id == id);
    if (i < 0 || rides[i].planned) return false;
    final r = rides[i];
    rides[i] = Ride(
        id: r.id,
        startedAt: r.startedAt,
        endedAt: r.endedAt,
        points: r.points,
        events: r.events,
        marks: r.marks,
        profile: profile,
        imported: r.imported,
        name: r.name);
    return true;
  }
}

/// Die Brücke zum Service-Isolate im Test: merkt sich nur, was gesagt
/// wurde.
class FakeRideServiceBridge implements RideServiceBridge {
  bool armed = false;
  String? uid;
  DateTime? startedAt;
  int arms = 0;

  @override
  Future<void> arm({required String uid, required DateTime startedAt}) async {
    armed = true;
    arms++;
    this.uid = uid;
    this.startedAt = startedAt;
  }

  @override
  Future<void> disarm() async => armed = false;
}

/// Der Foreground-Service im Test: protokolliert statt einen
/// Platform-Channel anzufassen.
class FakeRideService implements RideService {
  bool running = false;
  int starts = 0;
  Duration? every;
  final titles = <String>[];

  @override
  Future<void> start({required String title, required String text, required Duration every}) async {
    if (!running) starts++;
    running = true;
    this.every = every;
    titles.add(title);
  }

  @override
  Future<void> stop() async => running = false;
}

/// Eine steuerbare Fix-Quelle. Vorgabe `null` — „kein Fix" ist im Wald
/// der Normalfall; ein Test, der eine Position braucht, setzt sie.
class FakeRideFix {
  RidePoint? next;
  int calls = 0;

  Future<RidePoint?> call() async {
    calls++;
    return next;
  }
}

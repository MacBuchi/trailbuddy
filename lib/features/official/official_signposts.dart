import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import 'official_match.dart';
import 'official_trails.dart';
import 'official_trails_layer.dart';
import 'official_trails_source.dart';

/// Der Satz dazu, von der Quelle aus gesagt.
String officialOverlapLine(OfficialOverlap overlap, String name) => switch (overlap) {
      OfficialOverlap.same => 'Auch ausgeschildert als „$name"',
      OfficialOverlap.partOf => 'Teil des offiziellen Trails „$name"',
      OfficialOverlap.contains => 'Enthält den offiziellen Trail „$name"',
    };

/// Die Sperre der Quelle zu einem gedeckten offiziellen Trail (#41) —
/// immer mit der Quelle, und mit Stand, wenn sie einen nennt. Liegt der
/// gesperrte Abschnitt NICHT auf dem Trail des Netzes, sagt der Satz das,
/// statt ihn zu sperren; liegt er darauf, ist das die Warnung.
String? officialClosureLine(OfficialMatch m, String by) {
  if (m.trail.status == OfficialStatus.open) return null;
  if (!m.onClosed) return 'anderer Abschnitt gesperrt laut $by';
  final what = m.trail.status == OfficialStatus.closed ? 'gesperrt' : 'Abschnitt gesperrt';
  final at = m.trail.updated;
  return '$what laut $by${at == null ? '' : ', Stand ${formatIsoDateDe(at)}'}';
}

/// „Auch ausgeschildert als …" im Trail-Blatt (#13, Schritt 4): die
/// offiziellen Trails, die [line] deckt, je eine Zeile, ein Tipp öffnet
/// ihr Blatt. Nur bei eingeschalteter Ebene — aus heißt: keine Anfrage,
/// also auch hier nicht. Die Region des Trails wird nachgeladen, falls
/// die Karte noch nicht dort war (Blatt aus der Liste geöffnet).
class OfficialSignposts extends ConsumerStatefulWidget {
  const OfficialSignposts({super.key, required this.line});

  final List<LatLng> line;

  @override
  ConsumerState<OfficialSignposts> createState() => _OfficialSignpostsState();
}

class _OfficialSignpostsState extends ConsumerState<OfficialSignposts> {
  Object? _computedFor;
  List<OfficialMatch> _matches = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(officialTrailsEnabledProvider) || widget.line.isEmpty) {
        return;
      }
      var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
      for (final p in widget.line) {
        if (p.latitude < s) s = p.latitude;
        if (p.latitude > n) n = p.latitude;
        if (p.longitude < w) w = p.longitude;
        if (p.longitude > e) e = p.longitude;
      }
      ref.read(officialTrailsControllerProvider.notifier).ensure((s: s, w: w, n: n, e: e));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(officialTrailsEnabledProvider)) return const SizedBox.shrink();
    final state = ref.watch(officialTrailsControllerProvider);
    // Nur neu rechnen, wenn andere Regionen da sind oder die Linie wechselt.
    final key = (state.byRegion, widget.line);
    if (key != _computedFor) {
      _computedFor = key;
      _matches = matchOfficial(widget.line, state.trails);
    }
    if (_matches.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in _matches)
          InkWell(
            key: ValueKey('official-${m.trail.id}'),
            onTap: () => showOfficialTrailSheet(context, m.trail),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                // Gesperrt ist grau wie die Linie, nicht orange — Orange
                // ist die Meldung eines Buddys (Konzept offizielle 5.3).
                m.onClosed
                    ? Icon(Icons.block, size: 18, color: Colors.grey.shade700)
                    : Icon(Icons.verified_outlined,
                        size: 18, color: AppPalette.of(context).map.official),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [
                      officialOverlapLine(m.overlap, m.trail.name),
                      // Gesperrt kommt von der Quelle, nicht von einem
                      // Buddy — der Satz sagt, von wem.
                      ?officialClosureLine(
                          m, state.sourceOf(m.trail)?.attribution ?? 'Quelle'),
                    ].join(' · '),
                    style: text.bodyMedium,
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ]),
            ),
          ),
      ],
    );
  }
}

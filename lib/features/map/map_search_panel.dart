// Das Suchfeld über der Karte (#576): geöffnet von der Lupe in der
// Knopfspalte, oben ein Feld, darunter die Treffer in vier Abschnitten —
// der vierte (Stufe 2) die Ortsnamen aus dem Index des Kartenhosts. Gerechnet wird in `map_search.dart`; ein Tipp gibt den
// Treffer an die Karte, die ihn wie einen Tipp auf die Karte behandelt.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_colors.dart';
import '../../core/app_theme.dart' show AppFonts;
import '../../core/geo.dart' show formatMeters;
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../../models/start_point.dart';
import '../../models/trail.dart';
import '../trails/grade_shield.dart';
import '../trails/trail_providers.dart';
import 'map_search.dart';
import 'place.dart';
import 'place_source.dart';
import 'poi.dart';
import 'poi_layer.dart' show PoiGlyph;
import 'poi_source.dart';
import 'start_point_layer.dart';

class MapSearchPanel extends ConsumerStatefulWidget {
  const MapSearchPanel({
    super.key,
    required this.center,
    required this.onPick,
    required this.onClose,
  });

  /// Die Mitte der Karte beim Öffnen: Orte werden rund um sie gesucht,
  /// alle Treffer nach Entfernung zu ihr sortiert.
  final LatLng center;

  /// Ein [Trail], [StartPoint], [Poi] oder [Place].
  final void Function(Object hit) onPick;
  final VoidCallback onClose;

  @override
  ConsumerState<MapSearchPanel> createState() => _MapSearchPanelState();
}

class _MapSearchPanelState extends ConsumerState<MapSearchPanel> {
  final _field = TextEditingController();
  late final List<PoiCell> _cells = mapSearchPoiCells(widget.center);
  static final _allGroups = PoiGroup.values.toSet();

  /// Die Ortsnamen zur letzten Eingabe; [_placesFor] ist die Eingabe, zu
  /// der sie gehören — kommt eine ältere Antwort zu spät, zählt sie nicht.
  PlaceLookup _places = kNoPlaces;
  String? _placesFor;
  bool _placesLoading = false;

  /// Online wird erst nach dem Tipp auf „Weitere Orte online suchen"
  /// gesucht (#596 H5, Betreiber 2026-11-20) — dann, solange das Feld
  /// offen ist; vorher geht keine Anfrage an den Kartenhost.
  bool _online = false;

  Future<void> _lookupPlaces(String text) async {
    _placesFor = text;
    if (longestPlaceWord(text) == null) {
      setState(() {
        _places = kNoPlaces;
        _placesLoading = false;
      });
      return;
    }
    if (_online) setState(() => _placesLoading = true);
    final found = await ref
        .read(placeSourceProvider)
        .lookup(text, widget.center, online: _online);
    if (!mounted || _placesFor != text) return;
    setState(() {
      _places = found;
      _placesLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    // Alle Gruppen, nicht nur die eingeschalteten: „Radladen" soll auch
    // finden, wer die Gruppe auf der Karte aus hat. Dieselben Zellen und
    // derselbe Weg wie die Karte (Host oder gespeicherter Bereich).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(poiControllerProvider.notifier).ensure(_cells, _allGroups);
    });
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final poiState = ref.watch(poiControllerProvider);
    final loaded = _cells.every(
      (c) => _allGroups.every((g) => poiState.byCell[c]?[g] != null),
    );
    final result = mapSearchOf(
      query: _field.text,
      center: widget.center,
      trails: ref.watch(trailsProvider).valueOrNull ?? const <Trail>[],
      startPoints: shownStartPoints(
        ref.watch(startPointsProvider),
        ref.watch(currentUserIdProvider),
      ),
      pois: poiState.inCells(_cells, _allGroups),
      places: _places.places,
      kindLabel: (k) => k.label(l),
    );
    final typed = _field.text.trim().isNotEmpty;
    final empty =
        result.trails.isEmpty &&
        result.startPoints.isEmpty &&
        result.pois.isEmpty &&
        result.places.isEmpty;
    final maxList = MediaQuery.sizeOf(context).height * 0.5;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onClose();
      },
      child: Card(
        key: const ValueKey('map-search'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.search),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('map-search-field'),
                    controller: _field,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: l.mapSearchHint,
                      border: InputBorder.none,
                    ),
                    onChanged: _lookupPlaces,
                  ),
                ),
                IconButton(
                  key: const ValueKey('map-search-close'),
                  tooltip: l.mapSearchClose,
                  icon: const Icon(Icons.close),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: widget.onClose,
                ),
              ],
            ),
            if (typed) ...[
              const Divider(height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxList),
                child: ListView(
                  key: const ValueKey('map-search-results'),
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    if (result.isGuess)
                      _Note(
                        l.mapSearchGuess,
                        key: const ValueKey('map-search-guess'),
                      ),
                    if (result.trails.isNotEmpty) ...[
                      _Header(l.mapSearchTrails),
                      for (final t in result.trails)
                        _TrailRow(
                          t,
                          center: widget.center,
                          onTap: () => widget.onPick(t),
                        ),
                    ],
                    if (result.startPoints.isNotEmpty) ...[
                      _Header(l.mapSearchStartPoints),
                      for (final p in result.startPoints)
                        _StartPointRow(
                          p,
                          center: widget.center,
                          own: p.isMine(ref.watch(currentUserIdProvider) ?? ''),
                          onTap: () => widget.onPick(p),
                        ),
                    ],
                    if (result.pois.isNotEmpty) ...[
                      _Header(l.mapSearchPois),
                      for (final p in result.pois)
                        _PoiRow(
                          p,
                          center: widget.center,
                          onTap: () => widget.onPick(p),
                        ),
                    ],
                    if (result.places.isNotEmpty) ...[
                      _Header(l.mapSearchPlaces),
                      for (final p in result.places)
                        _PlaceRow(
                          p,
                          center: widget.center,
                          onTap: () => widget.onPick(p),
                        ),
                    ],
                    if (!_online && longestPlaceWord(_field.text) != null)
                      ListTile(
                        key: const ValueKey('map-search-places-online'),
                        minTileHeight: 48,
                        leading: SizedBox(
                          width: 32,
                          child: Center(
                            child: Icon(
                              Icons.travel_explore,
                              color: AppPalette.of(context).accentText,
                            ),
                          ),
                        ),
                        title: Text(
                          l.mapSearchPlacesOnline,
                          style: TextStyle(
                            color: AppPalette.of(context).accentText,
                          ),
                        ),
                        onTap: () {
                          setState(() => _online = true);
                          _lookupPlaces(_field.text);
                        },
                      ),
                    if (_placesLoading)
                      _Note(
                        l.mapSearchPlacesLoading,
                        key: const ValueKey('map-search-places-loading'),
                      )
                    else if (_places.offline)
                      _Note(
                        l.mapSearchPlacesOffline,
                        key: const ValueKey('map-search-places-offline'),
                      ),
                    // Was die Orte gerade tun — erst, wenn sie den
                    // Unterschied machen könnten.
                    if (!loaded && poiState.unavailable)
                      _Note(
                        l.mapSearchPoisUnavailable,
                        key: const ValueKey('map-search-pois-unavailable'),
                      )
                    else if (!loaded)
                      _Note(
                        l.mapSearchPoisLoading,
                        key: const ValueKey('map-search-pois-loading'),
                      )
                    else if (empty && !_placesLoading)
                      _Note(
                        l.mapSearchNothing,
                        key: const ValueKey('map-search-nothing'),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _away(LatLng center, LatLng at) =>
    formatMeters(const Distance().as(LengthUnit.Meter, center, at));

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: AppPalette.of(context).muted,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: AppPalette.of(context).muted),
    ),
  );
}

class _TrailRow extends StatelessWidget {
  const _TrailRow(this.trail, {required this.center, required this.onTap});

  final Trail trail;
  final LatLng center;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final near = trail.points.isEmpty
        ? null
        : trail.points.reduce(
            (a, b) =>
                const Distance().as(LengthUnit.Meter, center, a) <=
                    const Distance().as(LengthUnit.Meter, center, b)
                ? a
                : b,
          );
    return ListTile(
      key: ValueKey('map-search-trail-${trail.id}'),
      minTileHeight: 48,
      leading: SizedBox(
        width: 32,
        child: Center(
          child: trail.grade == null
              ? Icon(Icons.route, color: AppPalette.of(context).muted)
              : GradeShield(trail.grade!, uphill: isUphill(trail)),
        ),
      ),
      title: Text(
        trail.displayName(context.l10n),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: near == null ? null : _Distance(_away(center, near)),
      onTap: onTap,
    );
  }
}

class _StartPointRow extends StatelessWidget {
  const _StartPointRow(
    this.point, {
    required this.center,
    required this.own,
    required this.onTap,
  });

  final StartPoint point;
  final LatLng center;
  final bool own;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('map-search-start-${point.key}'),
    minTileHeight: 48,
    leading: SizedBox(
      width: 32,
      child: Center(
        child: Transform.scale(
          scale: 0.8,
          child: StartPointPin(own: own, pending: point.pending),
        ),
      ),
    ),
    title: Text(point.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: own || point.username == null ? null : Text(point.username!),
    trailing: _Distance(_away(center, point.position)),
    onTap: onTap,
  );
}

class _PoiRow extends StatelessWidget {
  const _PoiRow(this.poi, {required this.center, required this.onTap});

  final Poi poi;
  final LatLng center;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final kind = poi.kind.label(l);
    final color = poi.kind.group.color;
    return ListTile(
      key: ValueKey('map-search-poi-${poi.id}'),
      minTileHeight: 48,
      leading: SizedBox(
        width: 32,
        child: Center(
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: PoiGlyph(kind: poi.kind, size: 16, background: color),
          ),
        ),
      ),
      title: Text(
        poi.name ?? kind,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: poi.name == null ? null : Text(kind),
      trailing: _Distance(_away(center, poi.position)),
      onTap: onTap,
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow(this.place, {required this.center, required this.onTap});

  final Place place;
  final LatLng center;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final muted = AppPalette.of(context).muted;
    final details = [
      place.kind.label(l),
      if (place.ele != null) '${place.ele} m',
      ?place.alt,
    ].join(' · ');
    return ListTile(
      key: ValueKey('map-search-place-${place.id}'),
      minTileHeight: 48,
      leading: SizedBox(
        width: 32,
        child: Center(child: Icon(place.kind.icon, color: muted)),
      ),
      title: Text(place.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: _Distance(_away(center, place.position)),
      onTap: onTap,
    );
  }
}

class _Distance extends StatelessWidget {
  const _Distance(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      fontFamily: AppFonts.mono,
      color: AppPalette.of(context).muted,
    ),
  );
}

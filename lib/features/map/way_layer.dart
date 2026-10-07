// Die Ebene „Wege" (#212, PR 2): Forstweg-Güte und Pfad-Schwierigkeit aus
// OSM, als drittes Archiv vom eigenen Kartenhost neben Basiskarte und
// Höhen (`way-data.yml`, `tool/way_archive.py`). Die Basiskarte zeichnet
// den Weg; diese Ebene legt sich über ihn und sagt, wie er ist — dort, wo
// OSM es weiß (#211: Güte auf 83 % der Forstwege, Schwierigkeit auf einem
// Fünftel der Pfade). Ungetaggte Wege bleiben, wie die Basiskarte sie
// zeichnet.
//
// **Aussehen** (Betreiber, 2026-10-08; `docs/design/README.md` Abschnitt
// 5a): nur Strich und Breite, in den Grau-Braun-Tönen der Basiskarte, nie
// eine Trail-Farbe. Durchgezogen und kräftig heißt gut/leicht, gestrichelt
// mittel, gepunktet und blass schlecht/schwer. Im Web gibt es keinen Strich
// (`vector_tile_renderer` verwirft `line-dasharray`), dort tragen Breite
// und Helligkeit allein — deshalb zwei Fassungen derselben Tabelle
// ([wayStyleLayers] mit `dashes`).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart' show TileProviders;
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../../core/connectivity.dart';
import '../../core/errors.dart';
import '../../core/settings.dart';
import 'base_map_providers.dart';
import 'map_providers.dart';
import 'online_map.dart';

/// Das Kachelformat des Archivs — gespiegelt aus `tool/way_archive.py`
/// (`FORMAT`, `ZOOM`, `LAYER`, `KEY`); `test/release_workflow_test.dart`
/// hält beide Seiten zusammen. Ein anderes Format lehnt das Manifest ab:
/// dann keine Ebene, keine falsch gelesene.
const kWaysFormat = 1;

/// Die eine Zoomstufe des Archivs. Darunter zeigt keine Engine die Ebene
/// (ein Archiv mit nur z13 kann nicht verkleinert werden), darüber wird
/// hochskaliert. Die Basiskarte zeigt Forstwege ab 12, Pfade ab 13.
const kWaysZoom = 13;
const kWaysLayer = 'ways';
const kWaysKey = 'k';

/// Die Quelle im Stil beider Engines.
const kWaysSourceId = 'ways';

/// Forstweg oder Pfad — die Basiskarte unterscheidet beide schon (Farbe,
/// Breite), die Ebene übernimmt das.
enum WayKind { track, path }

/// Die sechs Klassen des Archivs (`k`), je mit ihrem Aussehen. Die
/// Reihenfolge ist die der Legende.
///
/// [color] ist der Strich, [band] das Band darunter, das die gestrichelte
/// Linie der Basiskarte abdeckt (sonst schienen deren Striche durch die
/// Lücken); [webColor] die Farbe ohne Strich. Die Breiten liegen bei
/// Zoom 15 immer ÜBER der Basislinie (Forstweg 1,4, Pfad 0,8), sonst
/// stünde sie neben der Ebene.
enum WayClass {
  trackGood(1, WayKind.track, 'gut', Color(0xFF7F6649), null, Color(0xFF7F6649), 2.2, null),
  trackMedium(2, WayKind.track, 'mittel', Color(0xFFA58A6A), Color(0xFFD3C5B3), Color(0xFFA58A6A), 1.8, [3, 1.5]),
  trackPoor(3, WayKind.track, 'schlecht', Color(0xFFA58A6A), Color(0xFFDDD2C4), Color(0xFFC7B49D), 1.6, [1, 2]),
  pathEasy(4, WayKind.path, 'leicht', Color(0xFF8F7860), null, Color(0xFF8F7860), 1.4, null),
  pathMedium(5, WayKind.path, 'mittelschwer', Color(0xFFA8907A), Color(0xFFD8CCBD), Color(0xFFB6A08A), 1.1, [3, 1.5]),
  pathHard(6, WayKind.path, 'schwer', Color(0xFFA8907A), Color(0xFFE0D6CA), Color(0xFFCDBFAE), 1.0, [1, 2]);

  const WayClass(this.code, this.kind, this.label, this.color, this.band, this.webColor, this.width, this.dash);

  /// Der Wert von `k` im Archiv.
  final int code;
  final WayKind kind;

  /// Das Wort der Legende, unter der Überschrift der Wegart.
  final String label;
  final Color color;
  final Color? band;
  final Color webColor;

  /// Breite bei Zoom 15 in Bildpunkten.
  final double width;

  /// Strichmuster in Vielfachen der Breite (MapLibre); null = durchgezogen.
  final List<double>? dash;
}

/// Die Breite über den Zoom, wie die Wege der Basiskarte
/// (`tool/transform_map_style.py`, exponentiell 1,6).
List<Object> _width(double atZ15) => [
      'interpolate', ['exponential', 1.6], ['zoom'],
      kWaysZoom, atZ15 * 0.55, 15, atZ15, 20, atZ15 * 3.3,
    ];

String _css(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Die Stil-Ebenen der Wege für eine Quelle [sourceId]. Mit [dashes]
/// (MapLibre) je gestrichelter Klasse ein Band und darüber der Strich;
/// ohne (flutter_map im Web) EINE durchgezogene Linie in [WayClass.webColor].
/// Erst alle Bänder, dann alle Striche — ein Band darf keinen Strich
/// einer Nachbarklasse zudecken, wo zwei Wege sich treffen.
List<Map<String, dynamic>> wayStyleLayers(String sourceId, {required bool dashes}) {
  Map<String, dynamic> line(String id, WayClass c, Color color, {List<double>? dash}) => {
        'id': '$sourceId/$id-${c.name}',
        'type': 'line',
        'source': sourceId,
        'source-layer': kWaysLayer,
        'minzoom': kWaysZoom,
        'filter': ['==', ['get', kWaysKey], c.code],
        'layout': {'line-cap': 'butt', 'line-join': 'round'},
        'paint': {
          'line-color': _css(color),
          'line-width': _width(c.width),
          'line-dasharray': ?dash,
        },
      };
  if (!dashes) {
    return [for (final c in WayClass.values) line('line', c, c.webColor)];
  }
  return [
    for (final c in WayClass.values)
      if (c.band case final band?) line('band', c, band),
    for (final c in WayClass.values) line('line', c, c.color, dash: c.dash),
  ];
}

/// Das Manifest des Wege-Archivs (`ways.json`, geschrieben von
/// `way-data.yml`): welche Datei gilt, mit welchem Format.
class WaysManifest {
  const WaysManifest({required this.file, required this.bytes, required this.build});

  final String file;
  final int bytes;

  /// Das Datum des Baus (`JJJJMMTT`).
  final String build;

  Uri get archiveUri => Uri.parse('$kMapTilesBase/$file');

  /// Wirft bei allem, was nicht passt. Der Dateiname wird geprüft, weil
  /// er zu einem Pfad wird; Format und Zoom, weil die Stil-Ebenen genau
  /// diese Kacheln erwarten.
  factory WaysManifest.fromJson(Map<String, dynamic> j) {
    final file = j['file'] as String;
    if (!RegExp(r'^ways-\d{8}\.pmtiles$').hasMatch(file)) {
      throw FormatException('Unerwarteter Archivname: $file');
    }
    if (j['format'] != kWaysFormat || j['zoom'] != kWaysZoom) {
      throw FormatException('Wegeformat ${j['format']}/${j['zoom']} unbekannt');
    }
    return WaysManifest(file: file, bytes: j['bytes'] as int, build: j['build'] as String);
  }
}

/// Holt das Manifest vom Host; wirft bei allem, was nicht passt.
Future<WaysManifest?> fetchWaysManifest() async {
  final response = await http.get(Uri.parse(kWaysManifestUrl)).timeout(kMapManifestTimeout);
  if (response.statusCode != 200) {
    throw http.ClientException('Wege-Manifest: HTTP ${response.statusCode}');
  }
  return WaysManifest.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
}

/// Die Naht für Tests (kein Netz).
final waysManifestLoaderProvider =
    Provider<Future<WaysManifest?> Function()>((ref) => fetchWaysManifest);

/// Der Schalter in „Kartenebenen", gerätelokal, Vorgabe an. Aus heißt:
/// keine Anfrage.
final wayLayerEnabledProvider = NotifierProvider<RememberedFlag, bool>(
  () => RememberedFlag(
    read: (s) => s.wayLayerEnabled,
    write: (s, v) => s.setWayLayerEnabled(v),
    label: 'Ebene Wege merken',
  ),
);

/// Das Manifest — oder null: Ebene aus, kein Empfang, Host nicht
/// erreichbar, noch kein Bau, unbekanntes Format. Null heißt für beide
/// Engines: die Karte ohne die Ebene, still. Gemeldet wird nur, was nicht
/// nach Funkloch, fehlendem Bau (HTTP-Status) oder fremdem Format
/// aussieht — sonst stünde jede Installation im Wochendigest, solange
/// `way-data.yml` noch nicht veröffentlicht hat.
final waysManifestProvider = FutureProvider<WaysManifest?>((ref) async {
  if (!ref.watch(wayLayerEnabledProvider)) return null;
  if (ref.watch(noConnectivityProvider)) return null;
  try {
    return await ref.watch(waysManifestLoaderProvider)();
  } catch (e, s) {
    if (!looksOffline(e) && e is! FormatException && e is! http.ClientException) {
      logError('Wege-Manifest laden', e, s);
    }
    return null;
  }
});

/// Das Thema der Ebene für flutter_map — ohne Strich, siehe oben.
vtr.Theme wayTheme() => vtr.ThemeReader().read({
      'version': 8,
      'layers': wayStyleLayers(kWaysSourceId, dashes: false),
    });

/// Die Ebene für die flutter_map-Engine: Archiv vom Host per Range,
/// Quelle [kWaysSourceId]. Null, solange es kein Manifest gibt oder das
/// Archiv nicht aufgeht.
final onlineWaysStyleProvider = FutureProvider<BaseMapStyle?>((ref) async {
  final manifest = await ref.watch(waysManifestProvider.future);
  if (manifest == null) return null;
  try {
    final archive = await ref.watch(onlineArchiveOpenerProvider)(manifest.archiveUri);
    ref.onDispose(archive.close);
    return BaseMapStyle(theme: wayTheme(), tileProviders: TileProviders({kWaysSourceId: archive}));
  } catch (e, s) {
    if (!looksOffline(e)) logError('Wege-Archiv öffnen', e, s);
    return null;
  }
});

/// Zeichnet ein Stück Weg in einer Klasse, wie MapLibre es zeichnet: das
/// Band, darüber der Strich, das Muster in Vielfachen der Breite. Für
/// Legende und Schalter — dieselbe Tabelle wie die Karte.
void paintWayStroke(Canvas canvas, Offset a, Offset b, WayClass c, double width) {
  void stroke(Color color, List<double>? dash) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt;
    if (dash == null) {
      canvas.drawLine(a, b, paint);
      return;
    }
    var x = a.dx;
    var i = 0;
    while (x < b.dx) {
      final len = dash[i % dash.length] * width;
      if (i.isEven) canvas.drawLine(Offset(x, a.dy), Offset((x + len).clamp(a.dx, b.dx), a.dy), paint);
      x += len;
      i++;
    }
  }

  if (c.band case final band?) stroke(band, null);
  stroke(c.color, c.dash);
}

/// Das Bild am Schalter „Wege": die drei Forstweg-Klassen untereinander.
class WaySwatchPainter extends CustomPainter {
  const WaySwatchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const rows = [WayClass.trackGood, WayClass.trackMedium, WayClass.trackPoor];
    for (var i = 0; i < rows.length; i++) {
      final y = size.height * (i + 0.5) / rows.length;
      paintWayStroke(canvas, Offset(0, y), Offset(size.width, y), rows[i], 3);
    }
  }

  @override
  bool shouldRepaint(WaySwatchPainter old) => false;
}

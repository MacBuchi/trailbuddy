// Höhenlinien aus den Höhenkacheln (#271) — dieselben z13-Kacheln, mit
// denen Planer, Trail-Profil und Navigation rechnen (`height_tiles.dart`):
// offline aus den gespeicherten Bereichen, online vom eigenen Kartenhost.
// Kein neues Netzziel, keine neuen Daten, kein Asset.
//
// Die Maschine (Marching Squares, Douglas-Peucker, Chaikin) ist PilzBuddys
// `contours.dart`; die Regeln hier folgen PilzBuddys
// `elevation_contours.dart` (seit 1.99.1), mit zwei Unterschieden, die aus
// dem besseren Gitter kommen:
//
// - **Ein regelmäßiges Raster statt eines Hexgitters.** Jede Kachel trägt
//   49 × 49 Proben in ganzen Metern, gleichmäßig in Web-Mercator, die
//   Ränder geteilt. Die Proben liegen damit auf EINEM festen Weltraster
//   (`gx = Kachel-x · 48 + Spalte`), und das Feld eines Fensters ist ein
//   Ausschnitt daraus — dieselbe Gegend ergibt immer dieselben Proben.
//   PilzBuddys Viertelschritt gegen die Hex-Parität und der Zwang zum
//   3×3-Glätten gegen 20-m-Stufen entfallen.
// - **Das Fenster IST eine Menge von Kacheln** (alle z13-Kacheln, die der
//   Ausschnitt berührt). Schieben innerhalb derselben Kacheln ändert
//   nichts, und jede Kachel kostet höchstens einen Abruf je Sitzung.
//
// Reines Dart ohne Flutter — die Rechnung soll ohne Karte prüfbar sein.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import '../offline_areas/height_tiles.dart';
import 'contours.dart';

/// Abstand zweier Proben in Probenschritten je Kachel: 49 Proben, 48
/// Schritte, der Rand gehört beiden Nachbarn.
const kContourStepsPerTile = kHeightGrid - 1;

/// „Hier wissen wir nichts" — dieselbe Zahl wie in den Kacheln.
const kContourNoData = kHeightNoData;

/// Gröber als das je Bildschirmpixel, und die Ebene bleibt leer.
///
/// Eine Probe liegt rund 70 m neben der nächsten (z13-Kachel ≈ 3,3 km auf
/// 47° N, 48 Schritte). Bei 40 m je Pixel sind das noch knapp zwei Pixel
/// je Probe — darüber zeichnete die Linie eine Genauigkeit, die nicht in
/// den Daten steht, und die Kacheln des Fensters gingen in die Hunderte.
const kContourMaxMetersPerPixel = 40.0;

/// Höchstens so viele Kacheln je Fenster. **Eine Kostengrenze, keine
/// Datengrenze**: Jede Kachel, die kein gespeicherter Bereich hat, ist
/// online eine Range-Anfrage an den Kartenhost (R2-Class-B, #55) — wie
/// eine Kachel der Karte selbst. 64 Kacheln sind ein Telefon hochkant bei
/// rund 30 m je Pixel; ein Tablet quer erreicht die Grenze früher und
/// zeigt dann „näher heranzoomen".
const kContourMaxTiles = 64;

/// Höchstens so viele Proben je Achse; darüber wird ausgedünnt (jede
/// zweite, dritte … Probe). Hält auch die Kantenkennungen der Maschine
/// unter 2^20.
const kContourSampleBudget = 512;

/// Kürzer als das auf dem Schirm, und die Linie sagt nichts.
const kContourMinLinePixels = 40.0;

/// Sind nach dem Ziehen mehr Punkte als das übrig, wird die Äquidistanz
/// EINMAL vergröbert und neu gezogen. Nur ein Netz — die Dichte regelt
/// [contourEquidistanceM] aus dem Gelände.
const kContourPointBudget = 40000;

/// Wie weit die Vereinfachung eine Linie von ihrem Verlauf abbringen
/// darf — in BILDSCHIRMPIXELN (PilzBuddy 1.99.1: 2 Gitterzellen waren
/// nah dran 110 px, und Nachbarlinien kreuzten sich). Eine Größenordnung
/// unter [kContourMinLineSpacingPixels].
const kContourSimplifyPixels = 1.5;

/// Ab wie vielen Bildschirmpixeln Abstand zwei Nachbarlinien noch zwei
/// Linien sind. Die eine Stellschraube der Dichte (PilzBuddy, am Gerät:
/// 12 px waren in den Alpen eine Schraffur).
const kContourMinLineSpacingPixels = 20.0;

/// Die erlaubten Äquidistanzen, aufsteigend. 10 m geht hier (PilzBuddy
/// beginnt bei 20): Die Kacheln tragen ganze Meter, keine 20-m-Stufen.
const kContourSteps = [10, 20, 50, 100, 200];

/// Höhenabstand der Hauptlinien — die kräftigeren mit der Zahl. Nicht
/// „jede fünfte": Bei 100 m Äquidistanz wäre das alle 500 Höhenmeter, und
/// in einem Talkessel stünde keine Zahl auf dem Schirm (PilzBuddy).
/// Anders als dort ist aber höchstens JEDE ZWEITE eine Hauptlinie
/// ([contourIndexStepM]): In den Alpen gilt nah dran oft 100 m, und mit
/// „mindestens alle 100 m" war dort jede Linie kräftig und beschriftet —
/// das Gegenteil von dezent (an echten Kacheln um Innsbruck gesehen).
const kContourIndexEveryM = 100;

/// Über 3 × 3 Proben mitteln, bevor gezogen wird. Das Geländemodell ist
/// ein Oberflächenmodell (Copernicus GLO-90 misst Kronendach und Dächer
/// mit): Waldkanten und Lichtungen hinterlassen Stufen von 10–20 m, und
/// ungeglättet zeichnen 10-m-Linien jede davon als eigenen Ring. Das
/// Mittel über ~200 m nimmt diese Ringe weg und lässt Hang, Rinne und
/// Kuppe stehen. An echten Kacheln angesehen (Brandenburg, Pfälzerwald,
/// Innsbruck; `lib/features/map/CLAUDE.md`): ungeglättet 104 statt 59
/// Linien im Flachen, die Mehrzahl davon Störringe.
const kContourSmooth = true;

/// Das Aussehen (#271, „relativ dezent"): dünn und halb durchsichtig,
/// Hauptlinien etwas kräftiger — schmaler als jeder Pfad der Ebene „Wege"
/// (0,9 px bei Zoom 13), damit nie eine Höhenlinie wie ein Weg aussieht.
/// Farbe in `AppColors.contourLine`.
const kContourWidth = 0.8;
const kContourOpacity = 0.35;
const kContourIndexWidth = 1.2;
const kContourIndexOpacity = 0.55;

/// Schriftgröße der Zahlen.
const kContourLabelSize = 10.5;

/// So viele Proben Rand braucht der Ausschnitt mindestens bis zur
/// Fensterkante (siehe [ContourWindow.covering]).
const kContourMarginSamples = 1.5;

/// Die z13-Kacheln, die ein Ausschnitt berührt — das Fenster der Ebene.
class ContourWindow {
  const ContourWindow(this.x0, this.y0, this.x1, this.y1);

  /// Aus dem Sichtfenster: alle Kacheln von der Nordwest- bis zur
  /// Südost-Ecke — plus die Nachbarkachel, wenn der Rand des Ausschnitts
  /// näher als [kContourMarginSamples] an einer Kachelkante liegt. Das Feld
  /// verliert nach dem Glätten seinen äußersten Probenring
  /// ([contourFieldFrom]); ohne den Zuschlag fehlten die Linien dann in
  /// einem Streifen am Bildrand.
  factory ContourWindow.covering({
    required double west,
    required double south,
    required double east,
    required double north,
  }) {
    const m = kContourMarginSamples / kContourStepsPerTile;
    final nw = heightTileOf(LatLng(north, west));
    final se = heightTileOf(LatLng(south, east));
    final x0 = nw.fx < m ? nw.x - 1 : nw.x;
    final y0 = nw.fy < m ? nw.y - 1 : nw.y;
    final x1 = se.fx > 1 - m ? se.x + 1 : se.x;
    final y1 = se.fy > 1 - m ? se.y + 1 : se.y;
    return ContourWindow(math.min(x0, x1), math.min(y0, y1), math.max(x0, x1), math.max(y0, y1));
  }

  final int x0, y0, x1, y1;

  int get columns => x1 - x0 + 1;
  int get rows => y1 - y0 + 1;
  int get tileCount => columns * rows;

  Iterable<({int x, int y})> get tiles sync* {
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        yield (x: x, y: y);
      }
    }
  }

  String get key => '$x0,$y0-$x1,$y1';

  @override
  bool operator ==(Object other) =>
      other is ContourWindow && other.x0 == x0 && other.y0 == y0 && other.x1 == x1 && other.y1 == y1;

  @override
  int get hashCode => Object.hash(x0, y0, x1, y1);
}

/// Jede wievielte Probe das Feld nimmt — ein Teiler von 48, damit das
/// ausgedünnte Raster ein Teilraster des Weltrasters bleibt: Zwei Fenster
/// mit demselben Faktor tasten dieselben Punkte ab, auch wenn ihre erste
/// Kachel eine andere ist.
int contourSampleFactor(ContourWindow window, {int budget = kContourSampleBudget}) {
  final longest = math.max(window.columns, window.rows) * kContourStepsPerTile;
  for (final f in const [1, 2, 3, 4, 6, 8, 12, 16, 24, 48]) {
    if (longest ~/ f + 1 <= budget) return f;
  }
  return kContourStepsPerTile;
}

const _worldTiles = 1 << kHeightTileZoom;

/// Länge einer Weltraster-Spalte (auch gebrochen).
double contourLonAt(double gx) => gx / kContourStepsPerTile / _worldTiles * 360 - 180;

/// Breite einer Weltraster-Zeile (auch gebrochen), Web-Mercator.
double contourLatAt(double gy) {
  final n = math.pi * (1 - 2 * gy / kContourStepsPerTile / _worldTiles);
  return math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
}

/// Das Feld eines Fensters: Höhen in Metern auf dem (ausgedünnten)
/// Weltraster, zeilenweise von Nord nach Süd.
class ContourField {
  const ContourField({
    required this.values,
    required this.cols,
    required this.rows,
    required this.gx0,
    required this.gy0,
    required this.factor,
  });

  final Int32List values;
  final int cols;
  final int rows;

  /// Die erste Probe im Weltraster (Nordwest-Ecke des Fensters).
  final int gx0;
  final int gy0;

  /// Abstand zweier Proben in Weltraster-Schritten.
  final int factor;

  /// Für die Maschine: Sie gibt Zeile + 0,5 herein (Zellmitte), die
  /// Proben hier liegen auf den ganzen Zahlen — deshalb − 0,5.
  double latAtRow(double row) => contourLatAt(gy0 + (row - 0.5) * factor);
  double lonAtColumn(double column) => contourLonAt(gx0 + (column - 0.5) * factor);

  /// Meter zwischen zwei Nachbarproben auf der mittleren Breite.
  double get metersPerSample {
    final lat = contourLatAt(gy0 + (rows - 1) * factor / 2);
    return 40075016.686 * math.cos(lat * math.pi / 180) / (_worldTiles * kContourStepsPerTile) * factor;
  }

  bool get isEmpty => values.every((v) => v == kContourNoData);

  /// Die kleinste und größte Höhe — null ohne Daten.
  ({int min, int max})? get range {
    int? low, high;
    for (final v in values) {
      if (v == kContourNoData) continue;
      if (low == null || v < low) low = v;
      if (high == null || v > high) high = v;
    }
    return low == null ? null : (min: low, max: high!);
  }
}

/// Baut das Feld aus den Kacheln des Fensters ([tileAt] liefert null, wo
/// es keine gibt). Eine Probe auf einer Kachelkante gehört beiden
/// Nachbarn; fehlt der eine, liest sie der andere an seinem Rand —
/// dieselbe Regel wie `HeightReader.heightAt`.
///
/// **Geglättet wird über das ganze Fenster, behalten nur das Innere**:
/// Am äußersten Ring fehlen dem 3 × 3 die Nachbarn, sein Mittel hinge
/// also davon ab, wo das Fenster endet — und das Fenster wandert mit dem
/// Ausschnitt. Ohne den Schnitt sprängen die Linien am alten Rand, sobald
/// eine neue Kachelreihe dazukommt. Jede Probe, die bleibt, hat damit in
/// jedem Fenster denselben Wert (Test).
ContourField contourFieldFrom(
  ContourWindow window,
  HeightTile? Function(int x, int y) tileAt, {
  int? factor,
  bool smooth = kContourSmooth,
}) {
  final f = factor ?? contourSampleFactor(window);
  const s = kContourStepsPerTile;
  final gx0 = window.x0 * s;
  final gy0 = window.y0 * s;
  final cols = window.columns * s ~/ f + 1;
  final rows = window.rows * s ~/ f + 1;
  final raw = Int32List(cols * rows);

  int sampleAt(int gx, int gy) {
    final tx = gx ~/ s, c = gx % s;
    final ty = gy ~/ s, r = gy % s;
    final xs = [(tx, c), if (c == 0) (tx - 1, s)];
    final ys = [(ty, r), if (r == 0) (ty - 1, s)];
    for (final (x, cc) in xs) {
      for (final (y, rr) in ys) {
        final tile = tileAt(x, y);
        if (tile == null) continue;
        final v = tile.valueAt(cc, rr);
        if (v != kHeightNoData) return v;
      }
    }
    return kContourNoData;
  }

  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < cols; col++) {
      raw[row * cols + col] = sampleAt(gx0 + col * f, gy0 + row * f);
    }
  }
  if (!smooth) {
    return ContourField(values: raw, cols: cols, rows: rows, gx0: gx0, gy0: gy0, factor: f);
  }
  final smoothed = smooth3x3(raw, width: cols, height: rows, noData: kContourNoData);
  final inner = Int32List((cols - 2) * (rows - 2));
  for (var row = 1; row < rows - 1; row++) {
    inner.setRange((row - 1) * (cols - 2), row * (cols - 2), smoothed, row * cols + 1);
  }
  return ContourField(values: inner, cols: cols - 2, rows: rows - 2, gx0: gx0 + f, gy0: gy0 + f, factor: f);
}

/// Wie viele HÖHENMETER ein Bildschirmpixel typischerweise überwindet —
/// das 75. Perzentil der Höhenunterschiede zwischen Nachbarproben, damit
/// sich die Dichte nach dem bewegteren Viertel richtet (Talboden plus
/// Steilhang hätte sonst einen niedrigen Median, und die Linien wären
/// genau dort zu dicht, wo man sie lesen will). Null bei zu wenig Daten.
double? reliefPerPixel(ContourField field, {required double pixelsPerSample}) {
  final steps = <int>[];
  for (var y = 0; y < field.rows; y++) {
    final row = y * field.cols;
    for (var x = 0; x < field.cols; x++) {
      final here = field.values[row + x];
      if (here == kContourNoData) continue;
      if (x + 1 < field.cols) {
        final right = field.values[row + x + 1];
        if (right != kContourNoData) steps.add((here - right).abs());
      }
      if (y + 1 < field.rows) {
        final below = field.values[row + field.cols + x];
        if (below != kContourNoData) steps.add((here - below).abs());
      }
    }
  }
  if (steps.length < 8) return null;
  steps.sort();
  return steps[(steps.length * 3) ~/ 4] / pixelsPerSample;
}

/// Die Äquidistanz, die auf DIESEM Gelände bei DIESER Auflösung noch
/// etwas sagt — null heißt gar nicht zeichnen. Die Regel ist ein Satz:
/// Zwei Nachbarlinien näher als [minSpacingPixels] sind eine Schraffur,
/// also `Äquidistanz ≥ Abstand · Relief je Pixel`. Im Flachen ist das
/// nah dran 10 m, in den Alpen bei derselben Zoomstufe 50 oder 100.
int? contourEquidistanceM({
  required double reliefPerPixel,
  double minSpacingPixels = kContourMinLineSpacingPixels,
}) {
  final needed = minSpacingPixels * reliefPerPixel;
  for (final step in kContourSteps) {
    if (step >= needed) return step;
  }
  return null;
}

/// Der Höhenabstand der Hauptlinien bei dieser Äquidistanz — ein
/// Vielfaches davon, mindestens [kContourIndexEveryM] und mindestens das
/// Doppelte (10 → 100, 20 → 100, 50 → 100, 100 → 200, 200 → 400).
int contourIndexStepM(int equidistanceM) =>
    equidistanceM * math.max(2, (kContourIndexEveryM / equidistanceM).ceil());

/// Die Stufen, die im Feld überhaupt vorkommen.
List<int> contourLevelsIn(ContourField field, int equidistanceM) {
  final range = field.range;
  if (range == null) return const [];
  final first = (range.min ~/ equidistanceM + 1) * equidistanceM;
  return [for (var l = first; l <= range.max; l += equidistanceM) l];
}

/// Was ein Lauf ergibt: die Linien, die Äquidistanz, die WIRKLICH
/// gezeichnet wurde (nach der Punktschranke kann sie gröber sein), und
/// die Kennung, auf der die MapLibre-Seite idempotent ist.
class TerrainContours {
  const TerrainContours({
    required this.lines,
    required this.equidistanceM,
    required this.metersPerPixel,
    required this.key,
  });

  final List<ContourLine> lines;
  final int equidistanceM;

  /// Der Maßstab, für den gezogen wurde — die Zahlen für flutter_map
  /// rechnen ihren Abstand damit.
  final double metersPerPixel;
  final String key;
}

/// Warum ein Lauf keine Linien hat.
enum ContourGap {
  /// Zu wenig Höhen im Fenster — keine Kacheln (weder Bereich noch Host).
  noHeights,

  /// Das Gelände ist bei diesem Maßstab zu bewegt (selbst 200 m wären
  /// eine Schraffur) — erst näher heran.
  tooFarOut,
}

/// Was in den Rechen-Isolate geht: das Feld und der Maßstab.
class ContourJob {
  const ContourJob({required this.field, required this.metersPerPixel, required this.key});

  final ContourField field;

  /// Meter Gelände je logischem Bildschirmpixel — bewusst keine
  /// Zoomstufe: MapLibre und flutter_map zählen Zoom verschieden
  /// (PilzBuddy 1.98.0 lag auf Android damit eine Stufe daneben).
  final double metersPerPixel;

  /// Fenster und Faktor — der Maßstab kommt beim Ergebnis dazu.
  final String key;
}

/// Zieht die Höhenlinien für ein Feld — läuft im Isolate. Entweder
/// Linien oder ein Grund ([ContourGap]), nie beides.
({TerrainContours? contours, ContourGap? gap}) computeContours(
  ContourJob job, {
  int pointBudget = kContourPointBudget,
  double minLinePixels = kContourMinLinePixels,
  double minSpacingPixels = kContourMinLineSpacingPixels,
  double simplifyPixels = kContourSimplifyPixels,
}) {
  final field = job.field;
  final pixelsPerSample = field.metersPerSample / job.metersPerPixel;
  final relief = reliefPerPixel(field, pixelsPerSample: pixelsPerSample);
  if (relief == null) return (contours: null, gap: ContourGap.noHeights);
  var equidistance = contourEquidistanceM(reliefPerPixel: relief, minSpacingPixels: minSpacingPixels);
  if (equidistance == null) return (contours: null, gap: ContourGap.tooFarOut);

  // Beide Schwellen der Maschine in PIXELN gerechnet — eine feste Zahl in
  // Proben wäre nah dran am schärfsten, wo sie am wenigsten darf.
  final tolerance = simplifyPixels / pixelsPerSample;
  final minChain = math.max(2, (minLinePixels / pixelsPerSample).round());

  List<ContourLine> draw(int step) => contourLines(
        values: field.values,
        width: field.cols,
        height: field.rows,
        noData: kContourNoData,
        levels: contourLevelsIn(field, step),
        latAtRow: field.latAtRow,
        lonAtColumn: field.lonAtColumn,
        toleranceCells: tolerance,
        minChainCells: minChain,
        isIndex: (level) => level % contourIndexStepM(step) == 0,
      );

  var lines = draw(equidistance);
  final points = lines.fold<int>(0, (n, l) => n + l.points.length);
  if (points > pointBudget) {
    // Genau EINMAL vergröbern: Die nächste Stufe halbiert die Linienzahl
    // ohnehin, ein zweiter Durchgang kostete so viel wie der erste.
    final coarser = kContourSteps.firstWhere((s) => s > equidistance!, orElse: () => equidistance!);
    if (coarser != equidistance) {
      equidistance = coarser;
      lines = draw(coarser);
    }
  }
  return (
    contours: TerrainContours(
      lines: lines,
      equidistanceM: equidistance,
      metersPerPixel: job.metersPerPixel,
      key: '${job.key}|$equidistance|${job.metersPerPixel.toStringAsFixed(2)}',
    ),
    gap: null,
  );
}

/// Ein Platz für eine Zahl an einer Hauptlinie — für flutter_map, das
/// keinen Text entlang einer Linie kann (dort ist eine Zahl ein Marker mit
/// Winkel). MapLibre setzt sie selbst (`symbol-placement: line`).
class ContourLabel {
  const ContourLabel({required this.point, required this.angleRadians, required this.level});

  final LatLng point;

  /// Drehung im Uhrzeigersinn für `Transform.rotate`, nie kopfüber.
  final double angleRadians;

  /// Die Höhe in Metern — das, was dort steht.
  final int level;
}

/// Verteilt Zahlen auf die Hauptlinien, etwa alle [spacingPixels]; kurze
/// Linien bekommen keine (eine Zahl überdeckte den ganzen Stummel).
List<ContourLabel> contourLabels(
  List<ContourLine> lines, {
  required double metersPerPixel,
  double spacingPixels = 420,
  double minLinePixels = 140,
}) {
  final spacing = spacingPixels * metersPerPixel;
  final minLength = minLinePixels * metersPerPixel;
  final labels = <ContourLabel>[];
  for (final line in lines) {
    if (!line.index || line.points.length < 2) continue;
    final segments = <double>[];
    var total = 0.0;
    for (var i = 1; i < line.points.length; i++) {
      final m = _metersBetween(line.points[i - 1], line.points[i]);
      segments.add(m);
      total += m;
    }
    if (total < minLength) continue;
    final count = math.max(1, (total / spacing).floor());
    final step = total / (count + 1);
    // Die Plätze VORHER festlegen — im Gehen hochgezählt rutschte der
    // letzte durch Rundung auf das Linienende.
    final targets = [for (var k = 1; k <= count; k++) k * step];
    var placed = 0;
    var walked = 0.0;
    for (var i = 0; i < segments.length && placed < targets.length; i++) {
      final next = walked + segments[i];
      while (placed < targets.length && targets[placed] <= next) {
        final from = line.points[i];
        final to = line.points[i + 1];
        final t = segments[i] == 0 ? 0.0 : (targets[placed] - walked) / segments[i];
        labels.add(ContourLabel(
          point: LatLng(
            from.latitude + (to.latitude - from.latitude) * t,
            from.longitude + (to.longitude - from.longitude) * t,
          ),
          angleRadians: _uprightAngle(from, to),
          level: line.level,
        ));
        placed++;
      }
      walked = next;
    }
  }
  return labels;
}

double _metersBetween(LatLng a, LatLng b) {
  final midLat = (a.latitude + b.latitude) / 2 * math.pi / 180;
  final dx = (b.longitude - a.longitude) * 111320 * math.cos(midLat);
  final dy = (b.latitude - a.latitude) * 110574;
  return math.sqrt(dx * dx + dy * dy);
}

/// Der Winkel der Strecke auf dem Schirm, bei Bedarf um 180° gedreht.
double _uprightAngle(LatLng from, LatLng to) {
  final midLat = (from.latitude + to.latitude) / 2 * math.pi / 180;
  final dx = (to.longitude - from.longitude) * math.cos(midLat);
  final dy = -(to.latitude - from.latitude); // Bildschirm-y wächst nach unten
  var angle = math.atan2(dy, dx);
  if (angle > math.pi / 2) angle -= math.pi;
  if (angle < -math.pi / 2) angle += math.pi;
  return angle;
}

/// Meter Gelände je logischem Pixel aus Sichtfenster und Breite des
/// Kartenfensters — über die BREITE, weil Längengrade in Mercator linear
/// abgebildet werden.
double groundResolution({
  required double west,
  required double east,
  required double south,
  required double north,
  required double widthPixels,
}) {
  if (widthPixels <= 0) return double.infinity;
  final lat = (north + south) / 2;
  return (east - west) * 111320 * math.cos(lat * math.pi / 180) / widthPixels;
}

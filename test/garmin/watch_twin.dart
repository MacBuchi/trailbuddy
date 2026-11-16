// Das Dart-Abbild der Uhr-Ansicht (#511, Prüfleiter S4): zeichnet, was
// `garmin/source/NavView.mc` zeichnet, aus denselben Layoutzahlen
// (`tool/watch_layout.json`) und mit den im Simulator gemessenen
// Schriftmaßen (`tool/watch_fonts/<gerät>.json`) — für Größen und lange
// Texte, die der Simulator im Container (S1c) nicht zeigt.
//
// Was es NICHT ist: ein Beweis, dass Monkey C dasselbe zeichnet. Text
// steht als Kästchen je Zeichen in der gemessenen Breite (CI hat die
// Schriften der Uhr nicht), die Karte ist vereinfacht. Wer die Ansicht
// ändert, ändert dieses Abbild mit (Konzept-Garmin 12.2).
//
// Gerastert wird hier selbst, ohne Glättung wie auf MIP — so sind die
// Bilder auf Mac und Linux bildpunktgleich (Skia rastert dort nicht gleich).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// --- Quellen ------------------------------------------------------------------

/// Die Layoutzahlen für eine Breite (Regel im Kopf von watch_layout.json).
class WatchLayout {
  WatchLayout._(this.size, this._values, this._fonts);

  final int size;
  final Map<String, int> _values;
  final Map<String, String> _fonts;

  static Map<String, dynamic> raw() =>
      jsonDecode(File('tool/watch_layout.json').readAsStringSync()) as Map<String, dynamic>;

  factory WatchLayout.forSize(int size) {
    final j = raw();
    final base = j['base'] as int;
    final over = ((j['overrides'] as Map<String, dynamic>)['$size'] as Map<String, dynamic>?) ?? {};
    final values = <String, int>{};
    (j['values'] as Map<String, dynamic>).forEach((k, v) {
      final e = v as Map<String, dynamic>;
      final n = e['v'] as int;
      values[k] = over[k] as int? ?? (e['fixed'] == true ? n : (n * size / base).round());
    });
    return WatchLayout._(size, values, (j['fonts'] as Map<String, dynamic>).cast<String, String>());
  }

  int v(String name) => _values[name] ?? (throw ArgumentError('watch_layout.json: values.$name fehlt'));
  String font(String name) => _fonts[name] ?? (throw ArgumentError('watch_layout.json: fonts.$name fehlt'));
}

class WatchFont {
  WatchFont(this.height, this.ascent, this.descent, this.chars);

  final int height;
  final int ascent;
  final int descent;
  final Map<String, int> chars;

  /// Breite wie `getTextWidthInPixels`: Summe der Zeichen — gemessen ohne
  /// Unterschneidung (`kerning` leer). Ein unbekanntes Zeichen zählt wie „?".
  int width(String s) => s.runes.fold(0, (a, r) => a + (chars[String.fromCharCode(r)] ?? chars['?']!));
}

class WatchDevice {
  WatchDevice._(this.id, this.screen, this.fonts);

  final String id;
  final int screen;
  final Map<String, WatchFont> fonts;

  factory WatchDevice.load(String id) {
    final j = jsonDecode(File('tool/watch_fonts/$id.json').readAsStringSync()) as Map<String, dynamic>;
    final fonts = <String, WatchFont>{};
    (j['fonts'] as Map<String, dynamic>).forEach((k, v) {
      final f = v as Map<String, dynamic>;
      fonts[k] = WatchFont(f['height'] as int, f['ascent'] as int, f['descent'] as int,
          (f['chars'] as Map<String, dynamic>).cast<String, int>());
    });
    return WatchDevice._(id, j['screen'] as int, fonts);
  }

  static List<String> all() => (WatchLayout.raw()['devices'] as List).cast<String>();
}

/// Die Texte der Uhr: Englisch aus `resources`, Deutsch aus `resources-deu`.
Map<String, String> watchStrings(String lang) {
  Map<String, String> read(String dir) {
    final xml = File('garmin/$dir/strings/strings.xml').readAsStringSync();
    return {
      for (final m in RegExp(r'<string id="(\w+)">(.*?)</string>').allMatches(xml))
        m.group(1)!: m.group(2)!.replaceAll(r'\n', '\n').replaceAll('&amp;', '&'),
    };
  }

  final en = read('resources');
  return lang == 'deu' ? {...en, ...read('resources-deu')} : en;
}

/// Die Farben aus `garmin/source/Colors.mc` (dort die Herleitung).
Map<String, int> watchColors() {
  final src = File('garmin/source/Colors.mc').readAsStringSync();
  return {
    for (final m in RegExp(r'const (\w+) = 0x([0-9A-Fa-f]{6});').allMatches(src))
      m.group(1)!: 0xFF000000 | int.parse(m.group(2)!, radix: 16),
  };
}

List<int> watchLogo() =>
    ((jsonDecode(File('garmin/resources/logo/logo.json').readAsStringSync()) as Map)['d'] as List).cast<int>();

int unpackHi(int v) {
  final h = (v >> 16) & 0xFFFF;
  return h >= 0x8000 ? h - 0x10000 : h;
}

int unpackLo(int v) {
  final l = v & 0xFFFF;
  return l >= 0x8000 ? l - 0x10000 : l;
}

// --- Raster -------------------------------------------------------------------

/// Ein Bildspeicher ohne Glättung, wie die MIP-Anzeige.
class MipCanvas {
  MipCanvas(this.w) : px = Uint32List(w * w);

  final int w;
  final Uint32List px;

  void set(int x, int y, int c) {
    if (x < 0 || y < 0 || x >= w || y >= w) return;
    px[y * w + x] = c;
  }

  void clear(int c) => px.fillRange(0, px.length, c);

  void rect(int x, int y, int rw, int rh, int c) {
    for (var yy = y; yy < y + rh; yy++) {
      for (var xx = x; xx < x + rw; xx++) {
        set(xx, yy, c);
      }
    }
  }

  void circle(int cx, int cy, int r, int c) {
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        if (dx * dx + dy * dy <= r * r) set(cx + dx, cy + dy, c);
      }
    }
  }

  void roundRect(int x, int y, int rw, int rh, int rad, int c) {
    for (var yy = y; yy < y + rh; yy++) {
      for (var xx = x; xx < x + rw; xx++) {
        final ex = xx < x + rad ? x + rad - xx : (xx >= x + rw - rad ? xx - (x + rw - rad - 1) : 0);
        final ey = yy < y + rad ? y + rad - yy : (yy >= y + rh - rad ? yy - (y + rh - rad - 1) : 0);
        if (ex * ex + ey * ey <= rad * rad) set(xx, yy, c);
      }
    }
  }

  /// Ein Vieleck, Bildpunkt in der Mitte gegen die Kanten (gerade/ungerade).
  void polygon(List<List<num>> pts, int c) {
    final ys = pts.map((p) => p[1]);
    final y0 = ys.reduce(math.min).floor();
    final y1 = ys.reduce(math.max).ceil();
    for (var y = y0; y <= y1; y++) {
      final fy = y + 0.5;
      final xs = <double>[];
      for (var i = 0; i < pts.length; i++) {
        final a = pts[i];
        final b = pts[(i + 1) % pts.length];
        if ((a[1] <= fy) != (b[1] <= fy)) {
          xs.add(a[0] + (fy - a[1]) * (b[0] - a[0]) / (b[1] - a[1]));
        }
      }
      xs.sort();
      for (var i = 0; i + 1 < xs.length; i += 2) {
        for (var x = xs[i].round(); x < xs[i + 1].round(); x++) {
          set(x, y, c);
        }
      }
    }
  }

  void line(num x1, num y1, num x2, num y2, int width, int c) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return;
    final nx = -dy / len * width / 2;
    final ny = dx / len * width / 2;
    polygon([
      [x1 + nx, y1 + ny], [x2 + nx, y2 + ny], [x2 - nx, y2 - ny], [x1 - nx, y1 - ny],
    ], c);
  }

  /// Ring um die Mitte: Radius [r], Breite [width], von Anteil [f0] bis
  /// [f1] der Route (0 rechts neben der Lücke oben, im Uhrzeigersinn).
  void ringArc(int r, int width, double f0, double f1, int gapDeg, int c) {
    final m = w / 2;
    for (var y = 0; y < w; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x + 0.5 - m;
        final dy = y + 0.5 - m;
        final d = math.sqrt(dx * dx + dy * dy);
        if ((d - r).abs() > width / 2) continue;
        final theta = math.atan2(-dy, dx) * 180 / math.pi;
        final along = ((90 - gapDeg / 2 - theta) % 360 + 360) % 360;
        final f = along / (360 - gapDeg);
        if (f >= f0 && f <= f1) set(x, y, c);
      }
    }
  }

  /// Ein Ring zwischen [r0] und [r1] (der schwarze Rand der Karte).
  void annulus(double r0, double r1, int c) {
    final m = w / 2;
    for (var y = 0; y < w; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x + 0.5 - m;
        final dy = y + 0.5 - m;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d >= r0 && d <= r1) set(x, y, c);
      }
    }
  }

  /// Außerhalb der runden Anzeige grau — dort ist keine Anzeige.
  void maskRound() {
    final m = w / 2;
    for (var y = 0; y < w; y++) {
      for (var x = 0; x < w; x++) {
        final dx = x + 0.5 - m;
        final dy = y + 0.5 - m;
        if (dx * dx + dy * dy > m * m) px[y * w + x] = kOutside;
      }
    }
  }

  img.Image toImage() {
    final im = img.Image(width: w, height: w);
    for (var y = 0; y < w; y++) {
      for (var x = 0; x < w; x++) {
        final c = px[y * w + x];
        im.setPixelRgb(x, y, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF);
      }
    }
    return im;
  }
}

/// Keine MIP-Farbe: außerhalb des Kreises.
const kOutside = 0xFF7F7F7F;

/// Leerraum links und rechts in einer Zeile, den die Summe der Breiten
/// mitzählt (siehe [WatchTwin.text]).
const kBearing = 2;

/// So weit darf ein Zeichen über den sichtbaren Kreis reichen (Raster).
const kSlack = 1.0;

// --- Stand der Ansicht ------------------------------------------------------

/// Was #508 als Stand der Ansicht kennt, so weit es das Bild ändert.
enum TwinPhase { overview, map, offRoute, free, freeWaiting, arrived, ride, mountain, bests, loader, ended, broken }

/// Die Infofläche der Karte.
enum TwinFooter { trailAhead, onTrail, toGoal }

/// Die Aufzeichnung: [RideLog.IDLE], läuft, Pause, auf einem Trail.
enum TwinRec { idle, recording, paused, trail }

class TwinScene {
  const TwinScene(this.name, this.phase,
      {this.footer = TwinFooter.trailAhead,
      this.rec = TwinRec.recording,
      this.ask = false,
      this.askBig = false,
      this.toast,
      this.phone = false,
      this.storageFull = false,
      this.trails = 6,
      this.loaderText});

  final String name;
  final TwinPhase phase;
  final TwinFooter footer;
  final TwinRec rec;
  final bool ask;
  final bool askBig;
  /// Schlüssel eines Texts aus strings.xml für die Einblendung.
  final String? toast;
  final bool phone;
  final bool storageFull;
  final int trails;
  /// Schlüssel des Laders (Loading, RouteComing, RideWaits, NavEnded …).
  final String? loaderText;
}

/// Die längsten Werte, die eine Fahrt vernünftig bringt (#511: „längster
/// Trailname, dreistellige km").
class TwinValues {
  static const trailName = 'Schlosswald-Trail Nordabfahrt';
  static const grade = 2;
  static const headM = 12345.0;
  static const headClimbM = 1234.0;
  static const restOnTrailM = 987.0;
  static const remainingM = 123456.0;
  static const climbLeftM = 2345.0;
  static const offM = 1234.0;
  static const distanceM = 123456.0;
  static const movingS = 35940.0; // 9:59 h, 599 min
  static const climbM = 2345.0;
  static const speed = '45';
  static const pulse = '188';
  static const gradePct = '-12';
  static const altitude = '3456 m';
  static const clock = '23:59';
  static const wheelieM = '123';
  static const airMs = 1234;
  static const angle = '45°';
  static const counts = '123';
  static const routeLengthM = 123456.0;
}

/// Ein gezeichneter Text (oder ein Hindernis wie ein Trennstrich), mit
/// dem Bereich, in dem seine Zeichen stehen, und dem Kreis, in dem er
/// sichtbar ist (Karte und Seiten: innerhalb des Rings; was danach
/// gezeichnet wird: die ganze Anzeige).
class TwinBox {
  TwinBox(this.id, this.text, this.x0, this.y0, this.x1, this.y1, this.clipR,
      {this.text2 = true, this.overlay = false});

  final String id;
  final String text;
  final int x0, y0, x1, y1;
  final double clipR;
  /// false: kein Text, nur ein Hindernis für die Überdeckung.
  final bool text2;
  /// Liegt mit eigenem Grund über dem Inhalt (Schild der Aufzeichnung,
  /// Frage, Einblendung) — überdeckt ihn absichtlich.
  final bool overlay;

  @override
  String toString() => '$id „$text" [$x0..$x1, $y0..$y1]';
}

// --- Das Abbild ---------------------------------------------------------------

class WatchTwin {
  WatchTwin(this.device, this.lang)
      : w = device.screen,
        l = WatchLayout.forSize(device.screen),
        s = watchStrings(lang),
        c = watchColors(),
        canvas = MipCanvas(device.screen);

  final WatchDevice device;
  final String lang;
  final int w;
  final WatchLayout l;
  final Map<String, String> s;
  final Map<String, int> c;
  final MipCanvas canvas;
  final boxes = <TwinBox>[];

  /// Sichtbarer Radius für das, was gerade gezeichnet wird.
  double _clip = 0;
  bool _overlay = false;

  static const gapDeg = 4; // TbRing.GAP_DEG

  String get sep => s['DecimalSep']!;
  WatchFont f(String name) => device.fonts[l.font(name)]!;
  int col(String name) => c[name] ?? (throw ArgumentError('Colors.mc: $name fehlt'));

  // Zahlen wie NavView.km/seconds/clock/meters.
  String km(double m) {
    final t = (m / 100.0 + 0.5).floor();
    return '${t ~/ 10}$sep${t % 10}';
  }

  String seconds(int ms) {
    final t = (ms + 50) ~/ 100;
    return '${t ~/ 10}$sep${t % 10} s';
  }

  String clock(double secs) {
    final m = secs.truncate() ~/ 60;
    return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
  }

  String meters(double m) =>
      m < 1000 ? '${(m + 0.5).floor()} m' : (m < 10000 ? '${km(m)} km' : '${(m / 1000 + 0.5).floor()} km');

  // --- Text ------------------------------------------------------------------

  /// Wie `dc.drawText`: [x] links, Mitte oder rechts; [vcenter] legt die
  /// Mitte der Zeile auf [y]. Zeilen mit „\n" untereinander, je mittig.
  void text(String id, int x, int y, String fontName, String t, int color,
      {bool center = true, bool vcenter = false}) {
    final font = f(fontName);
    final lines = t.split('\n');
    var top = vcenter ? y - font.height * lines.length ~/ 2 : y;
    for (final line in lines) {
      final tw = font.width(line);
      final left = center ? x - tw ~/ 2 : x;
      _glyphs(font, left, top, line, color);
      // Die Zeichen stehen von Höhe − Ascent + 1 bis zur Grundlinie
      // (aus den Referenzbildern der fēnix 5, garmin/shots), Unterlängen
      // darunter.
      // Unterlängen zählen nicht (ein Komma unten am Rand stört nicht), und
      // die Zeichen beginnen gut 1 px nach ihrem Vorschub (im Bild der
      // fēnix 5: „NEBEN DER ROUTE" 39..200, Summe der Breiten 38..203).
      boxes.add(TwinBox(id, line, left + kBearing, top + font.height - font.ascent + 1, left + tw - kBearing,
          top + font.ascent, _clip, overlay: _overlay));
      top += font.height;
    }
  }

  /// Je Zeichen ein Kästchen in seiner Breite (1 px Luft), Kleinbuchstaben
  /// niedriger — gibt dem Bild den Rhythmus eines Worts.
  void _glyphs(WatchFont font, int x, int top, String line, int color) {
    final base = top + font.ascent;
    final cap = font.ascent - (font.height - font.ascent);
    for (final r in line.runes) {
      final ch = String.fromCharCode(r);
      final cw = font.chars[ch] ?? font.chars['?']!;
      if (ch.trim().isNotEmpty) {
        final low = ch.toLowerCase() == ch && ch.toUpperCase() != ch;
        final h = low ? (cap * 0.7).round() : cap;
        canvas.rect(x + 1, base - h, math.max(1, cw - 2), h, color);
      }
      x += cw;
    }
  }

  void obstacle(String id, int x0, int y0, int x1, int y1) =>
      boxes.add(TwinBox(id, '', x0, y0, x1, y1, _clip, text2: false, overlay: _overlay));

  void pill(String id, int cx, int y, String t, String fontName, int bg, int fg) {
    final font = f(fontName);
    final tw = font.width(t);
    final h = font.height;
    canvas.roundRect(cx - tw ~/ 2 - 8, y - h ~/ 2 - 1, tw + 16, h + 2, (h + 2) ~/ 2, bg);
    text(id, cx, y, fontName, t, fg, vcenter: true);
  }

  // --- Formen ----------------------------------------------------------------

  int chordAround(int cc, int r, int y) {
    final d = (y - cc).abs();
    if (d >= r) return 0;
    return (2 * math.sqrt(r * r - d * d)).truncate();
  }

  void shield(int x, int y, int g, int r, {required bool onMap}) {
    final cc = onMap ? col('S$g') : col('DS$g');
    final seam = onMap ? col('GROUND') : col('FIELD');
    for (var layer = 0; layer < 2; layer++) {
      final rr = layer == 0 ? r + 2 : r;
      final k = layer == 0 ? seam : cc;
      if (g == 2) {
        canvas.rect(x - rr, y - rr, 2 * rr + 1, 2 * rr + 1, k);
      } else if (g == 3) {
        final d = rr + 2;
        canvas.polygon([[x, y - d], [x + d, y], [x, y + d], [x - d, y]], k);
      } else {
        canvas.circle(x, y, rr, k);
      }
    }
    if (g == 0) canvas.circle(x, y, r - 3, seam);
    if (!onMap) obstacle('shield', x - r - 2, y - r - 2, x + r + 3, y + r + 3);
  }

  void field(int color) => canvas.rect(0, l.v('field_y'), w, w - l.v('field_y'), color);

  void mapBorder() {
    final mapR = l.v('map_r');
    final pw = w ~/ 2 - mapR + 2;
    final rc = (w ~/ 2 + mapR) ~/ 2 + 1;
    canvas.annulus(rc - pw / 2, rc + pw / 2, col('FIELD'));
  }

  void ring(double at, {bool off = false, bool arrived = false}) {
    final r = l.v('ring_r');
    final rw = l.v('ring_w');
    canvas.ringArc(r, rw, 0, 1, gapDeg, col('MUTED_DARK'));
    canvas.ringArc(r, rw, 0.30, 0.45, gapDeg, col('DS1'));
    canvas.ringArc(r, rw, 0.60, 0.70, gapDeg, col('DS2'));
    final a = arrived ? 1.0 : at;
    canvas.ringArc(r, rw, 0, a, gapDeg, off ? col('WARNING') : col('ROUTE'));
    final deg = (90 - gapDeg / 2 - a * (360 - gapDeg)) * math.pi / 180;
    final ux = math.cos(deg);
    final uy = -math.sin(deg);
    final cc = w ~/ 2;
    for (var layer = 0; layer < 2; layer++) {
      final g = layer == 0 ? 2 : 0;
      final half = 6 + g;
      final outer = cc + 1 + g;
      final inner = r - 11 - g;
      canvas.polygon([
        [cc + ux * outer - uy * half, cc + uy * outer + ux * half],
        [cc + ux * outer + uy * half, cc + uy * outer - ux * half],
        [cc + ux * inner, cc + uy * inner],
      ], layer == 0 ? col('FIELD') : col('TEXT_ON_FIELD'));
    }
  }

  void me(int cx, int cy) {
    canvas.polygon([[cx, cy - 18], [cx + 14, cy + 14], [cx, cy + 7], [cx - 14, cy + 14]], col('GROUND'));
    canvas.polygon([[cx, cy - 13], [cx + 11, cy + 11], [cx, cy + 5], [cx - 11, cy + 11]], col('TEXT'));
  }

  void north() {
    final r = l.v('map_r') - 14;
    final x = w ~/ 2;
    final y = w ~/ 2 - r;
    canvas.circle(x, y, 12, col('TEXT'));
    text('north', x, y, 'north', 'N', col('GROUND'), vcenter: true);
  }

  /// Die Route vereinfacht: gefahren dünn in Moos unter der Position, das
  /// Band nach oben, darauf ein Trail in seiner S-Farbe.
  void route({bool trail = false}) {
    final cx = w ~/ 2;
    final py = l.v('pos_y');
    canvas.line(cx, py, cx - 30, w, 3, col('ROUTE_EDGE'));
    canvas.line(cx, py, cx + 20, 0, 12, col('ROUTE_EDGE'));
    canvas.line(cx, py, cx + 20, 0, 8, col('ROUTE'));
    final t0 = trail ? py : py - 50;
    canvas.line(cx + 20 * (py - t0) / py, t0, cx + 20 * (py - 10) / py, 10, 4, col('S${TwinValues.grade}'));
    if (!trail) shield(cx + 20 * 50 ~/ py, py - 50, TwinValues.grade, 6, onMap: true);
  }

  // --- Teile der Ansicht -------------------------------------------------------

  void status(TwinScene sc, int y) {
    _overlay = true;
    final cx = w ~/ 2;
    final top = y == l.v('status_top_y');
    final idle = sc.rec == TwinRec.idle;
    String? t;
    var bg = col('FIELD');
    var fg = col('ROUTE');
    switch (sc.rec) {
      case TwinRec.idle:
        // Auf den Zahlenseiten nur ein grauer Punkt (#555).
        if (top) t = s['RecIdle'];
      case TwinRec.paused:
        t = s['RecPaused'];
        bg = col('WARNING');
        fg = col('TEXT_ON_FIELD');
      case TwinRec.trail:
        t = s['RecTrail'];
        bg = col('ROUTE');
        fg = col('TEXT');
      case TwinRec.recording:
        t = null;
    }
    if (t == null) {
      canvas.circle(cx, y, 6, col('GROUND'));
      canvas.circle(cx, y, 4, idle ? col('MUTED_DARK') : col('S2'));
    } else {
      pill('status', cx, y, t, 'status', bg, fg);
    }
    if (sc.ask) {
      ask(sc, top ? l.v('ask_y_map') : l.v('ask_y_page'));
      _overlay = false;
      return;
    }
    final toast = sc.toast;
    if (toast != null) {
      pill('toast', cx, top ? l.v('toast_y_map') : l.v('toast_y_page'), s[toast]!, 'toast', col('FIELD'),
          col('TEXT_ON_FIELD'));
    }
    _overlay = false;
  }

  void ask(TwinScene sc, int y) {
    pill('ask', w ~/ 2, y, s['AskReplan']!, 'ask', col('FIELD'), col('TEXT_ON_FIELD'));
    final bx = l.v('ask_bar_x');
    final by = y + l.v('ask_bar_dy');
    canvas.rect(bx, by, l.v('ask_bar_w') * 2 ~/ 3, 4, col('ROUTE'));
    obstacle('ask_bar', bx, by, bx + l.v('ask_bar_w'), by + 4);
    final yes = s['AskYes']!;
    pill('ask_yes', sc.askBig ? l.v('ask_yes_big_x') : l.v('ask_yes_x'), l.v('ask_yes_y'),
        sc.askBig ? 'START = $yes' : yes, sc.askBig ? 'ask_yes_big' : 'ask_yes', col('ROUTE'), col('TEXT'));
    pill('ask_no', l.v('ask_no_x'), l.v('ask_no_y'), s['AskNo']!, 'ask_no', col('MUTED_DARK'),
        col('TEXT_ON_FIELD'));
  }

  void shieldLine(int cx, int y, int g, String name) {
    var fontName = 'field_name';
    var font = f(fontName);
    var room = chordAround(cx, l.v('map_r'), y + font.ascent) - 22;
    var tw = font.width(name);
    if (tw > room) {
      fontName = 'field_name_small';
      font = f(fontName);
      room = chordAround(cx, l.v('map_r'), y + font.ascent) - 22;
      tw = font.width(name);
    }
    if (tw > room) {
      var cut = name.length;
      var shown = name;
      while (cut > 1 && tw > room) {
        cut--;
        shown = '${name.substring(0, cut)}…';
        tw = font.width(shown);
      }
      name = shown;
    }
    final x = cx - (tw + 20) ~/ 2;
    shield(x + 6, y + font.height ~/ 2, g, 5, onMap: false);
    text('field_name', x + 20, y, fontName, name, col('TEXT_ON_FIELD'), center: false);
  }

  void numberLine(int cx, int y, String dist, double? climb) {
    final up = climb != null && climb >= 1 ? climb.truncate().toString() : null;
    var fontName = 'number_line_3';
    var dw = 0;
    var uw = 0;
    for (final name in ['number_line', 'number_line_2', 'number_line_3']) {
      fontName = name;
      final font = f(name);
      dw = font.width(dist);
      uw = up == null ? 0 : font.width(up) + 22;
      final bottom = y + font.height - 4;
      if (dw + uw <= chordAround(cx, l.v('map_r') - 4, bottom)) break;
    }
    final font = f(fontName);
    final x = cx - (dw + uw) ~/ 2;
    text('number_line', x, y, fontName, dist, col('TEXT_ON_FIELD'), center: false);
    if (up != null) {
      final ax = x + dw + 14;
      final my = y + font.height ~/ 2;
      canvas.polygon([[ax, my - 7], [ax + 6, my + 4], [ax - 6, my + 4]], col('ROUTE'));
      text('number_line_up', ax + 8, y, fontName, up, col('ROUTE'), center: false);
    }
  }

  void climbText(String id, int cx, int y, double? m, int color) {
    const fontName = 'climb_value';
    final font = f(fontName);
    if (m == null) {
      text(id, cx, y, fontName, '--', color);
      return;
    }
    final t = '${m.truncate()} m';
    final tw = font.width(t);
    final x = cx - (tw + 14) ~/ 2;
    final my = y + font.height ~/ 2;
    canvas.polygon([[x + 5, my - 7], [x + 11, my + 4], [x - 1, my + 4]], col('ROUTE'));
    obstacle('${id}_arrow', x - 1, my - 7, x + 12, my + 4);
    text(id, x + 14, y, fontName, t, color, center: false);
  }

  void big(String unit, String value) {
    final cx = w ~/ 2;
    text('big_unit', cx, l.v('big_unit_y'), 'big_unit', unit, col('MUTED'));
    text('big_value', cx, l.v('big_value_y'), 'big_value', value, col('TEXT_ON_FIELD'));
    final rx = l.v('big_rule_x');
    final ry = l.v('big_rule_y');
    canvas.line(rx, ry, w - rx, ry, 2, col('MUTED_DARK'));
    obstacle('big_rule', rx, ry - 1, w - rx, ry + 1);
    final t = l.v('col_rule_top');
    final b = l.v('col_rule_bottom');
    canvas.line(cx, t, cx, b, 2, col('MUTED_DARK'));
    obstacle('col_rule', cx - 1, t, cx + 1, b);
  }

  int colX(int k) => w ~/ 2 + (k == 0 ? -l.v('col_x') : l.v('col_x'));

  void label(int k, int y, String name) => text('cell_label', colX(k), y, 'cell_label', name, col('MUTED'));

  void cell(int k, int y, String name, String value, int color) {
    label(k, y, name);
    text('cell_value', colX(k), y + l.v('cell_value_dy'), 'cell_value', value, color);
  }

  void loader(String t, {required bool full}) {
    canvas.clear(col('FIELD'));
    final dots = watchLogo();
    final cx = w ~/ 2;
    void draw(int to, int color) {
      for (var i = 0; i + 1 < dots.length; i += 2) {
        final rc = dots[i + 1];
        if (to >= 0 && unpackLo(rc) > to) return;
        final xy = dots[i];
        canvas.circle(cx + unpackHi(xy) ~/ 10, l.v('logo_y') + unpackLo(xy) ~/ 10, unpackHi(rc) ~/ 10, color);
      }
    }

    if (!full) draw(-1, col('MUTED_DARK'));
    draw(full ? -1 : 900, col('ROUTE'));
    final y = t.contains('\n') ? l.v('two_line_text_y') : l.v('loader_text_y');
    text('loader_text', cx, y, 'loader_text', t, col('MUTED'));
  }

  // --- Ganze Bilder ----------------------------------------------------------

  void draw(TwinScene sc) {
    final cx = w ~/ 2;
    final inRing = (l.v('ring_r') - l.v('ring_w') / 2).toDouble();
    final mapR = l.v('map_r').toDouble();
    final screen = w / 2;
    final fy = l.v('field_y');
    final l1 = fy + l.v('field_line1_dy');
    final l2 = fy + l.v('field_line2_dy');
    switch (sc.phase) {
      case TwinPhase.loader:
      case TwinPhase.ended:
        _clip = screen;
        final key = sc.loaderText ?? (sc.phase == TwinPhase.ended ? 'NavEnded' : 'Loading');
        final t = key == 'Loading' ? '${s['Loading']} 100 %' : s[key]!;
        loader(t, full: sc.phase == TwinPhase.ended);
      case TwinPhase.broken:
        _clip = screen;
        canvas.clear(col('GROUND'));
        text('route_broken', cx, w ~/ 2, 'route_broken', s['RouteBroken']!, col('TEXT'), vcenter: true);
      case TwinPhase.overview:
        canvas.clear(col('GROUND'));
        _clip = mapR;
        // Die Linie als Kreis im Radius der Übersicht um die Mitte.
        final r = l.v('overview_r').toDouble();
        canvas.annulus(r - 6, r + 6, col('ROUTE_EDGE'));
        canvas.annulus(r - 4, r + 4, col('ROUTE'));
        field(col('FIELD'));
        text('field_note', cx, l1, 'field_note', s['WaitGps']!, col('MUTED'));
        numberLine(cx, l2, meters(TwinValues.routeLengthM), TwinValues.climbLeftM);
        text('version', cx, l.v('version_y'), 'version', 'v1.6.0-dev', col('MUTED_DARK'));
        mapBorder();
        _clip = screen;
        ring(0);
        status(sc, l.v('status_top_y'));
      case TwinPhase.map:
      case TwinPhase.offRoute:
        canvas.clear(col('GROUND'));
        _clip = mapR;
        final off = sc.phase == TwinPhase.offRoute;
        route(trail: sc.footer == TwinFooter.onTrail && !off);
        north();
        me(cx, l.v('pos_y'));
        if (sc.phone) {
          final py = l.v('pos_y');
          canvas.polygon([[cx, py - 7], [cx + 6, py + 6], [cx, py + 3], [cx - 6, py + 6]], col('GROUND'));
          text('phone_gps', cx, py - l.v('phone_gps_dy'), 'phone_gps', s['PhoneGps']!, col('TEXT'), vcenter: true);
        }
        if (off) {
          field(col('WARNING'));
          text('off_title', cx, l1, 'off_title', s['OffRoute']!, col('TEXT_ON_FIELD'));
          text('off_value', cx, l2, 'off_value', meters(TwinValues.offM), col('TEXT_ON_FIELD'));
        } else {
          field(col('FIELD'));
          switch (sc.footer) {
            case TwinFooter.onTrail:
              shieldLine(cx, l1, TwinValues.grade, TwinValues.trailName);
              numberLine(cx, l2, meters(TwinValues.restOnTrailM), null);
            case TwinFooter.trailAhead:
              shieldLine(cx, l1, TwinValues.grade, TwinValues.trailName);
              numberLine(cx, l2, meters(TwinValues.headM), TwinValues.headClimbM);
            case TwinFooter.toGoal:
              text('field_note', cx, l1, 'field_note', s['ToGoal']!, col('MUTED'));
              numberLine(cx, l2, meters(TwinValues.remainingM), TwinValues.climbLeftM);
          }
        }
        mapBorder();
        _clip = screen;
        ring(0.38, off: off);
        status(sc, l.v('status_top_y'));
      case TwinPhase.free:
      case TwinPhase.freeWaiting:
        canvas.clear(col('GROUND'));
        _clip = mapR;
        final waiting = sc.phase == TwinPhase.freeWaiting;
        if (!waiting) {
          canvas.line(cx, l.v('pos_y'), cx - 40, w, 3, col('ROUTE_EDGE'));
          north();
          me(cx, l.v('pos_y'));
        }
        field(col('FIELD'));
        if (waiting) {
          text('field_note', cx, l1, 'field_note', s['WaitGps']!, col('MUTED'));
        } else {
          final note = s[sc.storageFull ? 'StorageFull' : 'FreeRide']!;
          text('field_note', cx, l1, 'field_note', sc.storageFull ? note : '$note · ${clock(TwinValues.movingS)} h',
              col('MUTED'));
          numberLine(cx, l2, meters(TwinValues.distanceM), TwinValues.climbM);
        }
        mapBorder();
        _clip = screen;
        status(sc, l.v('status_top_y'));
      case TwinPhase.arrived:
      case TwinPhase.ride:
      case TwinPhase.mountain:
      case TwinPhase.bests:
        canvas.clear(col('FIELD'));
        _clip = inRing;
        switch (sc.phase) {
          case TwinPhase.ride:
            big(s['Speed']!, TwinValues.speed);
            cell(0, l.v('cell_row1_y'), s['Time']!, clock(TwinValues.movingS), col('TEXT_ON_FIELD'));
            cell(1, l.v('cell_row1_y'), s['Distance']!, '${km(TwinValues.distanceM)} km', col('TEXT_ON_FIELD'));
            label(0, l.v('cell_row2_y'), s['Climbed']!);
            climbText('climb_value', colX(0), l.v('climb_row2_y'), TwinValues.climbM, col('TEXT_ON_FIELD'));
            cell(1, l.v('cell_row2_y'), s['Pulse']!, TwinValues.pulse, col('MUTED'));
          case TwinPhase.mountain:
            big(s['Grade']!, TwinValues.gradePct);
            cell(0, l.v('cell_row1_y'), s['Altitude']!, TwinValues.altitude, col('TEXT_ON_FIELD'));
            label(1, l.v('cell_row1_y'), s['ToTrail']!);
            climbText('climb_value', colX(1), l.v('climb_row1_y'), TwinValues.headClimbM, col('TEXT_ON_FIELD'));
            label(0, l.v('cell_row2_y'), s['ToFinish']!);
            climbText('climb_value', colX(0), l.v('climb_row2_y'), TwinValues.climbLeftM, col('TEXT_ON_FIELD'));
            cell(1, l.v('cell_row2_y'), s['Clock']!, TwinValues.clock, col('TEXT_ON_FIELD'));
          case TwinPhase.bests:
            big(s['WheelieM']!, TwinValues.wheelieM);
            cell(0, l.v('cell_row1_y'), s['Airtime']!, seconds(TwinValues.airMs), col('TEXT_ON_FIELD'));
            cell(1, l.v('cell_row1_y'), s['Angle']!, TwinValues.angle, col('TEXT_ON_FIELD'));
            cell(0, l.v('cell_row2_y'), s['Jumps']!, TwinValues.counts, col('TEXT_ON_FIELD'));
            cell(1, l.v('cell_row2_y'), s['Wheelies']!, TwinValues.counts, col('TEXT_ON_FIELD'));
          default:
            text('arrived_title', cx, l.v('arrived_title_y'), 'arrived_title', s['Arrived']!, col('ROUTE'));
            text('arrived_km', cx, l.v('arrived_km_y'), 'arrived_km', '${km(TwinValues.distanceM)} km',
                col('TEXT_ON_FIELD'));
            final row = l.v('arrived_row_y');
            text('arrived_time', cx - l.v('arrived_time_dx'), row, 'arrived_time', '${clock(TwinValues.movingS)} h',
                col('TEXT_ON_FIELD'));
            climbText('arrived_climb', cx + l.v('arrived_climb_dx'), row, TwinValues.climbM, col('TEXT_ON_FIELD'));
            var x = cx - (sc.trails - 1) * 10;
            for (var k = 0; k < sc.trails; k++) {
              shield(x, l.v('arrived_shields_y'), k % 4, 5, onMap: false);
              x += 20;
            }
            text('arrived_bests', cx, l.v('arrived_bests_y'), 'arrived_bests',
                '${s['AirShort']} ${seconds(TwinValues.airMs)}\n${s['WheelieShort']} ${TwinValues.wheelieM} m',
                col('MUTED'));
        }
        ring(0.38, arrived: sc.phase == TwinPhase.arrived);
        _clip = screen;
        status(sc, l.v('status_bottom_y'));
    }
    canvas.maskRound();
  }

  // --- Prüfung ------------------------------------------------------------------

  /// Was nicht passt: Zeichen außerhalb des sichtbaren Kreises, zwei
  /// Texte (oder Text und Strich) übereinander.
  List<String> problems() {
    final out = <String>[];
    final m = w / 2;
    bool inside(num x, num y, double r) {
      final dx = x - m;
      final dy = y - m;
      return dx * dx + dy * dy <= (r + kSlack) * (r + kSlack);
    }

    for (final b in boxes.where((b) => b.text2)) {
      final ok = inside(b.x0, b.y0, b.clipR) &&
          inside(b.x1, b.y0, b.clipR) &&
          inside(b.x0, b.y1, b.clipR) &&
          inside(b.x1, b.y1, b.clipR);
      if (!ok) out.add('außerhalb r ${b.clipR.toStringAsFixed(0)}: $b');
    }
    for (var i = 0; i < boxes.length; i++) {
      for (var j = i + 1; j < boxes.length; j++) {
        final a = boxes[i];
        final b = boxes[j];
        if (!a.text2 && !b.text2) continue;
        if (a.overlay != b.overlay) continue;
        final hit = a.x0 < b.x1 && b.x0 < a.x1 && a.y0 < b.y1 && b.y0 < a.y1;
        if (hit) out.add('überdeckt: $a ↔ $b');
      }
    }
    return out;
  }
}

/// Alle Bilder, die das Abbild zeichnet: jede Phase und jede Fußzeile, die
/// es gibt, die Frage auf Karte und Seite, Einblendungen, alle Stände der
/// Aufzeichnung — je mit den längsten Werten.
const kTwinScenes = <TwinScene>[
  TwinScene('uebersicht', TwinPhase.overview, rec: TwinRec.idle),
  TwinScene('anfahrt', TwinPhase.map, rec: TwinRec.idle),
  TwinScene('trail', TwinPhase.map, footer: TwinFooter.onTrail, rec: TwinRec.trail),
  TwinScene('ziel', TwinPhase.map, footer: TwinFooter.toGoal, rec: TwinRec.paused),
  TwinScene('abseits', TwinPhase.offRoute),
  TwinScene('handy_gps', TwinPhase.map, phone: true, rec: TwinRec.idle),
  TwinScene('frage', TwinPhase.map, ask: true, rec: TwinRec.idle),
  TwinScene('frage_gross', TwinPhase.map, ask: true, askBig: true, rec: TwinRec.idle),
  TwinScene('einblendung', TwinPhase.map, toast: 'TrailDiscarded', rec: TwinRec.idle),
  TwinScene('frei', TwinPhase.free),
  TwinScene('frei_voll', TwinPhase.free, storageFull: true, rec: TwinRec.paused),
  TwinScene('frei_ohne_gps', TwinPhase.freeWaiting, rec: TwinRec.idle),
  TwinScene('fahrt', TwinPhase.ride, rec: TwinRec.idle, storageFull: true),
  TwinScene('fahrt_frage', TwinPhase.ride, ask: true, askBig: true, rec: TwinRec.paused),
  TwinScene('berg', TwinPhase.mountain, toast: 'RideDiscarded', rec: TwinRec.idle),
  TwinScene('spruenge', TwinPhase.bests, rec: TwinRec.trail),
  TwinScene('angekommen', TwinPhase.arrived, trails: 8),
  TwinScene('lader', TwinPhase.loader),
  TwinScene('lader_wartet', TwinPhase.loader, loaderText: 'RideWaits'),
  TwinScene('beendet', TwinPhase.ended),
  TwinScene('unbrauchbar', TwinPhase.broken),
];

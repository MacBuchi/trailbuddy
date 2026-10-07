// Hostnamen mit Umlauten (#223): „mühle-trails.de" steht im Netz als
// „xn--mhle-trails-xxx.de" (Punycode, RFC 3492). Gespeichert wird die
// ASCII-Form, gezeigt die mit Umlauten — wie die Adresszeile des Browsers.
// Ohne Paket: Die Umrechnung ist kurz und vollständig festgelegt. Keine
// volle IDNA-Abbildung (Normalisierung, verbotene Zeichen): Wer eine
// Adresse eintippt, tippt sie so, wie der Browser sie zeigt.

const _base = 36, _tMin = 1, _tMax = 26, _skew = 38, _damp = 700;
const _initialBias = 72, _initialN = 128;
const _prefix = 'xn--';

int _adapt(int delta, int numPoints, bool firstTime) {
  delta = firstTime ? delta ~/ _damp : delta ~/ 2;
  delta += delta ~/ numPoints;
  var k = 0;
  while (delta > ((_base - _tMin) * _tMax) ~/ 2) {
    delta ~/= _base - _tMin;
    k += _base;
  }
  return k + (_base - _tMin + 1) * delta ~/ (delta + _skew);
}

int _threshold(int k, int bias) =>
    k <= bias ? _tMin : (k >= bias + _tMax ? _tMax : k - bias);

String _digit(int d) => String.fromCharCode(d < 26 ? 0x61 + d : 0x30 + d - 26);

int? _value(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30 + 26;
  if (c >= 0x41 && c <= 0x5a) return c - 0x41;
  if (c >= 0x61 && c <= 0x7a) return c - 0x61;
  return null;
}

/// Ein Label nach Punycode, ohne „xn--".
String _encode(String label) {
  final input = label.runes.toList();
  final out = StringBuffer()..writeAll(input.where((c) => c < 0x80).map(String.fromCharCode));
  final basic = out.length;
  var handled = basic;
  if (basic > 0) out.write('-');
  var n = _initialN, delta = 0, bias = _initialBias;
  while (handled < input.length) {
    final m = input.where((c) => c >= n).reduce((a, b) => a < b ? a : b);
    delta += (m - n) * (handled + 1);
    n = m;
    for (final c in input) {
      if (c < n) delta++;
      if (c != n) continue;
      var q = delta;
      for (var k = _base;; k += _base) {
        final t = _threshold(k, bias);
        if (q < t) break;
        out.write(_digit(t + (q - t) % (_base - t)));
        q = (q - t) ~/ (_base - t);
      }
      out.write(_digit(q));
      bias = _adapt(delta, handled + 1, handled == basic);
      delta = 0;
      handled++;
    }
    delta++;
    n++;
  }
  return out.toString();
}

/// Ein Label aus Punycode (ohne „xn--"); null, wenn es keins ist.
String? _decode(String label) {
  final cut = label.lastIndexOf('-');
  final out = <int>[...(cut < 0 ? '' : label.substring(0, cut)).codeUnits];
  if (out.any((c) => c >= 0x80)) return null;
  var n = _initialN, i = 0, bias = _initialBias;
  var pos = cut < 0 ? 0 : cut + 1;
  while (pos < label.length) {
    final oldI = i;
    var w = 1;
    for (var k = _base;; k += _base) {
      if (pos >= label.length) return null;
      final d = _value(label.codeUnitAt(pos++));
      if (d == null) return null;
      i += d * w;
      final t = _threshold(k, bias);
      if (d < t) break;
      w *= _base - t;
      if (i > 0x10FFFF * 4) return null;
    }
    bias = _adapt(i - oldI, out.length + 1, oldI == 0);
    n += i ~/ (out.length + 1);
    i %= out.length + 1;
    if (n > 0x10FFFF) return null;
    out.insert(i++, n);
  }
  return String.fromCharCodes(out);
}

/// „Mühle-Trails.de" → „xn--mhle-trails-xxx.de": klein geschrieben, jedes
/// Label mit Zeichen über ASCII nach Punycode. Reines ASCII bleibt.
String hostToAscii(String host) => host
    .toLowerCase()
    .split('.')
    .map((l) => l.runes.every((c) => c < 0x80) ? l : '$_prefix${_encode(l)}')
    .join('.');

/// Umkehrung von [hostToAscii]; ein kaputtes „xn--"-Label bleibt, wie es ist.
String hostToUnicode(String host) => host.split('.').map((l) {
      if (!l.toLowerCase().startsWith(_prefix)) return l;
      return _decode(l.substring(_prefix.length)) ?? l;
    }).join('.');

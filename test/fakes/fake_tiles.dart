// Eine Vektor-Kachel aus der Hand (Mapbox Vector Tile, wie Protomaps sie
// schreibt): die Ebene `roads` mit Linien in Kachel-Pixeln und den
// Eigenschaften `kind`/`kind_detail`. Für die Tests des Wege-Index (#29)
// — ein echter Kachelausschnitt läge im Repo als Binärblob ohne Aussage.
import 'dart:typed_data';

import 'package:vector_tile/raw/raw_vector_tile.dart' as raw;
import 'package:vector_tile/util/command.dart';

/// Eine Linie in Kachel-Pixeln (0 … [kTileExtent]) mit ihren Eigenschaften;
/// [extra] trägt, was die Routing-Engine liest (`access`, `service`,
/// `oneway`, `is_bridge`, `is_tunnel`) — Strings und Bools, wie Protomaps
/// sie schreibt.
typedef RoadLine = ({
  List<(int, int)> px,
  String kind,
  String? kindDetail,
  String layer,
  Map<String, Object> extra,
});

const kTileExtent = 4096;

RoadLine road(List<(int, int)> px, String kind,
        {String? kindDetail, String layer = 'roads', Map<String, Object> extra = const {}}) =>
    (px: px, kind: kind, kindDetail: kindDetail, layer: layer, extra: extra);

/// Kodiert die Linien je Ebene in EINE Kachel.
Uint8List mvtTile(List<RoadLine> lines) {
  final byLayer = <String, List<RoadLine>>{};
  for (final l in lines) {
    (byLayer[l.layer] ??= []).add(l);
  }
  final tile = raw.VectorTile();
  for (final entry in byLayer.entries) {
    final keys = <String>['kind', 'kind_detail'];
    int keyIndex(String k) {
      final i = keys.indexOf(k);
      if (i >= 0) return i;
      keys.add(k);
      return keys.length - 1;
    }

    final values = <raw.VectorTile_Value>[];
    int valueIndex(Object v) {
      final i = values.indexWhere((x) => switch (v) {
            final String s => x.hasStringValue() && x.stringValue == s,
            final bool b => x.hasBoolValue() && x.boolValue == b,
            _ => false,
          });
      if (i >= 0) return i;
      values.add(switch (v) {
        final String s => raw.VectorTile_Value(stringValue: s),
        final bool b => raw.VectorTile_Value(boolValue: b),
        _ => throw ArgumentError('Eigenschaft $v: nur String und bool'),
      });
      return values.length - 1;
    }

    final layer = raw.VectorTile_Layer(name: entry.key, extent: kTileExtent, version: 2);
    for (final l in entry.value) {
      final tags = <int>[0, valueIndex(l.kind)];
      if (l.kindDetail != null) tags.addAll([1, valueIndex(l.kindDetail!)]);
      for (final e in l.extra.entries) {
        tags.addAll([keyIndex(e.key), valueIndex(e.value)]);
      }
      final geometry = <int>[];
      var x = 0, y = 0;
      for (var i = 0; i < l.px.length; i++) {
        if (i == 0) {
          geometry.add((1 << 3) | 1); // MoveTo, 1
        } else if (i == 1) {
          geometry.add(((l.px.length - 1) << 3) | 2); // LineTo, n-1
        }
        final (px, py) = l.px[i];
        geometry.add(Command.zigZagEncode(px - x));
        geometry.add(Command.zigZagEncode(py - y));
        x = px;
        y = py;
      }
      layer.features.add(raw.VectorTile_Feature(
          type: raw.VectorTile_GeomType.LINESTRING, tags: tags, geometry: geometry));
    }
    layer.keys.addAll(keys);
    layer.values.addAll(values);
    tile.layers.add(layer);
  }
  return tile.writeToBuffer();
}

/// Eine Kachel des Wege-Archivs (#213, Format 2): Ebene `ways`, je Linie
/// `k` und optional `u` als uint — von Hand kodiert wie
/// `encode_tile` in `tool/way_archive.py`, weil `VectorTile_Value` dafür
/// `Int64` aus einem Paket verlangt, das hier nicht direkt abhängt.
Uint8List waysTile(List<({int k, int? u, List<(int, int)> px})> lines) {
  void varint(List<int> out, int v) {
    while (v >= 0x80) {
      out.add((v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.add(v);
  }

  void field(List<int> out, int no, List<int> bytes) {
    varint(out, (no << 3) | 2);
    varint(out, bytes.length);
    out.addAll(bytes);
  }

  final numbers = <int>{for (final l in lines) ...[l.k, ?l.u]}.toList()..sort();
  final layer = <int>[];
  varint(layer, (15 << 3) | 0);
  varint(layer, 2);
  field(layer, 1, 'ways'.codeUnits);
  for (final l in lines) {
    final tags = <int>[];
    varint(tags, 0);
    varint(tags, numbers.indexOf(l.k));
    if (l.u case final u?) {
      varint(tags, 1);
      varint(tags, numbers.indexOf(u));
    }
    final geom = <int>[];
    var x = 0, y = 0;
    for (var i = 0; i < l.px.length; i++) {
      if (i == 0) varint(geom, (1 << 3) | 1);
      if (i == 1) varint(geom, ((l.px.length - 1) << 3) | 2);
      final (px, py) = l.px[i];
      varint(geom, Command.zigZagEncode(px - x));
      varint(geom, Command.zigZagEncode(py - y));
      x = px;
      y = py;
    }
    final f = <int>[];
    field(f, 2, tags);
    varint(f, (3 << 3) | 0);
    varint(f, 2); // LINESTRING
    field(f, 4, geom);
    field(layer, 2, f);
  }
  field(layer, 3, 'k'.codeUnits);
  field(layer, 3, 'u'.codeUnits);
  for (final n in numbers) {
    final v = <int>[];
    varint(v, (5 << 3) | 0);
    varint(v, n);
    field(layer, 4, v);
  }
  varint(layer, (5 << 3) | 0);
  varint(layer, kTileExtent);
  final tile = <int>[];
  field(tile, 3, layer);
  return Uint8List.fromList(tile);
}

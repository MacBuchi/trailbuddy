// Schreibt ein PMTiles-v3-Archiv aus Kacheln — der Speicher eines
// gespeicherten Bereichs (Konzept 3.2).
//
// **Warum ein eigener Schreiber, obwohl die Regel „nie mit einem eigenen
// Schreiber schneiden" gilt** (Konzept 3.1): Die Regel gilt für das
// Archiv des Hosts, das jeder Client liest — dort scheitert ein leicht
// kaputtes Archiv im Browser statt in CI. Ein Bereich entsteht dagegen
// auf dem Gerät, aus Kacheln, die die App gerade selbst per Range aus
// dem Host-Archiv geholt hat; dafür gibt es kein `pmtiles extract`. Die
// Kachelbytes bleiben, wie sie sind (dieselbe Kompression wie beim
// Host), nur Verzeichnis und Header entstehen hier. Nach jedem Schreiben
// liest der Aufrufer das Archiv mit dem Paket zurück — die Gegenprobe,
// die der Test auch fährt.
//
// Warum ein Archiv und kein Kachelspeicher je z/x/y: MapLibre liest
// `pmtiles://file://…` nativ, ohne eigenen Kachel-Lieferanten, und der
// Canvas-Renderer liest dasselbe Archiv über `PmTilesVectorTileProvider`.
// Ein Format für beide Engines, kein zweiter Weg.
//
// Das Format ist die Portierung von `tool/map_tiles.py` (`_build_archive`,
// `serialize_directory`): Verzeichnisse als vier Varint-Spalten (Delta
// der Kachel-Ids, Lauflängen, Längen, Versätze mit 0 für „direkt
// dahinter"), Blatt-Verzeichnisse, sobald die Wurzel 16 KiB übersteigt,
// interne Kompression „none" (Verzeichnisse sind klein, und der
// Leser braucht dann keinen Dekoder).
import 'dart:convert';
import 'dart:typed_data';

import 'package:pmtiles/pmtiles.dart' show Compression, ZXY;

/// Der Header ist 127 Byte lang, Wurzelverzeichnis ab Byte 127.
const kPmTilesHeaderLength = 127;

/// Ein Wurzelverzeichnis über dieser Größe bekommt Blätter; der Leser
/// holt die Wurzel mit dem Header in EINER Anfrage, und so bleibt sie
/// klein (Vorgabe der Spezifikation).
const kPmTilesMaxRootBytes = 16384;

/// Eine Kachel für den Schreiber: Lage plus die BYTES, wie sie im
/// Quellarchiv liegen (also bereits mit dessen Kompression).
class TileToWrite {
  const TileToWrite(this.z, this.x, this.y, this.bytes);

  final int z;
  final int x;
  final int y;
  final Uint8List bytes;
}

/// Der Rahmen, den der Header nennt (Grad).
class TileBounds {
  const TileBounds({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });

  final double west;
  final double south;
  final double east;
  final double north;
}

class _Entry {
  _Entry(this.tileId, this.runLength, this.offset, this.length);
  final int tileId;
  int runLength;
  final int offset;
  final int length;
}

void _writeVarint(BytesBuilder out, int value) {
  assert(value >= 0, 'Varints sind vorzeichenlos');
  var v = value;
  while (true) {
    final byte = v & 0x7F;
    v >>= 7;
    if (v != 0) {
      out.addByte(byte | 0x80);
    } else {
      out.addByte(byte);
      return;
    }
  }
}

Uint8List _serializeDirectory(List<_Entry> entries) {
  final out = BytesBuilder(copy: false);
  _writeVarint(out, entries.length);
  var lastId = 0;
  for (final e in entries) {
    _writeVarint(out, e.tileId - lastId);
    lastId = e.tileId;
  }
  for (final e in entries) {
    _writeVarint(out, e.runLength);
  }
  for (final e in entries) {
    _writeVarint(out, e.length);
  }
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (i > 0 && e.offset == entries[i - 1].offset + entries[i - 1].length) {
      _writeVarint(out, 0);
    } else {
      _writeVarint(out, e.offset + 1);
    }
  }
  return out.toBytes();
}

/// Baut das Archiv. [tiles] in beliebiger Reihenfolge; gleiche Bytes
/// werden nur einmal abgelegt (Meer, leere Kacheln), gleiche Nachbarn
/// zu Läufen zusammengefasst. [leafSize] erzwingt Blätter dieser Größe —
/// für Tests, denn eine synthetische Wurzel wird nie 16 KiB groß.
///
/// Wirft bei einer leeren Kachelliste: Ein Archiv ohne Kachel ist kein
/// Bereich, und der Header hätte keinen Zoombereich.
Uint8List writePmTiles({
  required Iterable<TileToWrite> tiles,
  required Compression tileCompression,
  required TileBounds bounds,
  int? leafSize,
  Map<String, dynamic>? metadata,
}) {
  final byId = [
    for (final t in tiles) (id: ZXY(t.z, t.x, t.y).toTileId(), tile: t),
  ]..sort((a, b) => a.id.compareTo(b.id));
  if (byId.isEmpty) throw ArgumentError('Ein Archiv ohne Kacheln');

  // Kacheldaten mit Dedup über den Inhalt. Der Schlüssel ist ein
  // Hash über die Bytes plus die Länge — ein Zusammenstoß hieße, zwei
  // verschiedene Kacheln mit gleicher Länge und gleichem 64-Bit-FNV;
  // die Prüfung `bytesEqual` darunter macht ihn harmlos.
  final data = BytesBuilder(copy: false);
  final offsets = <int, List<({int offset, Uint8List bytes})>>{};
  final entries = <_Entry>[];
  var contents = 0;
  var dataLength = 0;
  for (final item in byId) {
    final bytes = item.tile.bytes;
    final key = _fnv(bytes);
    var offset = -1;
    final same = offsets[key];
    if (same != null) {
      for (final candidate in same) {
        if (_bytesEqual(candidate.bytes, bytes)) {
          offset = candidate.offset;
          break;
        }
      }
    }
    if (offset < 0) {
      offset = dataLength;
      data.add(bytes);
      dataLength += bytes.length;
      contents++;
      (offsets[key] ??= []).add((offset: offset, bytes: bytes));
    }
    final last = entries.isEmpty ? null : entries.last;
    if (last != null &&
        last.offset == offset &&
        last.length == bytes.length &&
        last.tileId + last.runLength == item.id) {
      last.runLength++;
      continue;
    }
    entries.add(_Entry(item.id, 1, offset, bytes.length));
  }

  var root = _serializeDirectory(entries);
  var leaves = Uint8List(0);
  var entryCount = entries.length;
  if (leafSize != null || root.length > kPmTilesMaxRootBytes) {
    var size = leafSize ?? 2;
    while (true) {
      final leafBuilder = BytesBuilder(copy: false);
      final rootEntries = <_Entry>[];
      var leafLength = 0;
      for (var start = 0; start < entries.length; start += size) {
        final chunk = entries.sublist(
          start,
          start + size > entries.length ? entries.length : start + size,
        );
        final serialized = _serializeDirectory(chunk);
        rootEntries.add(
          _Entry(chunk.first.tileId, 0, leafLength, serialized.length),
        );
        leafBuilder.add(serialized);
        leafLength += serialized.length;
      }
      root = _serializeDirectory(rootEntries);
      if (leafSize != null || root.length <= kPmTilesMaxRootBytes) {
        leaves = leafBuilder.toBytes();
        entryCount = entries.length + rootEntries.length;
        break;
      }
      size *= 2;
      if (size > entries.length * 2) {
        throw StateError('Kein Wurzelverzeichnis unter 16 KiB möglich');
      }
    }
  }

  final metadataBytes = Uint8List.fromList(
    utf8.encode(jsonEncode(metadata ?? const {'vector_layers': <Object>[]})),
  );

  final rootOffset = kPmTilesHeaderLength;
  final metadataOffset = rootOffset + root.length;
  final leafOffset = metadataOffset + metadataBytes.length;
  final tileOffset = leafOffset + leaves.length;

  var minZoom = 255;
  var maxZoom = 0;
  for (final item in byId) {
    if (item.tile.z < minZoom) minZoom = item.tile.z;
    if (item.tile.z > maxZoom) maxZoom = item.tile.z;
  }
  var addressed = 0;
  for (final e in entries) {
    addressed += e.runLength;
  }

  final header = ByteData(kPmTilesHeaderLength);
  final magic = ascii.encode('PMTiles');
  for (var i = 0; i < magic.length; i++) {
    header.setUint8(i, magic[i]);
  }
  header.setUint8(7, 3);
  // Zwei 32-Bit-Hälften statt `setUint64`: Das gibt es im Browser nicht
  // (dart2js kennt keine 64-Bit-Ganzzahlen), und der Schreiber läuft dort
  // für Bereiche in IndexedDB.
  void u64(int at, int value) {
    header.setUint32(at, value & 0xFFFFFFFF, Endian.little);
    header.setUint32(at + 4, value ~/ 0x100000000, Endian.little);
  }

  u64(0x08, rootOffset);
  u64(0x10, root.length);
  u64(0x18, metadataOffset);
  u64(0x20, metadataBytes.length);
  u64(0x28, leafOffset);
  u64(0x30, leaves.length);
  u64(0x38, tileOffset);
  u64(0x40, dataLength);
  u64(0x48, addressed);
  u64(0x50, entryCount);
  u64(0x58, contents);
  header.setUint8(0x60, 1); // clustered
  header.setUint8(0x61, Compression.none.index); // internal compression
  header.setUint8(0x62, tileCompression.index);
  header.setUint8(0x63, 1); // mvt
  header.setUint8(0x64, minZoom);
  header.setUint8(0x65, maxZoom);
  int e7(double degrees) => (degrees * 1e7).round();
  header.setInt32(0x66, e7(bounds.west), Endian.little);
  header.setInt32(0x6A, e7(bounds.south), Endian.little);
  header.setInt32(0x6E, e7(bounds.east), Endian.little);
  header.setInt32(0x72, e7(bounds.north), Endian.little);
  header.setUint8(0x76, minZoom);
  header.setInt32(0x77, e7((bounds.west + bounds.east) / 2), Endian.little);
  header.setInt32(0x7B, e7((bounds.south + bounds.north) / 2), Endian.little);

  final out = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(root)
    ..add(metadataBytes)
    ..add(leaves)
    ..add(data.toBytes());
  return out.toBytes();
}

/// FNV-1a über die Bytes, 32 Bit in Rechenschritten, die auch dart2js
/// exakt kann (keine 64-Bit-Multiplikation); der Gleichheitsvergleich
/// darunter fängt Zusammenstöße.
int _fnv(Uint8List bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h ^= b;
    h =
        ((h & 0xFFFF) * 16777619 + ((((h >> 16) * 16777619) & 0xFFFF) << 16)) &
        0xFFFFFFFF;
  }
  return h ^ bytes.length;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

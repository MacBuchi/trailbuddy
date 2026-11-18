/// Liest aus Androids Tombstone die Stelle heraus, an der es geknallt hat
/// (#394).
///
/// **Warum in Dart und nicht in Kotlin.** Ab API 31 legt Android zu jedem
/// nativen Absturz ein Tombstone bereit — als Protobuf, nicht als Text
/// wie beim ANR-Dump. Irgendwer muss es also lesen. Die native Seite ist
/// die einzige Datei im Projekt ohne Test-Netz (`MainActivity.kt`);
/// hierher gebracht ist das Parsen mit erfundenen Tombstones prüfbar, und
/// drüben bleiben fünf Zeilen „Stream in ein Byte-Array".
///
/// **Es wirft nie.** Der Weg hierher ist die Fehlermeldung selbst — ein
/// Leser, der bei einem unerwarteten Byte stolpert, nähme dem Bericht
/// auch noch den Rest. Bei allem, was nicht passt, kommt `null` zurück,
/// und der Bericht steht dann eben ohne Spur da wie bisher.
///
/// Feldnummern aus AOSPs `debuggerd/proto/tombstone.proto`. Sie sind
/// Teil eines veröffentlichten Formats („NOTE TO OEMS: do not use numbers
/// in the reserved range") und ändern sich nicht rückwirkend; genau
/// deshalb ist es vertretbar, sie hier als Zahlen zu führen, statt die
/// Datei zu kopieren und mit AOSP Schritt halten zu müssen.
library;

import 'dart:typed_data';

const _tombstoneTid = 6;
const _tombstoneSignalInfo = 10;
const _tombstoneAbortMessage = 14;
const _tombstoneCauses = 15;
const _tombstoneThreads = 16;

const _signalNumber = 1;
const _signalName = 2;
const _signalCodeName = 4;
const _signalHasFaultAddress = 8;
const _signalFaultAddress = 9;

const _threadName = 2;
const _threadBacktrace = 4;

const _frameRelPc = 1;
const _frameFunctionName = 4;
const _frameFunctionOffset = 5;
const _frameFileName = 6;

const _causeHumanReadable = 1;

/// In `map<uint32, Thread>` heißt jeder Eintrag Schlüssel 1, Wert 2.
const _mapKey = 1;
const _mapValue = 2;

/// Der Absturz als Text — Signal, Grund und die Frames des abgestürzten
/// Threads. `null`, wenn sich daraus nichts machen lässt.
///
/// Nur der ABGESTÜRZTE Thread, wie beim ANR-Dump nur der Haupt-Thread:
/// Ein Tombstone führt alle Threads samt Registern und Speicherkarte, und
/// davon passt weder etwas in die 4000 Zeichen der Spalte noch in einen
/// Wochendigest.
String? formatTombstone(Uint8List bytes, {int maxChars = 4000}) {
  try {
    return _format(bytes, maxChars);
  } catch (_) {
    // Siehe oben: lieber keine Spur als ein verschluckter Bericht.
    return null;
  }
}

String? _format(Uint8List bytes, int maxChars) {
  int? tid;
  Uint8List? signal;
  String? abortMessage;
  final causes = <String>[];
  final threads = <int, Uint8List>{};

  final top = _Reader(bytes);
  while (!top.done) {
    final field = top.tag();
    switch (field) {
      case _tombstoneTid:
        tid = top.readVarint();
      case _tombstoneSignalInfo:
        signal = top.readBytes();
      case _tombstoneAbortMessage:
        abortMessage = top.readString();
      case _tombstoneCauses:
        final cause = _cause(top.readBytes());
        if (cause != null) causes.add(cause);
      case _tombstoneThreads:
        final entry = _Reader(top.readBytes());
        int? key;
        Uint8List? value;
        while (!entry.done) {
          switch (entry.tag()) {
            case _mapKey:
              key = entry.readVarint();
            case _mapValue:
              value = entry.readBytes();
            default:
              entry.skip();
          }
        }
        if (key != null && value != null) threads[key] = value;
      default:
        top.skip();
    }
  }

  final lines = <String>[];
  if (signal != null) {
    final line = _signal(signal);
    if (line != null) lines.add(line);
  }
  if (abortMessage != null && abortMessage.isNotEmpty) {
    lines.add('abort message: $abortMessage');
  }
  lines.addAll(causes.map((c) => 'cause: $c'));

  // Ohne tid kein Thread — und ohne Thread keine Frames. Beides kann bei
  // einem abgeschnittenen Tombstone vorkommen; dann bleibt der Kopf
  // stehen, der für sich schon eine Aussage ist.
  final thread = tid == null ? null : threads[tid];
  if (thread != null) lines.addAll(_thread(thread));

  if (lines.isEmpty) return null;
  final text = lines.join('\n');
  return text.length <= maxChars ? text : text.substring(0, maxChars);
}

String? _signal(Uint8List bytes) {
  final r = _Reader(bytes);
  int? number;
  String? name;
  String? codeName;
  var hasFault = false;
  var fault = 0;
  while (!r.done) {
    switch (r.tag()) {
      case _signalNumber:
        number = r.readVarint();
      case _signalName:
        name = r.readString();
      case _signalCodeName:
        codeName = r.readString();
      case _signalHasFaultAddress:
        hasFault = r.readVarint() != 0;
      case _signalFaultAddress:
        fault = r.readVarint();
      default:
        r.skip();
    }
  }
  if (number == null && name == null) return null;
  final parts = <String>[
    'signal ${number ?? '?'}${name == null ? '' : ' ($name)'}',
    if (codeName != null && codeName.isNotEmpty) 'code $codeName',
    // Die Fehleradresse nur, wenn sie GESETZT ist: `0x0` ist eine
    // gültige Adresse (Nullzeiger) und darf nicht wie „unbekannt"
    // aussehen — proto3 kann beides nicht unterscheiden, deshalb trägt
    // das Format ein eigenes Flag.
    if (hasFault) 'fault addr 0x${fault.toRadixString(16)}',
  ];
  return parts.join(', ');
}

String? _cause(Uint8List bytes) {
  final r = _Reader(bytes);
  while (!r.done) {
    if (r.tag() == _causeHumanReadable) return r.readString();
    r.skip();
  }
  return null;
}

List<String> _thread(Uint8List bytes) {
  final r = _Reader(bytes);
  String? name;
  final frames = <Uint8List>[];
  while (!r.done) {
    switch (r.tag()) {
      case _threadName:
        name = r.readString();
      case _threadBacktrace:
        frames.add(r.readBytes());
      default:
        r.skip();
    }
  }
  return [
    if (name != null && name.isNotEmpty) 'thread "$name"',
    for (final (index, frame) in frames.indexed) _frame(index, frame),
  ];
}

/// Eine Zeile in der Schreibweise, die ein Tombstone selbst benutzt —
/// `#00 pc 00000000000abc12  /apex/…/libc.so (memcpy+16)`. Vertraut für
/// jeden, der schon einmal einen gelesen hat, und nah genug an den
/// ANR-Zeilen, die `tool/symbolize_anr.py` verarbeitet.
String _frame(int index, Uint8List bytes) {
  final r = _Reader(bytes);
  var relPc = 0;
  String? function;
  var offset = 0;
  String? file;
  while (!r.done) {
    switch (r.tag()) {
      case _frameRelPc:
        relPc = r.readVarint();
      case _frameFunctionName:
        function = r.readString();
      case _frameFunctionOffset:
        offset = r.readVarint();
      case _frameFileName:
        file = r.readString();
      default:
        r.skip();
    }
  }
  final number = index.toString().padLeft(2, '0');
  final pc = relPc.toRadixString(16).padLeft(16, '0');
  final where = file == null || file.isEmpty ? '<unknown>' : file;
  final what = function == null || function.isEmpty
      ? ''
      : ' ($function+$offset)';
  return '  #$number pc $pc  $where$what';
}

/// Ein Protobuf-Leser für genau das, was hier gebraucht wird.
///
/// Kein Paket dafür: Die vollständige Laufzeit brächte Codegen und eine
/// kopierte `.proto`-Datei mit, die mit AOSP Schritt halten müsste. Was
/// hier fehlt (gepackte Wiederholungen, Gruppen, Vorzeichen-Zickzack),
/// kommt in diesem Format an den gelesenen Feldern nicht vor.
class _Reader {
  _Reader(this.bytes) : _end = bytes.length;

  final Uint8List bytes;
  final int _end;
  int _pos = 0;
  int _wire = 0;

  bool get done => _pos >= _end;

  /// Liest den nächsten Schlüssel und merkt sich den Drahttyp.
  int tag() {
    final tag = readVarint();
    _wire = tag & 7;
    return tag >> 3;
  }

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_pos >= _end) throw const FormatException('varint über das Ende');
      final byte = bytes[_pos++];
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) throw const FormatException('varint zu lang');
    }
  }

  Uint8List readBytes() {
    final length = readVarint();
    if (_pos + length > _end) {
      throw const FormatException('Länge über das Ende');
    }
    final view = Uint8List.sublistView(bytes, _pos, _pos + length);
    _pos += length;
    return view;
  }

  String readString() => String.fromCharCodes(readBytes());

  /// Überspringt ein Feld, dessen Nummer hier nicht interessiert.
  void skip() {
    switch (_wire) {
      case 0:
        readVarint();
      case 1:
        _pos += 8;
      case 2:
        readBytes();
      case 5:
        _pos += 4;
      default:
        throw FormatException('unbekannter Drahttyp $_wire');
    }
    if (_pos > _end) throw const FormatException('Sprung über das Ende');
  }
}

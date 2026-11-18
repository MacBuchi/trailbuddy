// Androids Tombstone lesen (#394).
//
// Die Eingabe wird hier ERZEUGT statt aufgezeichnet: Ein echtes Tombstone
// ist hunderte Kilobyte mit Registern, Speicherkarte und allen Threads —
// als Testdatei wäre es unlesbar und nicht veränderbar. Gebaut mit einem
// winzigen Encoder darunter, dessen Feldnummern aus AOSPs
// `tombstone.proto` stammen; stimmt eine davon nicht, findet der Leser
// nichts, und genau das würde auffallen.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/data/tombstone.dart';

void main() {
  group('formatTombstone', () {
    test('Signal, Grund und die Frames des abgestürzten Threads', () {
      final bytes = _tombstone(
        tid: 4242,
        signal: _signal(
          number: 11,
          name: 'SIGSEGV',
          codeName: 'SEGV_MAPERR',
          faultAddress: 0,
        ),
        abortMessage: null,
        threads: {
          // Ein anderer Thread ZUERST — und das ist der Punkt: Stünde
          // der abgestürzte vorn, wäre „den ersten nehmen" von „den
          // richtigen nehmen" nicht zu unterscheiden. In der
          // Gegenprobe genau so aufgefallen.
          99: _thread(
            name: 'Binder:1',
            frames: [_frame(relPc: 0xdead, file: '/system/lib64/libbinder.so')],
          ),
          4242: _thread(
            name: 'trailbuddy',
            frames: [
              _frame(
                relPc: 0xabc12,
                file:
                    '/apex/com.android.runtime/lib64/'
                    'bionic/libc.so',
                function: 'memcpy',
                offset: 16,
              ),
              _frame(relPc: 0x1234, file: '/data/app/libapp.so'),
            ],
          ),
        },
      );

      final text = formatTombstone(bytes)!;
      expect(text, contains('signal 11 (SIGSEGV)'));
      expect(text, contains('code SEGV_MAPERR'));
      expect(text, contains('thread "trailbuddy"'));
      expect(
        text,
        contains(
          '#00 pc 00000000000abc12  '
          '/apex/com.android.runtime/lib64/bionic/libc.so (memcpy+16)',
        ),
      );
      expect(text, contains('#01 pc 0000000000001234  /data/app/libapp.so'));
      expect(
        text,
        isNot(contains('libbinder')),
        reason:
            'nur der abgestürzte Thread — alle passen nicht in 4000 '
            'Zeichen und erst recht nicht in den Wochendigest',
      );
    });

    test('eine Nullzeiger-Adresse ist eine Aussage, keine Lücke', () {
      // proto3 kann „0" und „nicht gesetzt" nicht unterscheiden, deshalb
      // trägt das Format `has_fault_address`. Ohne die Auswertung sähe
      // ein Nullzeiger-Absturz — der häufigste überhaupt — so aus, als
      // wüsste man die Adresse nicht.
      final withFault = formatTombstone(
        _tombstone(
          tid: 1,
          signal: _signal(number: 11, name: 'SIGSEGV', faultAddress: 0),
          threads: {1: _thread(frames: [])},
        ),
      )!;
      expect(withFault, contains('fault addr 0x0'));

      final withoutFault = formatTombstone(
        _tombstone(
          tid: 1,
          signal: _signal(number: 6, name: 'SIGABRT'),
          threads: {1: _thread(frames: [])},
        ),
      )!;
      expect(withoutFault, isNot(contains('fault addr')));
    });

    test('abort message und cause kommen mit', () {
      final text = formatTombstone(
        _tombstone(
          tid: 1,
          signal: _signal(number: 6, name: 'SIGABRT'),
          abortMessage: 'Check failed: ptr != nullptr',
          causes: const ['null pointer dereference'],
          threads: {1: _thread(frames: [])},
        ),
      )!;
      expect(text, contains('abort message: Check failed: ptr != nullptr'));
      expect(text, contains('cause: null pointer dereference'));
    });

    test('unbekannte Felder werden übersprungen, nicht verschluckt', () {
      // Ein Tombstone von einem neueren Android — oder von einem OEM, der
      // eigene Felder anhängt — darf den Leser nicht aus dem Tritt
      // bringen. Alle vier Drahttypen kommen vor.
      final builder = BytesBuilder()
        ..add(_varintField(1, 1)) // arch (varint)
        ..add(_bytesField(2, ascii.encode('irgendein/fingerprint')))
        ..add(_fixed64Field(900, 0xdeadbeef))
        ..add(_fixed32Field(901, 0x1234))
        ..add(_varintField(6, 7))
        ..add(_bytesField(10, _signal(number: 9, name: 'SIGKILL')))
        ..add(_bytesField(16, _mapEntry(7, _thread(name: 'main', frames: []))));
      final text = formatTombstone(Uint8List.fromList(builder.takeBytes()))!;
      expect(text, contains('signal 9 (SIGKILL)'));
      expect(text, contains('thread "main"'));
    });

    test('kaputte Eingaben ergeben null statt einer Ausnahme', () {
      // Dieser Weg IST die Fehlermeldung. Ein Leser, der wirft, nimmt dem
      // Bericht auch noch den Rest — `ExitReporter` würde die Meldung
      // dieses Absturzes verlieren.
      for (final broken in [
        Uint8List.fromList([0xff, 0xff, 0xff]), // varint ohne Ende
        Uint8List.fromList([0x0a, 0x7f]), // Länge über das Ende
        Uint8List.fromList([0x0f]), // Drahttyp 7 gibt es nicht
        Uint8List(0),
      ]) {
        expect(formatTombstone(broken), isNull, reason: '$broken');
      }
    });

    test('länger als die Spalte wird gekürzt', () {
      // `error_reports.stack` fasst 4000 Zeichen. Ein Tombstone mit 300
      // Frames ist normal.
      final text = formatTombstone(
        _tombstone(
          tid: 1,
          signal: _signal(number: 11, name: 'SIGSEGV'),
          threads: {
            1: _thread(
              frames: [
                for (var i = 0; i < 300; i++)
                  _frame(
                    relPc: i,
                    file: '/system/lib64/libsomethinglong.so',
                    function: 'a_rather_long_function_name',
                    offset: i,
                  ),
              ],
            ),
          },
        ),
        maxChars: 4000,
      )!;
      expect(text.length, lessThanOrEqualTo(4000));
      expect(text, startsWith('signal 11'));
    });
  });
}

// --- ein winziger Protobuf-Encoder, nur für die Testdaten ---

List<int> _varint(int value) {
  final out = <int>[];
  var v = value;
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

List<int> _varintField(int field, int value) => [
  ..._varint(field << 3),
  ..._varint(value),
];

List<int> _bytesField(int field, List<int> value) => [
  ..._varint((field << 3) | 2),
  ..._varint(value.length),
  ...value,
];

List<int> _fixed64Field(int field, int value) => [
  ..._varint((field << 3) | 1),
  ...List.filled(8, 0)..[0] = value & 0xff,
];

List<int> _fixed32Field(int field, int value) => [
  ..._varint((field << 3) | 5),
  ...List.filled(4, 0)..[0] = value & 0xff,
];

Uint8List _signal({
  required int number,
  required String name,
  String? codeName,
  int? faultAddress,
}) {
  final b = BytesBuilder()
    ..add(_varintField(1, number))
    ..add(_bytesField(2, ascii.encode(name)));
  if (codeName != null) b.add(_bytesField(4, ascii.encode(codeName)));
  if (faultAddress != null) {
    b
      ..add(_varintField(8, 1)) // has_fault_address
      ..add(_varintField(9, faultAddress));
  }
  return Uint8List.fromList(b.takeBytes());
}

Uint8List _frame({
  required int relPc,
  required String file,
  String? function,
  int offset = 0,
}) {
  final b = BytesBuilder()
    ..add(_varintField(1, relPc))
    ..add(_bytesField(6, ascii.encode(file)));
  if (function != null) {
    b
      ..add(_bytesField(4, ascii.encode(function)))
      ..add(_varintField(5, offset));
  }
  return Uint8List.fromList(b.takeBytes());
}

Uint8List _thread({String? name, required List<Uint8List> frames}) {
  final b = BytesBuilder();
  if (name != null) b.add(_bytesField(2, ascii.encode(name)));
  for (final frame in frames) {
    b.add(_bytesField(4, frame));
  }
  return Uint8List.fromList(b.takeBytes());
}

List<int> _mapEntry(int key, Uint8List value) => [
  ..._varintField(1, key),
  ..._bytesField(2, value),
];

Uint8List _tombstone({
  required int tid,
  required Uint8List signal,
  required Map<int, Uint8List> threads,
  String? abortMessage,
  List<String> causes = const [],
}) {
  final b = BytesBuilder()
    ..add(_varintField(6, tid))
    ..add(_bytesField(10, signal));
  if (abortMessage != null) {
    b.add(_bytesField(14, ascii.encode(abortMessage)));
  }
  for (final cause in causes) {
    b.add(_bytesField(15, _bytesField(1, ascii.encode(cause))));
  }
  threads.forEach((key, value) {
    b.add(_bytesField(16, _mapEntry(key, value)));
  });
  return Uint8List.fromList(b.takeBytes());
}

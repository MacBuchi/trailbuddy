/// Untergrenzen für Pakete, deren ältere Fassungen die App einfrieren
/// können (#586). Ein Rückfall wäre still: Alles kompiliert, jede Suite
/// bleibt grün, und der Fehler zeigt sich erst als ANR auf einem Gerät,
/// dessen Standortdienst hängt.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Paket → kleinste erlaubte Fassung, mit dem Grund.
const _floors = {
  // Bis 5.2.0 meldet jeder Strom und jeder Fix NMEA-Listener und
  // GNSS-Callback synchron auf dem Main-Thread an und ab (ANR im
  // Emulator, Verklemmung in system_server). 5.2.1 nur mit
  // `useMSLAltitude`, das die App nicht nutzt.
  'geolocator_android': [5, 2, 1],
};

List<int> _parse(String v) =>
    v.split('+').first.split('.').map(int.parse).toList();

bool _atLeast(List<int> v, List<int> floor) {
  for (var i = 0; i < floor.length; i++) {
    if (v[i] != floor[i]) return v[i] > floor[i];
  }
  return true;
}

void main() {
  final lock = File('pubspec.lock').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();

  for (final MapEntry(key: name, value: floor) in _floors.entries) {
    test('$name ist direkt festgeschrieben, mindestens ${floor.join('.')}', () {
      // Direkt, damit die Auflösung nicht über ein anderes Paket unter
      // die Grenze rutscht.
      final constraint = RegExp(
        '^  $name: \\^(\\S+)\$',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(constraint, isNotNull, reason: '$name fehlt in pubspec.yaml');
      expect(
        _atLeast(_parse(constraint!.group(1)!), floor),
        isTrue,
        reason: 'Untergrenze in pubspec.yaml zu niedrig',
      );

      final locked = RegExp(
        '^  $name:\\n(?:    .*\\n)*?    version: "([^"]+)"',
        multiLine: true,
      ).firstMatch(lock);
      expect(locked, isNotNull, reason: '$name fehlt in pubspec.lock');
      expect(
        _atLeast(_parse(locked!.group(1)!), floor),
        isTrue,
        reason: 'pubspec.lock hat ${locked.group(1)}',
      );
    });
  }
}

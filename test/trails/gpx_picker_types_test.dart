// Die Typgruppen der GPX-Auswahl gegen die ECHTEN Plattformteile von
// `file_selector` (#644): Auf iOS warf der Import einen ArgumentError,
// weil die Gruppe nur `mimeTypes` trug. Die Plattform-Kanäle sind durch
// Fakes der erzeugten Host-APIs ersetzt; was die Pakete aus den Gruppen
// machen, rechnen sie selbst.
// ignore_for_file: implementation_imports
import 'package:file_selector_android/file_selector_android.dart';
import 'package:file_selector_android/src/file_selector_api.g.dart' as android;
import 'package:file_selector_ios/file_selector_ios.dart';
import 'package:file_selector_ios/src/messages.g.dart' as ios;
import 'package:flutter_test/flutter_test.dart';
import 'package:trailbuddy/features/trails/trail_import_screen.dart';

class _IosApi extends ios.FileSelectorApi {
  ios.FileSelectorConfig? seen;

  @override
  Future<List<String>> openFile(ios.FileSelectorConfig config) async {
    seen = config;
    return [];
  }
}

class _AndroidApi extends android.FileSelectorApi {
  android.FileTypes? seen;

  @override
  Future<List<android.FileResponse>> openFiles(
    String? initialDirectory,
    android.FileTypes allowedTypes,
  ) async {
    seen = allowedTypes;
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final groups = gpxPickerTypeGroups('Alle Dateien', 'GPX oder Zip');

  test('iOS: die Auswahl öffnet und erlaubt jede Datei', () async {
    final api = _IosApi();
    await FileSelectorIOS(api: api).openFiles(acceptedTypeGroups: groups);
    expect(api.seen!.utis, ['public.data']);
    expect(api.seen!.allowMultiSelection, isTrue);
  });

  test('Android: weiter ohne Filter (*/*), wie im Feld bewährt', () async {
    final api = _AndroidApi();
    await FileSelectorAndroid(api: api).openFiles(acceptedTypeGroups: groups);
    expect(api.seen!.mimeTypes, ['*/*']);
    expect(api.seen!.extensions, isEmpty);
  });
}

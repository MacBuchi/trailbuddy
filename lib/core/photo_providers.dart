// Ein Bild vom Nutzer holen und entkernen — für das Foto am Hinweis
// (#37). Aus PilzBuddy übernommen (`lib/core/photo_providers.dart`).
//
// Wer ein Bild annimmt, nimmt es über [photoPickerProvider] an und
// schickt es durch [photoPreparerProvider], bevor es irgendwohin geht.
// Es gibt keinen zweiten Weg an `preparePhoto` vorbei — das Repository
// nimmt nur ein [PreparedPhoto].
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'photo_pipeline.dart';

/// Woher das Bild kommt.
enum PhotoSource { camera, gallery }

/// Holt ein Bild vom Nutzer — `null`, wenn er abbricht.
typedef PhotoPicker = Future<Uint8List?> Function(PhotoSource source);

/// Der echte Weg: `image_picker`. **Mit `maxWidth`, und zwar aus zwei
/// Gründen, von denen keiner „Metadaten" heißt**: Das Plugin kodiert
/// dabei nach JPEG um (ein HEIC vom Telefon käme sonst bei
/// `package:image` an, das es nicht lesen kann), und 2048 statt 4000
/// Pixel Kante viertelt die Arbeit des Dart-Dekodierers. Die Metadaten
/// kopiert das Plugin dabei ZURÜCK — deshalb läuft danach
/// `preparePhoto`, und nur deshalb darf dieser Schritt hier stehen.
final photoPickerProvider = Provider<PhotoPicker>((ref) => (source) async {
      final file = await ImagePicker().pickImage(
        source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      return file?.readAsBytes();
    });

/// Verkleinern und entkernen — im Isolate, damit die Oberfläche nicht
/// steht (im Browser läuft `compute` auf demselben Faden, das Bild ist
/// dort durch `maxWidth` schon klein). Im Test überschrieben mit dem
/// direkten Aufruf: `compute` braucht ein echtes Isolate, und das gibt
/// es unter FakeAsync nicht.
typedef PhotoPreparer = Future<PreparedPhoto> Function(Uint8List bytes);

final photoPreparerProvider =
    Provider<PhotoPreparer>((ref) => (bytes) => compute(preparePhoto, bytes));

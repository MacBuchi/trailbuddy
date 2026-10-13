// Eine GPX-Datei aus der App herausgeben (#150): über das Teilen-Blatt
// des Systems (`share_plus`), im Browser als Download. Die Naht ist ein
// Provider, damit Tests das Blatt abfangen — `SharePlus.instance` lässt
// sich im Widget-Test nicht mocken (dasselbe Muster wie
// `gpxPickerProvider` beim Import).
//
// Zwei Dinge, die man wissen muss:
// - **`XFile.fromData` reicht**: `share_plus` legt die Datei selbst im
//   Cache-Verzeichnis ab, das Auto-Backup nicht sichert; der Name kommt
//   über `fileNameOverrides`, `XFile.name` gilt nur im Web.
// - **Im Browser ist `unavailable` ein Erfolg**: Kann der Browser keine
//   Dateien teilen, lädt `share_plus` sie herunter und meldet genau
//   diesen Status. Das Einladungs-Muster („unavailable ⇒ Fehler") darf
//   hier nicht kopiert werden.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import 'errors.dart';

/// Was beim Herausgeben herausgekommen ist.
enum GpxShareOutcome {
  /// Der Nutzer hat ein Ziel gewählt — nichts zu melden.
  shared,

  /// Das Teilen-Blatt wurde weggewischt.
  dismissed,

  /// Browser ohne Datei-Teilen: Die Datei ist als Download unterwegs.
  downloaded,
}

typedef GpxShare = Future<GpxShareOutcome> Function({required String fileName, required String xml});

/// Die Teilen-Funktion; der Harness überschreibt sie mit einem Recorder.
final gpxShareProvider = Provider<GpxShare>((ref) => _shareViaSystem);

Future<GpxShareOutcome> _shareViaSystem({required String fileName, required String xml}) async {
  final result = await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(utf8.encode(xml), mimeType: 'application/gpx+xml', name: fileName)],
    fileNameOverrides: [fileName],
    subject: fileName,
  ));
  return switch (result.status) {
    ShareResultStatus.success => GpxShareOutcome.shared,
    ShareResultStatus.dismissed => GpxShareOutcome.dismissed,
    ShareResultStatus.unavailable => GpxShareOutcome.downloaded,
  };
}

/// Gibt [xml] als [fileName] heraus und sagt, was der Nutzer sonst nicht
/// sähe: den Download im Browser und einen Fehler. Ein gewähltes Ziel
/// steht im Vordergrund, ein weggewischtes Blatt braucht keine Meldung.
Future<void> shareGpx(BuildContext context, WidgetRef ref,
    {required String fileName, required String xml}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  try {
    final outcome = await ref.read(gpxShareProvider)(fileName: fileName, xml: xml);
    if (outcome != GpxShareOutcome.downloaded) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l.gpxDownloading(fileName))));
  } catch (e, stackTrace) {
    logError('GPX-Export', e, stackTrace);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l.gpxExportFailed(friendlyError(l, e)))));
  }
}

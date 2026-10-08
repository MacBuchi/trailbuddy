import 'package:flutter/foundation.dart' show VoidCallback;

import 'picture_in_picture.dart';

PictureInPicture createPictureInPicture() => const _NoPictureInPicture();

/// Im Browser gibt es kein Fenster (9.6): Die Folgeansicht läuft, solange
/// der Tab vorne ist.
class _NoPictureInPicture implements PictureInPicture {
  const _NoPictureInPicture();

  @override
  Future<void> allow(bool on) async {}

  @override
  void listen({required void Function(bool inPip) onMode, required VoidCallback onStop}) {}
}

import 'dart:io' show Platform;

/// Die Plattform des Prozesses (nicht die gespielte, siehe
/// `platform_support.dart`).
bool get processIsAndroid => Platform.isAndroid;
bool get processIsIos => Platform.isIOS;

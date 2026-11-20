import 'seen_host_files.dart';

/// Im Browser gibt es keinen Ordner — dort wählt `chooseSeenHostFiles`
/// IndexedDB, und ohne sie gibt es keine Ablage.
SeenHostFiles? createDeviceSeenHostFiles() => null;

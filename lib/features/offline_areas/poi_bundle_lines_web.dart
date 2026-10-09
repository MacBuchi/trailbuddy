import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipDecoder;

/// Im Browser gibt es „Ganze Region" nicht (Konzept 8.1); der Rückfall
/// entpackt am Stück, damit der Code dort übersetzt.
Stream<String> gunzipLines(Uint8List bytes) =>
    Stream.fromIterable(const LineSplitter().convert(utf8.decode(GZipDecoder().decodeBytes(bytes))));

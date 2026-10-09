import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

/// Die Zeilen des entpackten Bündels, im Strom — nie das Ganze auf einmal.
Stream<String> gunzipLines(Uint8List bytes) => Stream<List<int>>.value(bytes)
    .transform(gzip.decoder)
    .transform(utf8.decoder)
    .transform(const LineSplitter());

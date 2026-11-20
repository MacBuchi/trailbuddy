// Ein StyleController, der mitschreibt und die Reihenfolge der Ebenen
// führt wie MapLibre — die Platform-View ist im Test nicht renderbar.
import 'package:maplibre/maplibre.dart' as ml;

/// Schreibt jeden Aufruf mit und führt die Reihenfolge der Ebenen wie
/// MapLibre: `belowLayerId` setzt darunter, sonst zuoberst.
class RecordingStyle implements ml.StyleController {
  final calls = <String>[];
  final order = <String>[];
  final sources = <String, String>{};
  String? failOn;

  void _maybeFail(String what) {
    if (failOn != null && what.contains(failOn!)) {
      failOn = null;
      throw StateError('Engine: $what');
    }
  }

  @override
  Future<void> addSource(ml.Source source) async {
    _maybeFail('addSource ${source.id}');
    if (sources.containsKey(source.id)) {
      throw StateError('Quelle ${source.id} gibt es schon');
    }
    sources[source.id] = (source as ml.GeoJsonSource).data;
    calls.add('addSource ${source.id}');
  }

  @override
  Future<void> addLayer(
    ml.StyleLayer layer, {
    String? belowLayerId,
    String? aboveLayerId,
    int? atIndex,
  }) async {
    _maybeFail('addLayer ${layer.id}');
    if (order.contains(layer.id)) {
      throw StateError('Ebene ${layer.id} gibt es schon');
    }
    if (belowLayerId == null) {
      order.add(layer.id);
    } else {
      order.insert(order.indexOf(belowLayerId), layer.id);
    }
    calls.add(
      'addLayer ${layer.id}${belowLayerId == null ? '' : ' unter $belowLayerId'}',
    );
  }

  @override
  Future<void> updateGeoJsonSource({
    required String id,
    required String data,
  }) async {
    sources[id] = data;
    calls.add('update $id');
  }

  @override
  Future<void> removeLayer(String id) async {
    order.remove(id);
    calls.add('removeLayer $id');
  }

  @override
  Future<void> removeSource(String id) async {
    sources.remove(id);
    calls.add('removeSource $id');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

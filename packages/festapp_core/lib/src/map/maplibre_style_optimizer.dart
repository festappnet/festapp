import 'package:festapp_core/map.dart';

class MapLibreStyleOptimizer {
  static const _supportedSource = 'versatiles-shortbread';
  static const _requiredLayerIds = {
    'background',
    'building',
    'street-primary',
    'bridge-street-primary',
    'tunnel-street-primary',
    'label-street-primary',
    'label-place-city',
  };

  static Map<String, dynamic> optimize(
    Map<String, dynamic> style, {
    required String sourceName,
  }) {
    if (sourceName != _supportedSource) return style;
    final rawLayers = style['layers'];
    if (rawLayers is! List) {
      throw OfflineMapBundleException('MapLibre style layers are missing.');
    }

    final layers = rawLayers
        .map((layer) => Map<String, dynamic>.from(layer as Map))
        .toList(growable: false);
    final layerIds = layers
        .map((layer) => layer['id'])
        .whereType<String>()
        .toSet();
    // Compact/custom styles using the same source id are already cheaper than
    // the audited VersaTiles snapshot. Leave them intact instead of applying a
    // partial prefix policy to an unknown contract.
    if (!layerIds.containsAll(_requiredLayerIds)) return style;

    return Map<String, dynamic>.from(style)
      ..['layers'] = layers.where(_keepLayer).toList(growable: false);
  }

  static bool _keepLayer(Map<String, dynamic> layer) {
    final id = layer['id'];
    if (id is! String) return false;
    if (id == 'background' ||
        id.startsWith('land-') ||
        id.startsWith('water-') ||
        id.startsWith('site-') ||
        id.startsWith('building')) {
      return true;
    }
    if (id == 'label-motorway-shield' ||
        id.startsWith('label-street') ||
        id.startsWith('label-place') ||
        id.startsWith('symbol-transit')) {
      return true;
    }

    final isStreet =
        id.startsWith('street-') ||
        id.startsWith('tunnel-street-') ||
        id.startsWith('bridge-street-');
    if (isStreet) {
      return !id.contains(':outline') && !id.endsWith('-bicycle');
    }

    final isTransport =
        id.startsWith('transport-') ||
        id.startsWith('tunnel-transport-') ||
        id.startsWith('bridge-transport-');
    return isTransport && !id.contains(':outline');
  }
}

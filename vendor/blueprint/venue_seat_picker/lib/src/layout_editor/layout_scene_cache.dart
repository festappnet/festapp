import 'package:venue_layout_core/venue_layout_core.dart';

/// Retains canonical scene items across immutable document snapshots. Geometry
/// and presentation updates share one patch path; structural/global edits use
/// the full compiler. This cache owns only derived rendering data.
class LayoutSceneCache {
  VenueLayoutDocument? _document;
  Map<String, dynamic>? _resources, _presentation, _scene;
  Map<String, LayoutNode> _nodes = {};
  Map<String, List<String>> _children = {};

  Map<String, dynamic> update(
    VenueLayoutDocument document, {
    Map<String, dynamic> resources = const {},
    Map<String, dynamic> presentation = const {},
  }) {
    if (identical(_document, document) &&
        identical(_resources, resources) &&
        identical(_presentation, presentation)) {
      return _scene!;
    }
    final previous = _document;
    final documentChanged = !identical(previous, document);
    final canvasChanged =
        previous != null && !sameLayoutValue(previous.canvas, document.canvas);
    final nextNodes = documentChanged
        ? {for (final node in document.nodes) node.id: node}
        : _nodes;
    var full =
        previous == null ||
        (_scene?['issues'] as List? ?? const []).isNotEmpty ||
        !identical(_resources, resources) ||
        (documentChanged &&
            (previous.schemaVersion != document.schemaVersion ||
                previous.symbolSetVersion != document.symbolSetVersion ||
                !sameLayoutValue(previous.styles, document.styles) ||
                !sameLayoutValue(
                  previous.seatingDefaults,
                  document.seatingDefaults,
                ) ||
                !sameLayoutValue(previous.textPolicy, document.textPolicy) ||
                !sameLayoutValue(previous.background, document.background) ||
                !sameLayoutValue(
                  previous.selectionUnits,
                  document.selectionUnits,
                ) ||
                _nodes.length != nextNodes.length));
    final affected = <String>{};
    if (!full && documentChanged) {
      for (final node in document.nodes) {
        final old = _nodes[node.id];
        if (old == null ||
            old.kind != node.kind ||
            old.parentId != node.parentId ||
            old.z != node.z) {
          full = true;
          break;
        }
        if (!sameLayoutNode(old, node)) affected.add(node.id);
      }
      // Compiler validation is memoized per immutable snapshot. Invalid input
      // must replace the entire scene, never leave old valid items visible.
      if (validateDocument(document).isNotEmpty) full = true;
      if (!full) {
        final queue = affected.toList();
        for (var i = 0; i < queue.length; i++) {
          for (final id in _children[queue[i]] ?? const <String>[]) {
            if (affected.add(id)) queue.add(id);
          }
        }
      }
    }
    if (!full && !identical(_presentation, presentation)) {
      for (final id in {...?_presentation?.keys, ...presentation.keys}) {
        if (!sameLayoutValue(_presentation?[id], presentation[id])) {
          affected.add(id);
        }
      }
    }
    if (full) {
      _scene = compileScene(
        document,
        resources: resources,
        presentation: presentation,
      );
      _children = {};
      for (final node in document.nodes) {
        if (node.parentId != null) {
          (_children[node.parentId!] ??= []).add(node.id);
        }
      }
    } else if (affected.isNotEmpty || canvasChanged) {
      final patch = compileSceneNodes(
        document,
        affected,
        includeCanvas: canvasChanged,
        resources: resources,
        presentation: presentation,
      );
      bool canvasItem(dynamic item) =>
          item['kind'] == 'floor' || item['id'] == 'background';
      final canvasItems = <dynamic>[];
      final replacements = <String, List<dynamic>>{};
      for (final item in patch['items'] as List) {
        if (canvasChanged && canvasItem(item)) {
          canvasItems.add(item);
          continue;
        }
        (replacements['${item['nodeId'] ?? item['id']}'] ??= []).add(item);
      }
      final inserted = <String>{};
      final items = <dynamic>[...canvasItems];
      for (final item in _scene!['items'] as List) {
        if (canvasChanged && canvasItem(item)) continue;
        final id = '${item['nodeId'] ?? item['id']}';
        if (affected.contains(id)) {
          if (inserted.add(id)) items.addAll(replacements[id] ?? const []);
        } else {
          items.add(item);
        }
      }
      // An item may become visible after previously compiling to no paths.
      // Sort only this uncommon case, using canonical compiler paint ranks.
      var added = false;
      for (final entry in replacements.entries) {
        if (!inserted.contains(entry.key)) {
          items.addAll(entry.value);
          added = true;
        }
      }
      if (added) {
        items.sort((dynamic a, dynamic b) {
          final ar = a['paintOrder'] as List? ?? const [-1, 0];
          final br = b['paintOrder'] as List? ?? const [-1, 0];
          final rank = (ar[0] as num).compareTo(br[0] as num);
          return rank != 0 ? rank : (ar[1] as num).compareTo(br[1] as num);
        });
      }
      _scene = {
        ..._scene!,
        'canvas': document.canvas,
        'items': items,
        'issues': [
          ...(_scene!['issues'] as List).where(
            (dynamic i) => !affected.contains(i['nodeId']),
          ),
          ...patch['issues'] as List,
        ],
      };
    }
    if (!full && (_scene!['issues'] as List).isNotEmpty) {
      _scene = compileScene(
        document,
        resources: resources,
        presentation: presentation,
      );
    }
    _document = document;
    _nodes = nextNodes;
    _resources = resources;
    _presentation = presentation;
    return _scene!;
  }
}

/// Editor presentation retains the last successfully prepared text while a new
/// request is outstanding. Canonical scene validation and saved data stay intact.
class LayoutTextPreviewCache {
  final _ready = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? _input, _output;
  VenueLayoutDocument? _document;
  Map<String, dynamic> update(
    Map<String, dynamic> scene,
    VenueLayoutDocument document, {
    required bool enabled,
  }) {
    if (!enabled) {
      _ready.clear();
      _input = null;
      _output = null;
      _document = null;
      return scene;
    }
    if (identical(_input, scene) && identical(_document, document)) {
      return _output!;
    }
    final issues = scene['issues'] as List? ?? const [],
        nodes = {for (final node in document.nodes) node.id: node};
    const pendingReasons = {
      'text_layout_unavailable',
      'font_family_unavailable',
      'font_face_unavailable',
    };
    if (issues.any((issue) => !pendingReasons.contains(issue['reason']))) {
      _ready.clear();
      _input = null;
      _output = null;
      _document = null;
      return scene;
    }
    final pending = {
      for (final issue in issues)
        if (issue['nodeId'] is String) issue['nodeId'] as String,
    };
    _ready.removeWhere((id, _) => !nodes.containsKey(id));
    final items = List<Map<String, dynamic>>.from(scene['items'] as List);
    final readyIds = <String>{};
    for (final item in items) {
      if (item['kind'] == 'glyphs' && item['nodeId'] is String) {
        final id = item['nodeId'] as String;
        readyIds.add(id);
        _ready[id] = item;
      }
    }
    _ready.removeWhere(
      (id, _) => !pending.contains(id) && !readyIds.contains(id),
    );
    final retained = pending.intersection(_ready.keys.toSet());
    var output = scene;
    if (retained.isNotEmpty) {
      final matrices = worldMatrices(document),
          ordered = orderedNodes(document),
          ranks = {for (var i = 0; i < ordered.length; i++) ordered[i].id: i};
      for (final id in retained) {
        final node = nodes[id]!, previous = _ready[id]!;
        if (!ranks.containsKey(id)) continue;
        final item =
            <String, dynamic>{
                ...previous,
                'matrix': labelRenderMatrix(
                  node,
                  resolveNodeAppearance(document, node).label,
                  matrices[id]!.map(quantize).toList(),
                  textBounds: sceneItemBounds({
                    ...previous,
                    'matrix': [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
                  }),
                ),
                'paintOrder': [ranks[id], (previous['paintOrder'] as List)[1]],
                'pendingTextPreview': true,
              }
              ..remove('bounds')
              ..remove('cullingBounds');
        item['bounds'] = sceneItemBounds(item);
        items.add(item);
      }
      items.sort((a, b) {
        final x = a['paintOrder'] as List,
            y = b['paintOrder'] as List,
            first = (x[0] as num).compareTo(y[0] as num);
        return first != 0 ? first : (x[1] as num).compareTo(y[1] as num);
      });
      output = {
        ...scene,
        'items': items,
        'pendingTextPreviewIds': retained.toList()..sort(),
      };
    }
    _input = scene;
    _document = document;
    _output = output;
    return output;
  }
}

import 'dart:math' as math;
import 'layout_scene_surface.dart';
import 'canonical_appearance_panel.dart';
import 'package:flutter/material.dart';
import 'package:venue_layout_core/venue_layout_core.dart';
import '../venue_layout_controller.dart';
import 'layout_strings.dart';
import '../../templates/cinema_hall.dart';

/// Neutral work panels in light mode, with the host surface retained in dark mode.
Color layoutPanelColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.light
      ? Colors.white
      : theme.colorScheme.surface;
}

/// Application workspace only. Authored document fills remain export-accurate.
Color layoutWorkspaceColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF151B24)
    : const Color(0xFFE9EDF2);

/// Visual properties only: never transfers geometry, labels or seat identities.
class LayoutAppearance {
  const LayoutAppearance(this.object, {this.seats, this.canvasFill});
  final Map<String, dynamic> object;
  final Map<String, dynamic>? seats;
  final String? canvasFill;
}

const layoutAppearancePresets = <String, LayoutAppearance>{
  'Original': LayoutAppearance(
    {
      'fill': '#FFFFFFFF',
      'stroke': '#000000FF',
      'label': {'color': '#000000FF'},
      'strokeWidth': 1,
      'cornerRadius': 0,
    },
    seats: {
      'fill': '#267329FF',
      'stroke': '#00000000',
      'strokeWidth': 0,
      'cornerRadius': 8,
      'seatStyle': 'plain',
    },
    canvasFill: '#FFFFFFFF',
  ),
  'Neutral': LayoutAppearance(
    {
      'fill': '#E2E8F0FF',
      'label': {'color': '#202830FF'},
      'stroke': '#475569FF',
      'strokeWidth': 1,
      'cornerRadius': 6,
    },
    seats: {
      'fill': layoutDefaultSeatFill,
      'stroke': '#475569FF',
      'strokeWidth': 1,
      'cornerRadius': 5,
      'seatStyle': 'plain',
    },
    canvasFill: '#FFFFFFFF',
  ),
  'Warm': LayoutAppearance(
    {
      'fill': '#F0E4D2FF',
      'label': {'color': '#5D4431FF'},
      'stroke': '#8A6A48FF',
      'strokeWidth': 1,
      'cornerRadius': 14,
    },
    seats: {
      'fill': '#D9B788FF',
      'stroke': '#886342FF',
      'strokeWidth': 1.3,
      'cornerRadius': 8,
      'seatStyle': 'wood',
    },
    canvasFill: '#FFFBF5FF',
  ),
  'Slate': LayoutAppearance(
    {
      'fill': '#CBD5E1FF',
      'label': {'color': '#1E293BFF'},
      'stroke': '#334155FF',
      'strokeWidth': 1.5,
      'cornerRadius': 2,
    },
    seats: {
      'fill': '#DBEAFEFF',
      'stroke': '#1E40AFFF',
      'strokeWidth': 1.5,
      'cornerRadius': 1,
      'seatStyle': 'upholstered',
    },
    canvasFill: '#F1F5F9FF',
  ),
};

final layoutColorPalettes = <String, LayoutAppearance>{
  for (final entry in layoutAppearancePresets.entries)
    entry.key: LayoutAppearance(
      {
        for (final e in entry.value.object.entries)
          if (const {'fill', 'stroke', 'label'}.contains(e.key)) e.key: e.value,
      },
      seats: {
        for (final e in (entry.value.seats ?? entry.value.object).entries)
          if (const {'fill', 'stroke', 'label'}.contains(e.key)) e.key: e.value,
      },
      canvasFill: entry.value.canvasFill,
    ),
  for (final entry in layoutStudioPalettes.entries)
    entry.key: LayoutAppearance(
      {
        'fill': entry.value['surface'],
        'stroke': entry.value['edge'],
        'label': {'color': entry.value['ink']},
      },
      seats: {
        'fill': entry.value['seat'],
        'stroke': entry.value['edge'],
        'label': {'color': entry.value['ink']},
      },
      canvasFill: entry.value['canvas'],
    ),
};

String layoutNodeFill(
  VenueLayoutDocument document,
  LayoutNode node, {
  Map<String, LayoutNode>? nodesById,
}) {
  final props = effectiveNodeProperties(document, node);
  if (props['fill'] is String) {
    return props['fill'] as String;
  }
  if (node.kind == 'seat') {
    final parent = nodesById == null
        ? document.nodes.where((n) => n.id == node.parentId).firstOrNull
        : nodesById[node.parentId];
    return parent?.assembly?['kind'] == 'couch'
        ? '#F8FAFCFF'
        : layoutDefaultSeatFill;
  }
  return switch (node.kind) {
    'table' => '#E2E8F0FF',
    'capacityArea' => '#DBEAFEFF',
    _ => '#F1F5F9FF',
  };
}

/// Captures resolved presentation only. Child exceptions stay with their chairs.
LayoutAppearance captureLayoutAppearance(
  VenueLayoutDocument document,
  String id,
) {
  var root = document.nodes.firstWhere((node) => node.id == id);
  if (root.kind == 'group') {
    final ids = layoutSubtree(document, {root.id});
    root =
        document.nodes
            .where((node) => ids.contains(node.id) && node.kind == 'table')
            .firstOrNull ??
        document.nodes.firstWhere(
          (node) => ids.contains(node.id) && node.kind != 'group',
          orElse: () => root,
        );
  }
  final child = LayoutNode(
    id: '00000000-0000-4000-8000-000000000000',
    kind: 'seat',
    parentId: root.id,
  );
  return LayoutAppearance(
    materializedNodeStyle(document, root),
    seats: root.kind == 'table' ? materializedNodeStyle(document, child) : null,
  );
}

/// Appearance-only presets use the existing canonical preset document contract.
/// Empty nodes distinguish them from insertable object/assembly presets.
Map<String, LayoutAppearance> namedLayoutAppearances(
  VenueLayoutDocument document,
  String kind,
) => {
  for (final preset in document.presets)
    if ((preset['document']?['nodes'] as List?)?.isEmpty == true &&
        preset['document']?['styles']?['kinds']?[kind] is Map)
      preset['id'] as String: LayoutAppearance(
        Map<String, dynamic>.from(preset['document']['styles']['kinds'][kind]),
        seats:
            kind == 'table' &&
                preset['document']['styles']['kinds']['seat'] is Map
            ? Map<String, dynamic>.from(
                preset['document']['styles']['kinds']['seat'],
              )
            : null,
      ),
};

VenueLayoutDocument saveLayoutAppearancePreset(
  VenueLayoutDocument document,
  LayoutNode node,
  String name,
) {
  final title = name.trim();
  if (title.isEmpty || title.length > 80) {
    throw const FormatException('Enter a style name.');
  }
  if (document.presets.any(
    (p) => (p['title'] as String).toLowerCase() == title.toLowerCase(),
  )) {
    throw const FormatException('A style with this name already exists.');
  }
  final appearance = captureLayoutAppearance(document, node.id);
  final fragment = VenueLayoutDocument(
    styles: {
      'kinds': {
        node.kind: appearance.object,
        if (node.kind == 'table' && appearance.seats != null)
          'seat': appearance.seats,
      },
    },
  );
  return document.copyWith(
    presets: [
      ...document.presets,
      {
        'id': newLayoutId(),
        'title': title,
        'version': 1,
        'document': fragment.toJson(),
      },
    ],
  );
}

Map<String, dynamic> _mergeStyle(
  Map<String, dynamic> base,
  Map<String, dynamic> patch,
) => {
  ...base,
  ...patch,
  if (patch['label'] is Map)
    'label': {...base['label'] as Map? ?? {}, ...patch['label'] as Map},
};

VenueLayoutDocument applyLayoutAppearance(
  VenueLayoutDocument document,
  Set<String> ids,
  LayoutAppearance appearance,
) {
  final targets = layoutAppearanceTargets(document, ids),
      byId = {for (final node in document.nodes) node.id: node};
  return document.copyWith(
    nodes: [
      for (final node in document.nodes)
        if (!targets.contains(node.id) ||
            node.kind == 'seat' &&
                !ids.contains(node.id) &&
                byId[node.parentId]?.kind == 'table' &&
                targets.contains(node.parentId))
          node
        else
          node.copyWith(
            style: _mergeStyle(
              node.style,
              node.kind == 'image' || node.kind == 'vector'
                  ? {
                      if (appearance.object.containsKey('opacity'))
                        'opacity': appearance.object['opacity'],
                    }
                  : {
                      ...(node.kind == 'seat' && !ids.contains(node.id)
                          ? appearance.seats ?? appearance.object
                          : appearance.object),
                      if (const {
                        'line',
                        'polyline',
                        'arrow',
                      }.contains(node.properties['shape']))
                        'fill': '#00000000',
                    },
            ),
            childStyles: node.kind == 'table' && appearance.seats != null
                ? {
                    ...node.childStyles,
                    'seat': _mergeStyle(
                      Map<String, dynamic>.from(
                        node.childStyles['seat'] as Map? ?? {},
                      ),
                      appearance.seats!,
                    ),
                  }
                : node.childStyles,
          ),
    ],
  );
}

/// Copy only resolved text styling to editable peers of the same kind.
/// Individual overrides are replaced so each peer actually matches the source.
/// Geometry, authored text, child styles and document defaults stay untouched.
Set<String> layoutTextStyleTargets(
  VenueLayoutDocument document,
  LayoutNode source,
) {
  final peers = {
    for (final node in document.nodes)
      if (node.kind == source.kind && node.id != source.id) node.id,
  };
  return layoutAppearanceTargets(document, peers).intersection(peers);
}

VenueLayoutDocument applyLayoutTextStyle(
  VenueLayoutDocument document,
  LayoutNode source,
) {
  final targets = layoutTextStyleTargets(document, source);
  final label = resolveNodeAppearance(document, source).label;
  return document.copyWith(
    nodes: [
      for (final node in document.nodes)
        if (targets.contains(node.id))
          node.copyWith(
            style: {
              ...node.style,
              'label': {...label},
            },
          )
        else
          node,
    ],
  );
}

/// Apply one visual family through canonical kind defaults. Object overrides stay explicit.
VenueLayoutDocument applyGlobalLayoutAppearance(
  VenueLayoutDocument document,
  LayoutAppearance appearance,
) {
  var next = document;
  for (final kind in ['table', 'seat', 'furniture', 'shape', 'capacityArea']) {
    final patch = kind == 'seat'
        ? appearance.seats ?? appearance.object
        : appearance.object;
    for (final entry in patch.entries) {
      if (entry.key == 'label') {
        for (final label in (entry.value as Map).entries) {
          next = setKindStyleLeaf(next, kind, [
            'label',
            label.key as String,
          ], value: label.value);
        }
      } else {
        next = setKindStyleLeaf(next, kind, [entry.key], value: entry.value);
      }
    }
  }
  return next.copyWith(
    canvas: {
      ...next.canvas,
      if (appearance.canvasFill != null) 'fill': appearance.canvasFill,
    },
  );
}

Set<String> layoutAppearanceTargets(
  VenueLayoutDocument document,
  Set<String> roots,
) {
  final subtree = layoutSubtree(document, roots);
  final byId = {for (final n in document.nodes) n.id: n};
  // The controller also protects ancestors of locked nodes, since edits to an
  // assembly may affect those descendants. Match that acceptance contract.
  final protectedAncestors = <String>{};
  for (final node in document.nodes.where((node) => node.locked)) {
    LayoutNode? current = node;
    final seen = <String>{};
    while (current != null && seen.add(current.id)) {
      protectedAncestors.add(current.id);
      current = byId[current.parentId];
    }
  }
  bool locked(LayoutNode node) {
    if (protectedAncestors.contains(node.id)) return true;
    LayoutNode? current = node;
    final seen = <String>{};
    while (current != null && seen.add(current.id)) {
      if (current.locked) return true;
      current = byId[current.parentId];
    }
    return false;
  }

  return {
    for (final node in document.nodes)
      if (subtree.contains(node.id) && node.kind != 'group' && !locked(node))
        node.id,
  };
}

VenueLayoutDocument applyLayoutFamily(
  VenueLayoutDocument document,
  String family,
) => family == 'cinema'
    ? withCinemaAppearance(document)
    : withLayoutMaterialFamily(
        document,
        family,
      ).copyWith(canvas: document.canvas);

final layoutMaterialFamilyAppearances = {
  'cinema': LayoutAppearance(
    cinemaKindStyles['table']!,
    seats: cinemaKindStyles['seat'],
    canvasFill: cinemaCanvasFill,
  ),
  for (final family in layoutMaterialFamilies.keys)
    family: LayoutAppearance(
      layoutMaterialStyles(family)['table']!,
      seats: layoutMaterialStyles(family)['seat'],
    ),
};

/// Quick family chooser backed by the same canonical material definitions as rendering.
class LayoutMaterialFamilies extends StatelessWidget {
  const LayoutMaterialFamilies({
    super.key,
    required this.controller,
    this.nodeId,
  });
  final VenueLayoutController controller;
  final String? nodeId;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final family in const {
          'minimal': 'Minimal',
          'wood': 'Timber',
          'lounge': 'Lounge',
          'round': 'Round seating',
          'banquet': 'Banquet hall',
          'transit': 'Transport',
          'cinema': 'Cinema',
        }.entries)
          SizedBox(
            width: 124,
            height: 124,
            child: OutlinedButton(
              key: ValueKey('appearance-family-${family.key}'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: controller.readOnly || controller.saving
                  ? null
                  : () {
                      final appearance =
                          layoutMaterialFamilyAppearances[family.key]!;
                      controller.apply(
                        nodeId == null
                            ? applyLayoutFamily(controller.document, family.key)
                            : applyLayoutAppearance(controller.document, {
                                nodeId!,
                              }, appearance),
                        label: 'Apply style',
                      );
                    },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutStylePreview(
                    appearance: layoutMaterialFamilyAppearances[family.key]!,
                    size: const Size(96, 60),
                  ),
                  const SizedBox(height: 6),
                  LayoutText(
                    family.value,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class LayoutStylePresets extends StatefulWidget {
  const LayoutStylePresets({
    super.key,
    required this.controller,
    this.onApply,
    this.colorsOnly = false,
    this.appearances,
    this.labelFor,
  });
  final VenueLayoutController controller;
  final ValueChanged<LayoutAppearance>? onApply;
  final bool colorsOnly;
  final Map<String, LayoutAppearance>? appearances;
  final String Function(String)? labelFor;
  @override
  State<LayoutStylePresets> createState() => _LayoutStylePresetsState();
}

class _LayoutStylePresetsState extends State<LayoutStylePresets> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _scroll,
    thumbVisibility: true,
    trackVisibility: true,
    scrollbarOrientation: ScrollbarOrientation.bottom,
    child: SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 12),
      key: const ValueKey('layout-style-presets-scroll'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry
              in (widget.appearances ??
                      (widget.colorsOnly
                          ? layoutColorPalettes
                          : layoutAppearancePresets))
                  .entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox.square(
                dimension: 88,
                child: OutlinedButton(
                  key: ValueKey('layout-style-${entry.key}'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed:
                      widget.controller.readOnly || widget.controller.saving
                      ? null
                      : () => widget.onApply != null
                            ? widget.onApply!(entry.value)
                            : widget.controller.apply(
                                applyLayoutAppearance(
                                  widget.controller.document,
                                  widget.controller.selection,
                                  entry.value,
                                ),
                                label: 'Apply style',
                              ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LayoutStylePreview(appearance: entry.value),
                      const SizedBox(height: 5),
                      LayoutText(
                        widget.labelFor?.call(entry.key) ?? entry.key,
                        style: Theme.of(context).textTheme.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class LayoutStylePreview extends StatelessWidget {
  const LayoutStylePreview({
    super.key,
    required this.appearance,
    this.size = const Size(58, 40),
  });
  final Size size;
  final LayoutAppearance appearance;
  static final _previews = Expando<Map<Brightness, Map<String, dynamic>>>();
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final variants = _previews[appearance] ??= {};
    final data = variants[brightness] ??= (() {
      final base = tableLayout(shape: 'roundedRect');
      final bounds = selectionBounds(base, base.nodes.map((n) => n.id).toSet());
      final frame = Rect.fromLTWH(
        bounds['x']!,
        bounds['y']!,
        bounds['width']!,
        bounds['height']!,
      ).inflate(12);
      final doc = base.copyWith(
        nodes: [for (final node in base.nodes) node.copyWith(label: '')],
        canvas: {
          'x': frame.left,
          'y': frame.top,
          'width': frame.width,
          'height': frame.height,
          'fill':
              appearance.canvasFill ??
              (brightness == Brightness.dark ? '#252E3AFF' : '#F8FAFCFF'),
        },
        styles: {
          'kinds': {
            'table': appearance.object,
            'seat': appearance.seats ?? appearance.object,
          },
        },
      );
      return {'frame': frame, 'scene': compileScene(doc)};
    })();
    final frame = data['frame'] as Rect;
    final scale = math.min(
      size.width / frame.width,
      size.height / frame.height,
    );
    return CustomPaint(
      size: size,
      painter: LayoutScenePainter(
        scene: data['scene'] as Map<String, dynamic>,
        resources: const {},
        selected: const {},
        scale: scale,
        offset: Offset(
          (size.width - frame.width * scale) / 2 - frame.left * scale,
          (size.height - frame.height * scale) / 2 - frame.top * scale,
        ),
        canvasColor: Colors.transparent,
        selectionColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

Future<void> showLayoutStyleDialog(
  BuildContext context,
  VenueLayoutController controller,
) => controller.selection.isEmpty
    ? Future<void>.value()
    : showCanonicalAppearanceDialog(
        context,
        controller,
        nodeId: controller.selection.first,
      );

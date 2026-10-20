import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:venue_layout_core/venue_layout_core.dart';
import 'layout_scene_surface.dart';

/// Display-only catalogue preview. Uses the canonical painter without creating
/// a separate interactive canvas, camera, gesture handlers or focus target.
class LayoutPaletteThumbnail extends StatefulWidget {
  const LayoutPaletteThumbnail({
    super.key,
    required this.document,
    required this.resources,
    required this.kind,
  });
  final VenueLayoutDocument document;
  final Map<String, dynamic> resources;
  final String kind;
  @override
  State<LayoutPaletteThumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<LayoutPaletteThumbnail> {
  VenueLayoutDocument? _document;
  Map<String, dynamic>? _resources;
  Brightness? _brightness;
  late Map<String, dynamic> _scene;
  late Rect _bounds;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    if (!identical(_document, widget.document) ||
        !identical(_resources, widget.resources) ||
        _brightness != brightness) {
      final b = selectionBounds(
        widget.document,
        widget.document.nodes.map((n) => n.id).toSet(),
      );
      _bounds = Rect.fromLTWH(b['x']!, b['y']!, b['width']!, b['height']!);
      final preview = brightness == Brightness.dark
          ? widget.document.copyWith(
              nodes: [
                for (final node in widget.document.nodes)
                  if ({
                    'Line',
                    'Arrow',
                    'Polyline',
                    'Text',
                  }.contains(widget.kind))
                    node.copyWith(
                      style: {
                        ...node.style,
                        if (node.kind != 'text') 'stroke': '#CBD5E1FF',
                        if (node.kind == 'text')
                          'label': {
                            ...node.style['label'] as Map? ?? {},
                            'color': '#E2E8F0FF',
                          },
                      },
                    )
                  else
                    node,
              ],
            )
          : widget.document;
      _scene = compileScene(preview, resources: widget.resources);
      _brightness = brightness;
      _document = widget.document;
      _resources = widget.resources;
    }
    final extent = switch (widget.kind) {
      'Seat' => const Size(40, 40),
      'Round table' => const Size(68, 68),
      'Couch' => const Size(66, 44),
      'Bar' => const Size(82, 46),
      'Standing' || 'Rectangle' || 'Ellipse' || 'Polygon' => const Size(62, 40),
      'Line' || 'Arrow' || 'Polyline' => const Size(74, 32),
      'Text' => const Size(54, 34),
      _ => const Size(82, 54),
    };
    return ExcludeSemantics(
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox.fromSize(
            size: extent,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const padding = 3.0;
                final width = constraints.maxWidth,
                    height = constraints.maxHeight;
                final scale = math.min(
                  (width - padding * 2) / math.max(1, _bounds.width),
                  (height - padding * 2) / math.max(1, _bounds.height),
                );
                return RepaintBoundary(
                  child: CustomPaint(
                    size: extent,
                    painter: LayoutScenePainter(
                      scene: {
                        ..._scene,
                        'items': [
                          for (final item in _scene['items'] as List)
                            if ({
                              'Line',
                              'Arrow',
                              'Polyline',
                            }.contains(widget.kind))
                              {
                                ...Map<String, dynamic>.from(item as Map),
                                'strokeWidth': math.max(
                                  (item['strokeWidth'] as num? ?? 0).toDouble(),
                                  1.5 / scale,
                                ),
                              }
                            else
                              item,
                        ],
                      },
                      resources: widget.resources,
                      selected: const {},
                      scale: scale,
                      offset: Offset(
                        (width - _bounds.width * scale) / 2 -
                            _bounds.left * scale,
                        (height - _bounds.height * scale) / 2 -
                            _bounds.top * scale,
                      ),
                      canvasColor: Colors.transparent,
                      selectionColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

/// Editor-only paragraphs. Never serialized, prepared remotely or used by viewers.
class LayoutNativeTextCache {
  final _paragraphs = <String, ({String signature, TextPainter painter})>{};
  void dispose() {
    for (final entry in _paragraphs.values) {
      entry.painter.dispose();
    }
    _paragraphs.clear();
  }

  Map<String, dynamic> update(
    Map<String, dynamic> scene,
    VenueLayoutDocument document,
    Map<String, TextStyle> fonts,
    String Function(LayoutNode) fontKey, {
    Map<String, dynamic> presentation = const {},
  }) {
    final matrices = worldMatrices(document), nodes = orderedNodes(document);
    final items = <Map<String, dynamic>>[
      for (final raw in scene['items'] as List)
        if (!(raw['kind'] == 'glyphs' && '${raw['id']}'.endsWith(':text')))
          Map<String, dynamic>.from(raw as Map),
    ];
    final active = <String>{};
    final nativeIds = <String>{};
    for (var rank = 0; rank < nodes.length; rank++) {
      final node = nodes[rank];
      if (const {'seat', 'group', 'image', 'vector'}.contains(node.kind) ||
          node.assembly?['kind'] == 'couch' ||
          isBarNode(node)) {
        continue;
      }
      final text = node.kind == 'text'
          ? '${node.properties['text'] ?? ''}'
          : '${(presentation[node.id] as Map?)?['label'] ?? node.label}';
      if (text.isEmpty) continue;
      nativeIds.add(node.id);
      final native = fonts[fontKey(node)];
      if (native == null) continue;
      final label = resolveNodeAppearance(document, node).label;
      final width = math.max(1.0, node.width),
          height = math.max(1.0, node.height);
      final signature = '$text|${fontKey(node)}|$label|$width|$height';
      var entry = _paragraphs[node.id];
      if (entry?.signature != signature) {
        entry?.painter.dispose();
        final direction =
            label['direction'] == 'rtl' ||
                (label['direction'] == 'auto' &&
                    ((RegExp(
                              r'[A-Za-z\u00c0-\u08ff]',
                            ).firstMatch(text)?.group(0)?.codeUnitAt(0) ??
                            0) >=
                        0x590))
            ? TextDirection.rtl
            : TextDirection.ltr;
        final painter = TextPainter(
          textDirection: direction,
          textAlign: switch (label['align']) {
            'right' => TextAlign.right,
            'center' => TextAlign.center,
            _ => TextAlign.left,
          },
        );
        final rgba = int.parse(
          (label['color'] as String).substring(1),
          radix: 16,
        );
        final color = Color(((rgba & 255) << 24) | (rgba >> 8)).withValues(
          alpha:
              (rgba & 255) /
              255 *
              (resolveNodeAppearance(document, node).values['opacity'] as num)
                  .toDouble(),
        );
        void layout(double size) {
          painter.text = TextSpan(
            text: text,
            style: native.copyWith(
              fontSize: size,
              color: color,
              height: (label['lineHeight'] as num).toDouble(),
            ),
          );
          painter.layout(minWidth: width, maxWidth: width);
        }

        final size = (label['size'] as num).toDouble();
        layout(size);
        if (node.kind != 'text' && painter.height > height) {
          var low = 1.0, high = size;
          for (var i = 0; i < 10; i++) {
            final mid = (low + high) / 2;
            layout(mid);
            if (painter.height > height) {
              high = mid;
            } else {
              low = mid;
            }
          }
          layout(low);
        }
        entry = (signature: signature, painter: painter);
        _paragraphs[node.id] = entry;
      }
      active.add(node.id);
      final paragraph = entry!.painter;
      final offset = Offset(
        -width / 2,
        node.kind == 'text' ? -height / 2 : -paragraph.height / 2,
      );
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      final ink = boxes.isEmpty
          ? Rect.zero
          : boxes
                .map((b) => b.toRect())
                .reduce((a, b) => a.expandToInclude(b))
                .shift(offset);
      final matrix = labelRenderMatrix(
        node,
        label,
        matrices[node.id]!,
        textBounds: {
          'x': ink.left,
          'y': ink.top,
          'width': ink.width,
          'height': ink.height,
        },
      );
      items.add({
        'id': '${node.id}:text',
        'nodeId': node.id,
        'kind': 'nativeText',
        'matrix': matrix,
        'paintOrder': [rank, 100000],
        'nativeParagraph': paragraph,
        'nativeOffset': Offset(
          -width / 2,
          node.kind == 'text' ? -height / 2 : -entry.painter.height / 2,
        ),
        'localClip': {
          'x': -width / 2,
          'y': -height / 2,
          'width': width,
          'height': height,
        },
        'bounds': boundsOfPoints([
          for (final p in [
            [-width / 2, -height / 2],
            [width / 2, -height / 2],
            [width / 2, height / 2],
            [-width / 2, height / 2],
          ])
            transformPoint(matrix, p[0], p[1]),
        ]),
      });
    }
    for (final id in _paragraphs.keys.toList()) {
      if (!active.contains(id)) {
        _paragraphs.remove(id)!.painter.dispose();
      }
    }
    items.sort((a, b) {
      final x = a['paintOrder'] as List, y = b['paintOrder'] as List;
      final rank = (x[0] as num).compareTo(y[0] as num);
      return rank == 0 ? (x[1] as num).compareTo(y[1] as num) : rank;
    });
    return {
      ...scene,
      'items': items,
      'issues': [
        for (final issue in scene['issues'] as List)
          if (!(nativeIds.contains(issue['nodeId']) &&
              const {
                'text_layout_unavailable',
                'font_family_unavailable',
                'font_face_unavailable',
              }.contains(issue['reason'])))
            issue,
      ],
    };
  }
}

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'layout_scene_surface.dart';

enum LayoutPaletteFeedbackState { floating, canvas, blocked }

/// Paints the insertion fragment at canvas zoom, with its world origin at the
/// pointer. Bounds only size the paint viewport; they never recenter geometry.
class LayoutPaletteDragFeedback extends StatefulWidget {
  const LayoutPaletteDragFeedback({
    super.key,
    required this.document,
    required this.scale,
    required this.changes,
    required this.resources,
    this.state,
  });
  final VenueLayoutDocument Function() document;
  final double Function() scale;
  final Listenable changes;
  final ValueListenable<LayoutPaletteFeedbackState>? state;
  final Map<String, dynamic> resources;

  @override
  State<LayoutPaletteDragFeedback> createState() =>
      _LayoutPaletteDragFeedbackState();
}

class _LayoutPaletteDragFeedbackState extends State<LayoutPaletteDragFeedback> {
  late final _document = widget.document();
  late final _bounds = selectionBounds(
    _document,
    _document.nodes.map((n) => n.id).toSet(),
  );
  late final _scene = compileScene(
    _document.copyWith(canvas: {..._document.canvas, 'fill': '#00000000'}),
    resources: widget.resources,
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.changes, widget.state]),
    builder: (context, _) {
      if (widget.state?.value == LayoutPaletteFeedbackState.canvas) {
        return const SizedBox.shrink();
      }
      final scale = widget.scale();
      final origin = Offset(_bounds['x']!, _bounds['y']!) * scale;
      return Transform.translate(
        offset: origin,
        child: SizedBox(
          key: const ValueKey('palette-drag-feedback'),
          width: _bounds['width']! * scale,
          height: _bounds['height']! * scale,
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity:
                    widget.state?.value == LayoutPaletteFeedbackState.blocked
                    ? .45
                    : 1,
                child: CustomPaint(
                  painter: LayoutScenePainter(
                    scene: _scene,
                    resources: widget.resources,
                    selected: const {},
                    scale: scale,
                    offset: -origin,
                    canvasColor: Colors.transparent,
                    selectionColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              if (widget.state?.value ==
                  LayoutPaletteFeedbackState.blocked) ...[
                DecoratedBox(
                  key: const ValueKey('palette-drop-blocked'),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: .08),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.error,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                Positioned(
                  left: 0,
                  bottom: _bounds['height']! * scale + 6,
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.block,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 6),
                          LayoutText(
                            'Cannot place here',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

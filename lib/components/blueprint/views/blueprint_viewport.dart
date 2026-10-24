import 'package:flutter/material.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

import '../blueprint_object_model.dart';
import '../blueprint_strings.dart';

/// Visible camera controls share the viewer's transform and scale limits.
class BlueprintViewport extends StatelessWidget {
  const BlueprintViewport({
    super.key,
    required this.controller,
    required this.child,
  });

  final VenueSeatController<BlueprintObjectModel, Object> controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              const controlsHeight = 48.0;
              final center = Size(
                      constraints.maxWidth,
                      (constraints.maxHeight - controlsHeight)
                          .clamp(0.0, double.infinity))
                  .center(Offset.zero);
              void zoom(double factor) {
                final transform = controller.transformationController;
                final current = transform.value.getMaxScaleOnAxis();
                final next = (current * factor).clamp(controller.minScale, 5.0);
                final ratio = next / current;
                transform.value =
                    Matrix4.translationValues(center.dx, center.dy, 0)
                      ..multiply(Matrix4.diagonal3Values(ratio, ratio, ratio))
                      ..multiply(
                          Matrix4.translationValues(-center.dx, -center.dy, 0))
                      ..multiply(transform.value);
                controller.showTooltipFor(null);
              }

              return Column(
                children: [
                  Expanded(child: child),
                  SizedBox(
                    height: controlsHeight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: BlueprintStrings.zoomOut,
                          constraints:
                              const BoxConstraints(minWidth: 48, minHeight: 48),
                          onPressed: () => zoom(1 / 1.3),
                          icon: const Icon(Icons.zoom_out),
                        ),
                        ValueListenableBuilder<Matrix4>(
                          valueListenable: controller.transformationController,
                          builder: (context, matrix, _) => SizedBox(
                            width: 52,
                            child: Text(
                                '${(matrix.getMaxScaleOnAxis() * 100).round()}%',
                                textAlign: TextAlign.center),
                          ),
                        ),
                        IconButton(
                          tooltip: BlueprintStrings.zoomIn,
                          constraints:
                              const BoxConstraints(minWidth: 48, minHeight: 48),
                          onPressed: () => zoom(1.3),
                          icon: const Icon(Icons.zoom_in),
                        ),
                        IconButton(
                          tooltip: BlueprintStrings.fitToScreen,
                          constraints:
                              const BoxConstraints(minWidth: 48, minHeight: 48),
                          onPressed: controller.fitToViewport,
                          icon: const Icon(Icons.fit_screen),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(BlueprintStrings.touchHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      );
}

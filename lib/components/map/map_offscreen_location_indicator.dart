import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/map/map_current_location_drop.dart';
import 'package:fstapp/components/map/map_edge_indicator_layout.dart';
import 'package:fstapp/components/map/map_location_style.dart';
import 'package:fstapp/components/map/map_strings.dart';

class MapOffscreenLocationIndicator extends StatelessWidget {
  static const double size = 48;
  static const double visualSize = 42;
  static const dropKey = Key('mapOffscreenCurrentLocationDrop');

  static const double _visualTipLength = visualSize / 2;

  final Offset projectedLocation;
  final List<Rect> Function(Size viewport) occupiedRectsBuilder;
  final VoidCallback onPressed;

  const MapOffscreenLocationIndicator({
    required this.projectedLocation,
    required this.occupiedRectsBuilder,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final placement = MapEdgeIndicatorLayout.resolve(
              target: projectedLocation,
              viewport: constraints.biggest,
              occupiedRects: occupiedRectsBuilder(constraints.biggest),
              indicatorTipLength: _visualTipLength,
              indicatorClearance: visualSize / 2,
            );
            if (placement == null) return const SizedBox.shrink();
            return Stack(
              children: [
                Positioned(
                  left: placement.center.dx - size / 2,
                  top: placement.center.dy - size / 2,
                  child: IconButton(
                    tooltip: MapStrings.currentLocation,
                    padding: EdgeInsets.zero,
                    onPressed: onPressed,
                    icon: Transform.rotate(
                      angle: placement.rotationRadians,
                      child: const MapCurrentLocationDrop(
                        key: dropKey,
                        size: visualSize,
                        color: MapLocationStyle.color,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
}

import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'layout_scene_surface.dart';

/// Read-only, zoomable rendering of the shared core display list.
class VenueLayoutViewer extends StatelessWidget {
  const VenueLayoutViewer({
    super.key,
    required this.document,
    this.resources = const {},
    this.seatPresentation = const {},
    this.highlightedNodeIds = const {},
    this.highlightPulse,
    this.activeNodeIds = const {},
    this.focusNodeIds = const {},
    this.focusRevision = 0,
    this.focusMaxZoomFactor = 5,
    this.focusSeatPixelSize,
    this.onNodeTap,
    this.wheelZoomRequiresModifier = false,
  });

  /// Local presentation only. This viewer has no reservation/editor callbacks.
  final Set<String> highlightedNodeIds, activeNodeIds, focusNodeIds;

  /// Increment to request a fit of [focusNodeIds], or the canvas when empty.
  final int focusRevision;

  /// Optional one-shot emphasis; only the canvas painter listens to its ticks.
  final Animation<double>? highlightPulse;

  /// Maximum focus zoom relative to the whole-plan fit.
  final double focusMaxZoomFactor;

  /// Optional readable seat size in logical screen pixels, bounded by context.
  final double? focusSeatPixelSize;

  /// Embedded viewers can let normal wheel scrolling reach the parent page.
  final bool wheelZoomRequiresModifier;
  final ValueChanged<String?>? onNodeTap;
  final VenueLayoutDocument document;
  final Map<String, dynamic> resources, seatPresentation;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Venue plan. Pinch to zoom and drag to pan.',
    child: LayoutSceneSurface(
      document: document,
      wheelZoomRequiresModifier: wheelZoomRequiresModifier,
      resources: resources,
      presentation: seatPresentation,
      selected: activeNodeIds,
      highlightedIds: highlightedNodeIds,
      highlightPulse: highlightPulse,
      showSeatSelectionChecks: false,
      focusNodeIds: focusNodeIds,
      focusRevision: focusRevision,
      focusMaxZoomFactor: focusMaxZoomFactor,
      focusSeatPixelSize: focusSeatPixelSize,
      onPointTap: onNodeTap == null
          ? null
          : (point) => onNodeTap!(hitTest(document, point.dx, point.dy)),
    ),
  );
}

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
  });
  final VenueLayoutDocument document;
  final Map<String, dynamic> resources, seatPresentation;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Venue plan. Pinch to zoom and drag to pan.',
    child: LayoutSceneSurface(
      document: document,
      resources: resources,
      presentation: seatPresentation,
    ),
  );
}

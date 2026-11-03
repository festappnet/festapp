import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

import '../../_shared/common_strings.dart';
import '../../blueprint/blueprint_layout_resources.dart';

/// Uses the saved draft geometry and the same resource resolver as the editor.
class OccasionSetupBlueprintPreview extends StatefulWidget {
  const OccasionSetupBlueprintPreview({
    super.key,
    required this.document,
    required this.loadResources,
  });
  final VenueLayoutDocument document;
  final Future<Map<String, dynamic>> Function() loadResources;

  @override
  State<OccasionSetupBlueprintPreview> createState() =>
      _BlueprintPreviewState();
}

class _BlueprintPreviewState extends State<OccasionSetupBlueprintPreview> {
  final _assets = BlueprintLayoutAssetResolver();
  late Future<Map<String, dynamic>> _resources = _load();

  Future<Map<String, dynamic>> _load() async =>
      _assets.resolve(await widget.loadResources());

  @override
  void dispose() {
    _assets.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 280,
    child: FutureBuilder<Map<String, dynamic>>(
      future: _resources,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => _resources = _load()),
              child: Text(CommonStrings.retry),
            ),
          );
        }
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        return VenueLayoutViewer(
          document: widget.document,
          resources: snapshot.data!,
          wheelZoomRequiresModifier: true,
        );
      },
    ),
  );
}

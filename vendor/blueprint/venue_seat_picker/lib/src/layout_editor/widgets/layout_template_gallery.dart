import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/editor_ui.dart';

import 'layout_scene_surface.dart';
import 'layout_template_card.dart';

/// One visual template picker for the editor and host creation flows.
Future<LayoutTemplate?> showVenueLayoutTemplateGallery(
  BuildContext context, {
  Map<String, dynamic> resources = const {},
}) {
  return showEditorDialog<LayoutTemplate>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 700),
        child: Column(
          children: [
            ListTile(
              title: const LayoutText('Choose a starting plan'),
              subtitle: const LayoutText(
                'Every layout is editable. All sections stay on one plan.',
              ),
              trailing: IconButton(
                tooltip: VenueLayoutStrings.text(context, 'Close gallery'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, size) => GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: math.max(1, (size.maxWidth / 260).floor()),
                    mainAxisExtent: 250,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: VenueLayoutTemplates.recommended.length,
                  itemBuilder: (context, index) {
                    final template = VenueLayoutTemplates.recommended[index];
                    return LayoutTemplateCard(
                      key: ValueKey('layout-template-${template.id}'),
                      template: template,
                      onPressed: () => Navigator.pop(context, template),
                      preview: LayoutSceneSurface(
                        showControls: false,
                        animate: false,
                        document: template.create(),
                        resources: resources,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

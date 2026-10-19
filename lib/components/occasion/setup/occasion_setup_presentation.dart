import 'package:flutter/material.dart';
import 'package:fstapp/components/images/db_images.dart';
import 'package:fstapp/components/images/image_area.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_strings.dart';
import 'occasion_setup_details_strings.dart';

class OccasionSetupPresentation extends StatelessWidget {
  final int unitId;
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final ValueChanged<bool>? onBusyChanged;
  const OccasionSetupPresentation(
      {super.key,
      required this.unitId,
      required this.data,
      required this.onChanged,
      this.onBusyChanged});
  @override
  Widget build(BuildContext context) {
    final image = data['introImage'] as String?;
    final hasImage = image != null && image.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        key: ValueKey('place-${data['id']}'),
        initialValue: data['placeName'] as String? ?? '',
        decoration: InputDecoration(
            labelText: OccasionSettingsStrings.placeName,
            helperText: OccasionSetupDetailsStrings.text('optional')),
        onChanged: (v) => onChanged({'placeName': v}),
      ),
      const SizedBox(height: 24),
      TextFormField(
        key: ValueKey('description-${data['id']}'),
        initialValue: data['descriptionText'] as String? ?? '',
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(
            labelText: OccasionSettingsStrings.description,
            helperText: OccasionSetupDetailsStrings.text('optional')),
        onChanged: (v) =>
            onChanged({'descriptionText': v, 'description': _html(v)}),
      ),
      const SizedBox(height: 24),
      Text(OccasionSettingsStrings.introImage),
      const SizedBox(height: 8),
      ImageArea(
        imageUrl: image,
        hint: OccasionSetupDetailsStrings.text('imageHint'),
        onFileSelected: (file) async {
          onBusyChanged?.call(true);
          try {
            final url = await DbImages.uploadImage(
                await file.readAsBytes(), null, unitId,
                profile: ImageUploadProfile.banner);
            if (context.mounted) onChanged({'introImage': url});
            return url;
          } finally {
            if (context.mounted) onBusyChanged?.call(false);
          }
        },
        // Detaching a draft must never delete a shared unit asset.
        onRemove: () => onChanged({'introImage': null, 'isPromoted': false}),
      ),
      const SizedBox(height: 16),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: data['isPromoted'] == true,
        onChanged: hasImage ? (v) => onChanged({'isPromoted': v}) : null,
        title: Text(OccasionSetupDetailsStrings.text('promotion')),
        subtitle: Text(OccasionSetupDetailsStrings.text(
            hasImage ? 'promotionHint' : 'promotionNeedsImage')),
      ),
    ]);
  }

  static String _html(String text) => text
      .split('\n')
      .map((line) => line
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;'))
      .join('<br>');
}

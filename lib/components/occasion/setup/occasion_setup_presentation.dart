import 'package:fstapp/components/images/image_upload_input.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/images/db_images.dart';
import 'package:fstapp/components/images/image_area.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_strings.dart';

import 'occasion_setup_details_strings.dart';
import 'occasion_setup_sales.dart';
import 'occasion_setup_strings.dart';

String? occasionSetupCoverUrl(Map<String, dynamic> data) {
  final url = (data['introImage'] as String?)?.trim();
  return url == null || url.isEmpty ? null : url;
}

String? occasionSetupCoverIssue(
  Map<String, dynamic> data, {
  required bool appSupported,
}) {
  if (occasionSetupCoverUrl(data) != null) return null;
  if (appSupported && data['isPromoted'] == true) {
    return 'promotionImageRequired';
  }
  if (!appSupported && OccasionSetupSales.publishesToCatalog(data)) {
    return 'listingImageRequired';
  }
  return null;
}

class OccasionSetupPresentation extends StatelessWidget {
  final int unitId;
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final ValueChanged<bool>? onBusyChanged;
  const OccasionSetupPresentation({
    super.key,
    required this.unitId,
    required this.data,
    required this.onChanged,
    this.onBusyChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: ValueKey('place-${data['id']}'),
          initialValue: data['placeName'] as String? ?? '',
          decoration: InputDecoration(
            labelText: OccasionSettingsStrings.placeName,
            helperText: OccasionSetupDetailsStrings.text('optional'),
          ),
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
            helperText: OccasionSetupDetailsStrings.text('optional'),
          ),
          onChanged: (v) =>
              onChanged({'descriptionText': v, 'description': _html(v)}),
        ),
        const SizedBox(height: 24),
        _OccasionSetupCover(
          unitId: unitId,
          url: occasionSetupCoverUrl(data),
          onChanged: onChanged,
          onBusyChanged: onBusyChanged,
        ),
      ],
    );
  }

  static String _html(String text) => text
      .split('\n')
      .map(
        (line) => line
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;'),
      )
      .join('<br>');
}

class OccasionSetupPublication extends StatelessWidget {
  final int unitId;
  final bool appSupported;
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final ValueChanged<bool>? onBusyChanged;
  const OccasionSetupPublication({
    super.key,
    required this.unitId,
    required this.appSupported,
    required this.data,
    required this.onChanged,
    this.onBusyChanged,
  });
  @override
  Widget build(BuildContext context) {
    final issue = occasionSetupCoverIssue(data, appSupported: appSupported);
    final setting = appSupported ? 'isPromoted' : 'listPubliclyOnPublish';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: appSupported ? data[setting] == true : data[setting] != false,
          onChanged: (value) => onChanged({setting: value}),
          title: Text(
            appSupported
                ? OccasionSetupDetailsStrings.text('promotion')
                : OccasionSetupStrings.story('listingTitle'),
          ),
          subtitle: Text(
            appSupported
                ? OccasionSetupDetailsStrings.text('promotionHint')
                : OccasionSetupStrings.story('listingHint'),
          ),
        ),
        const SizedBox(height: 16),
        _OccasionSetupCover(
          unitId: unitId,
          url: occasionSetupCoverUrl(data),
          issue: issue,
          onChanged: onChanged,
          onBusyChanged: onBusyChanged,
        ),
      ],
    );
  }
}

class _OccasionSetupCover extends StatelessWidget {
  const _OccasionSetupCover({
    required this.unitId,
    required this.url,
    required this.onChanged,
    this.onBusyChanged,
    this.issue,
  });

  final int unitId;
  final String? url;
  final String? issue;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final ValueChanged<bool>? onBusyChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(OccasionSettingsStrings.introImage),
      if (issue != null)
        Text(
          OccasionSetupStrings.story(issue!),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      const SizedBox(height: 8),
      ImageArea(
        imageUrl: url,
        hint: OccasionSetupDetailsStrings.text('imageHint'),
        onFileSelected: (file) async {
          onBusyChanged?.call(true);
          try {
            final uploadedUrl = await DbImages.uploadImage(
              await ImageUploadInput.readFile(file),
              null,
              unitId,
              profile: ImageUploadProfile.banner,
            );
            if (context.mounted) onChanged({'introImage': uploadedUrl});
            return uploadedUrl;
          } finally {
            if (context.mounted) onBusyChanged?.call(false);
          }
        },
        // Detach the draft reference and keep the shared unit asset.
        onRemove: () => onChanged({'introImage': null}),
      ),
    ],
  );
}

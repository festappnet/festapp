import 'ticket_wallet_card_preview.dart';

import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../images/image_upload_limits.dart';
import '../google_wallet_appearance.dart';
import '../ticket_delivery_strings.dart';
import '../../features/ticket_feature.dart';
import '../../images/image_area.dart';
import '../../images/db_images.dart';

/// Inert native preview and three optional overrides. It never issues a pass.
class TicketWalletAppearanceEditor extends StatefulWidget {
  const TicketWalletAppearanceEditor({
    super.key,
    required this.feature,
    required this.occasion,
    required this.onChanged,
    this.occasionId,
    this.unitId,
    this.readOnly = false,
    this.uploadImage,
  });
  final TicketFeature feature;
  final Map<String, dynamic> occasion;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final int? occasionId, unitId;
  final bool readOnly;
  final Future<String?> Function(Uint8List)? uploadImage;
  @override
  State<TicketWalletAppearanceEditor> createState() =>
      _TicketWalletAppearanceEditorState();
}

class _TicketWalletAppearanceEditorState
    extends State<TicketWalletAppearanceEditor> {
  TicketWalletPlatform platform = TicketWalletPlatform.google;
  String t(String key) => TicketDeliveryStrings.text(key);
  @override
  Widget build(BuildContext context) {
    final overrides = widget.feature.walletAppearance ?? <String, dynamic>{};
    final appearance = GoogleWalletAppearance.fromTicket(
      widget.feature.toJson(),
      Map<String, dynamic>.from(widget.occasion['data'] as Map? ?? {}),
    );
    void change(String key, Object? value) =>
        widget.onChanged({...overrides, key: value});
    final uploadAllowed =
        !widget.readOnly &&
        (widget.occasionId != null || widget.unitId != null);
    Widget image(String key, String? effective, String label, String help) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ImageArea(
              imageUrl: overrides.containsKey(key)
                  ? overrides[key] as String?
                  : effective?.split('?').first,
              enabled: uploadAllowed,
              dropHeight: 120,
              allowedExtensions: const ['png', 'jpg', 'jpeg'],
              hint: help,
              onFileSelected: (file) async {
                if (await file.length() > ImageUploadLimits.maxInputBytes) {
                  throw FormatException(t('walletImageTooLarge'));
                }
                final bytes = await file.readAsBytes();
                final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
                try {
                  final descriptor = await ui.ImageDescriptor.encoded(buffer);
                  try {
                    if (descriptor.width * descriptor.height >
                        ImageUploadLimits.maxPixels) {
                      throw FormatException(t('walletImageTooLarge'));
                    }
                    if (key == 'logo' &&
                        (descriptor.width < 660 ||
                            descriptor.height < 660 ||
                            descriptor.width != descriptor.height)) {
                      throw FormatException(t('walletLogoSize'));
                    }
                  } finally {
                    descriptor.dispose();
                  }
                } finally {
                  buffer.dispose();
                }
                final url = widget.uploadImage != null
                    ? await widget.uploadImage!(bytes)
                    : await DbImages.uploadImage(
                        bytes,
                        widget.occasionId,
                        widget.occasionId == null ? widget.unitId : null,
                      );
                if (context.mounted) change(key, url);
                return url;
              },
              onRemove: () => change(key, null),
            ),
            const SizedBox(height: 16),
          ],
        );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 16),
          title: Text(t('walletAppearance')),
          subtitle: Text(t('walletAppearanceSummary')),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final value in TicketWalletPlatform.values)
                  ChoiceChip(
                    label: Text(
                      value == TicketWalletPlatform.google
                          ? 'Google Wallet'
                          : 'Apple Wallet',
                    ),
                    selected: platform == value,
                    onSelected: (_) => setState(() => platform = value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TicketWalletCardPreview(
              platform: platform,
              showSeat: widget.feature.layout?['templates']?[widget.feature.ticketType == 'named' ? 'named' : 'wide']?['spotGroupAppearance']?['showSeat'] == true,
              appearance: appearance,
              occasion: widget.occasion,
              previewLabel: t('walletPreview'),
              sampleCodeLabel: t('walletSampleCode'),
            ),
            const SizedBox(height: 12),
            Text(t('walletSampleCode')),
            const SizedBox(height: 8),
            Text(t('walletAppearanceRules')),
            const SizedBox(height: 16),
            TextFormField(
              key: ValueKey(overrides['background_color']),
              initialValue:
                  overrides['background_color'] as String? ??
                  appearance.backgroundColor,
              readOnly: widget.readOnly,
              decoration: InputDecoration(
                labelText: t('walletColor'),
                hintText: '#216acf',
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) =>
                  value == null ||
                      value.isEmpty ||
                      RegExp(r'^#?[a-fA-F0-9]{6}$').hasMatch(value)
                  ? null
                  : t('walletColorInvalid'),
              onChanged: widget.readOnly
                  ? null
                  : (value) {
                      if (value.isEmpty ||
                          RegExp(r'^#?[a-fA-F0-9]{6}$').hasMatch(value)) {
                        change(
                          'background_color',
                          value.isEmpty ? null : value,
                        );
                      }
                    },
            ),
            const SizedBox(height: 16),
            image(
              'logo',
              appearance.logo,
              t('walletLogo'),
              t('walletLogoSize'),
            ),
            image(
              'hero_image',
              appearance.heroImage,
              t('walletHero'),
              t('walletHeroHelp'),
            ),
            TextButton(
              onPressed: widget.readOnly ? null : () => widget.onChanged({}),
              child: Text(t('walletInherit')),
            ),
          ],
        ),
      ),
    );
  }
}

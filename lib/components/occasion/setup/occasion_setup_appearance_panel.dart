import 'package:fstapp/widgets/appearance_style_chooser.dart';
import 'package:fstapp/components/_shared/appearance_palettes.dart';
import 'package:fstapp/widgets/appearance_color_controls.dart';
import 'package:fstapp/components/_shared/appearance_color_strings.dart';

import 'occasion_setup_strings.dart';
import '../../fonts/font_family_picker.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:fstapp/widgets/app_dialog.dart';

class OccasionSetupAppearancePanel extends StatelessWidget {
  const OccasionSetupAppearancePanel({
    super.key,
    required this.onPresetSelected,
    required this.fontFamily,
    required this.fontFamilies,
    required this.onFontChanged,
    required this.primaryColor,
    required this.secondaryColor,
    required this.gradient,
    required this.onPrimaryChanged,
    required this.onSecondaryChanged,
    required this.onGradientChanged,
    required this.formPreview,
    this.fontStyle,
    this.previewFontStyle,
  });

  final ValueChanged<String> onPresetSelected;
  final String fontFamily;
  final List<String> fontFamilies;
  final ValueChanged<String> onFontChanged;
  final Color primaryColor;
  final Color secondaryColor;
  final bool gradient;
  final ValueChanged<Color> onPrimaryChanged;
  final ValueChanged<Color> onSecondaryChanged;
  final ValueChanged<bool> onGradientChanged;
  final Widget formPreview;

  /// Resolves the loaded font alias; the owner handles loading and failures.
  final TextStyle Function(String family, TextStyle base)? fontStyle;
  final Future<TextStyle> Function(String family)? previewFontStyle;

  void _pickColor(
    BuildContext context,
    String label,
    Color color,
    ValueChanged<Color> onChanged,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(label),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: color,
            onColorChanged: onChanged,
            enableAlpha: false,
            hexInputBar: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppearanceColorStrings.done),
          ),
        ],
      ),
    );
  }

  TextStyle _fontStyle(String family, TextStyle? base) {
    final resolvedBase = base ?? const TextStyle(fontSize: 16);
    return fontStyle?.call(family, resolvedBase) ?? resolvedBase;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FontFamilyPicker(
          value: fontFamily,
          families: fontFamilies,
          extraFamilies: const ['Roboto Slab', 'Russo One'],
          label: OccasionSetupStrings.ui('font'),
          canReset: false,
          selectedStyle: _fontStyle(fontFamily, theme.textTheme.bodyLarge),
          previewStyle: previewFontStyle,
          onSelected: (value) async {
            final family = value ?? 'Roboto';
            await previewFontStyle?.call(family);
            onFontChanged(family);
          },
        ),
        const SizedBox(height: 24),
        AppearanceStyleChooser(
          primaryColor: primaryColor.toARGB32(),
          secondaryColor: secondaryColor.toARGB32(),
          gradient: gradient,
          onSelected: (palette) => onPresetSelected(palette.id),
          controls: AppearanceColorControls(
            paletteName: AppearancePalettes.match(
              primaryColor.toARGB32(),
              secondaryColor.toARGB32(),
              gradient,
            )?.label,
            gradient: gradient,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            onGradientChanged: onGradientChanged,
            onPrimaryPressed: () => _pickColor(
              context,
              gradient
                  ? AppearanceColorStrings.first
                  : AppearanceColorStrings.theme,
              primaryColor,
              onPrimaryChanged,
            ),
            onSecondaryPressed: () => _pickColor(
              context,
              AppearanceColorStrings.second,
              secondaryColor,
              onSecondaryChanged,
            ),
          ),
        ),
        const SizedBox(height: 24),
        formPreview,
      ],
    );
  }
}

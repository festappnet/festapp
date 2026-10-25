import 'occasion_setup_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:fstapp/widgets/app_dialog.dart';

/// Display data only; the setup owner resolves and persists each preset.
class OccasionSetupAppearancePreset {
  const OccasionSetupAppearancePreset({
    required this.id,
    required this.label,
    required this.primaryColor,
    required this.secondaryColor,
    required this.gradient,
    required this.fontFamily,
  });
  final String id;
  final String label;
  final Color primaryColor;
  final Color secondaryColor;
  final bool gradient;
  final String fontFamily;
}

class OccasionSetupAppearancePanel extends StatelessWidget {
  const OccasionSetupAppearancePanel({
    super.key,
    required this.presets,
    required this.selectedPresetId,
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
    this.customLabel,
  });

  final List<OccasionSetupAppearancePreset> presets;
  final String? selectedPresetId;
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
  final String? customLabel;

  Widget _colorControl(BuildContext context, String label, Color color,
      ValueChanged<Color> onChanged) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: () => showDialog<void>(
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
                child: const Text('Hotovo'))
          ],
        ),
      ),
      icon: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          )),
      label: Text(label),
    );
  }

  Color _previewColor(Color color) {
    final hsl = HSLColor.fromColor(color);
    var lightness = hsl.lightness;
    while ((1.05 / (color.computeLuminance() + .05)) < 4.5 && lightness > .02) {
      lightness -= .02;
      color = hsl.withLightness(lightness.clamp(0.0, 1.0)).toColor();
    }
    return color;
  }

  TextStyle _fontStyle(String family, TextStyle? base) {
    final resolvedBase = base ?? const TextStyle(fontSize: 16);
    return fontStyle?.call(family, resolvedBase) ?? resolvedBase;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 700;
      final columns = (constraints.maxWidth / 220).floor().clamp(2, 6);
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          key: ValueKey('appearance-font-$fontFamily'),
          initialValue: fontFamilies.contains(fontFamily) ? fontFamily : null,
          isExpanded: true,
          itemHeight: null,
          selectedItemBuilder: (context) => [
            for (final family in fontFamilies)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(family,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _fontStyle(family, theme.textTheme.bodyLarge)),
              ),
          ],
          decoration: InputDecoration(
              labelText: OccasionSetupStrings.ui('font'),
              border: OutlineInputBorder()),
          items: [
            for (final family in fontFamilies)
              DropdownMenuItem(
                  value: family,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(family,
                        style: _fontStyle(family, theme.textTheme.bodyLarge)),
                  ))
          ],
          onChanged: (value) {
            if (value != null) onFontChanged(value);
          },
        ),
        const SizedBox(height: 24),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final preset in presets)
            SizedBox(
              width: largeText
                  ? constraints.maxWidth
                  : narrow
                      ? (constraints.maxWidth < 320
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 12) / 2)
                      : (constraints.maxWidth - (columns - 1) * 12) / columns,
              child: Semantics(
                selected: selectedPresetId == preset.id,
                child: OutlinedButton(
                  key: ValueKey('appearance-preset-${preset.id}'),
                  onPressed: () => onPresetSelected(preset.id),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.all(12),
                    side: BorderSide(
                        color: selectedPresetId == preset.id
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                        width: selectedPresetId == preset.id ? 2 : 1),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          constraints: const BoxConstraints(minHeight: 82),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: preset.gradient
                                ? null
                                : _previewColor(preset.primaryColor),
                            gradient: preset.gradient
                                ? LinearGradient(colors: [
                                    _previewColor(preset.primaryColor),
                                    _previewColor(preset.secondaryColor),
                                  ])
                                : null,
                          ),
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                              OccasionSetupStrings.ui('our_event_story'),
                              style: _fontStyle(preset.fontFamily,
                                      theme.textTheme.titleLarge)
                                  .copyWith(
                                      color: Colors.white,
                                      fontSize: narrow ? 18 : 22)),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: Text(preset.label,
                                  style: _fontStyle(preset.fontFamily,
                                      theme.textTheme.titleSmall))),
                          SizedBox(
                              width: 20,
                              height: 20,
                              child: selectedPresetId == preset.id
                                  ? const Icon(Icons.check, size: 20)
                                  : null),
                        ]),
                      ]),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        ExpansionTile(
          key: ValueKey('appearance-custom-${selectedPresetId == null}'),
          initiallyExpanded: selectedPresetId == null,
          tilePadding: EdgeInsets.zero,
          title:
              Text(customLabel ?? OccasionSetupStrings.ui('custom_appearance')),
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(OccasionSetupStrings.ui('two_color_gradient')),
              value: gradient,
              onChanged: onGradientChanged,
            ),
            Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(spacing: 12, runSpacing: 8, children: [
                  _colorControl(
                      context,
                      OccasionSetupStrings.ui('primary_color'),
                      primaryColor,
                      onPrimaryChanged),
                  if (gradient)
                    _colorControl(
                        context,
                        OccasionSetupStrings.ui('secondary_color'),
                        secondaryColor,
                        onSecondaryChanged),
                ])),
            const SizedBox(height: 16),
          ],
        ),
        const SizedBox(height: 24),
        formPreview,
      ]);
    });
  }
}

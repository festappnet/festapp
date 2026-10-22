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
    this.customLabel = 'Vlastní vzhled',
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
  final String customLabel;

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

  TextStyle _fontStyle(String family, TextStyle? base) {
    final resolvedBase = base ?? const TextStyle(fontSize: 16);
    return fontStyle?.call(family, resolvedBase) ?? resolvedBase;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 700;
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          key: ValueKey('appearance-font-$fontFamily'),
          initialValue: fontFamilies.contains(fontFamily) ? fontFamily : null,
          isExpanded: true,
          itemHeight: null,
          decoration: const InputDecoration(
              labelText: 'Písmo', border: OutlineInputBorder()),
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
                      ? (constraints.maxWidth < 360
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 12) / 2)
                      : (constraints.maxWidth - 24) / 3,
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
                        ExcludeSemantics(
                            child: Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  color: preset.gradient
                                      ? null
                                      : preset.primaryColor,
                                  gradient: preset.gradient
                                      ? LinearGradient(colors: [
                                          preset.primaryColor,
                                          preset.secondaryColor
                                        ])
                                      : null,
                                ))),
                        const SizedBox(height: 8),
                        Text(preset.label,
                            style: _fontStyle(preset.fontFamily,
                                theme.textTheme.titleMedium)),
                        Text('Příběh naší akce',
                            style: _fontStyle(
                                preset.fontFamily, theme.textTheme.bodyLarge)),
                        SizedBox(
                          height: 20,
                          child: selectedPresetId == preset.id
                              ? const Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Icon(Icons.check, size: 20))
                              : null,
                        ),
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
          title: Text(customLabel),
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dvoubarevný přechod'),
              value: gradient,
              onChanged: onGradientChanged,
            ),
            Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(spacing: 12, runSpacing: 8, children: [
                  _colorControl(
                      context, 'Hlavní barva', primaryColor, onPrimaryChanged),
                  if (gradient)
                    _colorControl(context, 'Druhá barva', secondaryColor,
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

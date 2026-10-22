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
    this.ticketPreview,
    this.ticketSettings,
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
  final Widget? ticketPreview;
  final Widget? ticketSettings;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 700;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final preset in presets)
            SizedBox(
              width: narrow
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
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontFamily: preset.fontFamily)),
                        Text('Příběh naší akce',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontFamily: preset.fontFamily)),
                        if (selectedPresetId == preset.id)
                          const Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Icon(Icons.check, size: 20)),
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
            DropdownButtonFormField<String>(
              initialValue:
                  fontFamilies.contains(fontFamily) ? fontFamily : null,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Písmo', border: OutlineInputBorder()),
              items: [
                for (final family in fontFamilies)
                  DropdownMenuItem(value: family, child: Text(family))
              ],
              onChanged: (value) {
                if (value != null) onFontChanged(value);
              },
            ),
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
        if (ticketPreview == null)
          formPreview
        else if (narrow)
          DefaultTabController(
            length: 2,
            child: Builder(builder: (context) {
              final controller = DefaultTabController.of(context);
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const TabBar(
                        tabs: [Tab(text: 'Formulář'), Tab(text: 'Vstupenka')]),
                    const SizedBox(height: 16),
                    AnimatedBuilder(
                        animation: controller,
                        builder: (context, _) => controller.index == 0
                            ? formPreview
                            : ticketPreview!),
                  ]);
            }),
          )
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Text('Formulář', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  formPreview
                ])),
            const SizedBox(width: 24),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Text('Vstupenka', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  ticketPreview!
                ])),
          ]),
        if (ticketSettings != null) ...[
          const SizedBox(height: 24),
          ticketSettings!
        ],
      ]);
    });
  }
}

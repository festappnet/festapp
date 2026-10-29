import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/appearance_color_strings.dart';
import 'package:fstapp/components/_shared/appearance_palettes.dart';
import 'package:fstapp/components/forms/form_strings.dart';

/// Shared color selection; persistence and color editing stay with the owner.
class AppearanceStyleChooser extends StatefulWidget {
  const AppearanceStyleChooser({
    super.key,
    required this.primaryColor,
    required this.secondaryColor,
    required this.gradient,
    required this.onSelected,
    required this.controls,
  });
  final int? primaryColor;
  final int? secondaryColor;
  final bool gradient;
  final ValueChanged<AppearancePalette>? onSelected;
  final Widget controls;

  @override
  State<AppearanceStyleChooser> createState() => _AppearanceStyleChooserState();
}

class _AppearanceStyleChooserState extends State<AppearanceStyleChooser> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final selected = AppearancePalettes.match(
      widget.primaryColor,
      widget.secondaryColor,
      widget.gradient,
    );
    final inherited =
        widget.primaryColor == null &&
        (!widget.gradient || widget.secondaryColor == null);
    final status = selected != null
        ? AppearanceColorStrings.palette(selected.label)
        : inherited
        ? AppearanceColorStrings.inherited
        : AppearanceColorStrings.custom;
    final visible = _expanded
        ? AppearancePalettes.all
        : [
            ...AppearancePalettes.all.take(6),
            if (selected != null &&
                !AppearancePalettes.all.take(6).contains(selected))
              selected,
          ];
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(AppearanceColorStrings.style, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            status,
            key: const ValueKey('appearance-style-status'),
            style: theme.textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 4),
        Text(AppearanceColorStrings.paletteHint),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final palette in visible)
              ChoiceChip(
                key: ValueKey('appearance-style-${palette.id}'),
                selected: selected == palette,
                onSelected: widget.onSelected == null
                    ? null
                    : (_) => widget.onSelected!(palette),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                avatar: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Color(palette.primary),
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.outline),
                    gradient: widget.gradient
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(palette.primary),
                              Color(palette.secondary),
                            ],
                          )
                        : null,
                  ),
                ),
                label: Text(palette.label),
              ),
          ],
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('appearance-styles-more'),
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            label: Text(_expanded ? FormStrings.less : FormStrings.more),
          ),
        ),
        const SizedBox(height: 8),
        widget.controls,
      ],
    );
  }
}

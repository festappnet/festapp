import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/appearance_color_strings.dart';

/// The same optional color mode and editable colors in setup and form design.
/// The owner retains the secondary color when switching back to a solid theme.
class AppearanceColorControls extends StatelessWidget {
  const AppearanceColorControls({
    super.key,
    required this.gradient,
    required this.primaryColor,
    required this.secondaryColor,
    required this.onGradientChanged,
    required this.onPrimaryPressed,
    required this.onSecondaryPressed,
    this.onPrimaryReset,
    this.onSecondaryReset,
    this.resetLabel,
  });

  final bool gradient;
  final Color primaryColor;
  final Color secondaryColor;
  final ValueChanged<bool>? onGradientChanged;
  final VoidCallback? onPrimaryPressed;
  final VoidCallback? onSecondaryPressed;
  final VoidCallback? onPrimaryReset;
  final VoidCallback? onSecondaryReset;
  final String? resetLabel;

  Widget _color(
    BuildContext context,
    String id,
    String label,
    Color color,
    VoidCallback? onPressed,
    VoidCallback? onReset,
  ) {
    final theme = Theme.of(context);
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: ValueKey('appearance-color-$id'),
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(12),
              minimumSize: const Size(48, 64),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.colorScheme.outline),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.labelLarge),
                      Text(hex, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.edit_outlined, size: 20),
              ],
            ),
          ),
        ),
        if (onReset != null)
          IconButton(
            tooltip: '$resetLabel: $label',
            onPressed: onReset,
            icon: const Icon(Icons.refresh),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(AppearanceColorStrings.gradient),
          subtitle: Text(AppearanceColorStrings.hint),
          value: gradient,
          onChanged: onGradientChanged,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide =
                gradient &&
                constraints.maxWidth >= 560 &&
                MediaQuery.textScalerOf(context).scale(16) <= 24;
            final primary = _color(
              context,
              'primary',
              gradient
                  ? AppearanceColorStrings.first
                  : AppearanceColorStrings.theme,
              primaryColor,
              onPrimaryPressed,
              onPrimaryReset,
            );
            final secondary = _color(
              context,
              'secondary',
              AppearanceColorStrings.second,
              secondaryColor,
              onSecondaryPressed,
              onSecondaryReset,
            );
            if (!gradient) return primary;
            if (sideBySide) {
              return Row(
                children: [
                  Expanded(child: primary),
                  const SizedBox(width: 12),
                  Expanded(child: secondary),
                ],
              );
            }
            return Column(
              children: [primary, const SizedBox(height: 12), secondary],
            );
          },
        ),
      ],
    );
  }
}

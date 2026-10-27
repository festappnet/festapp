import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_strings.dart';
import 'package:fstapp/components/unit/unit_strings.dart';
import 'package:fstapp/styles/styles_config.dart';

/// Keeps creation choices attached to their entry point in the event list.
class OccasionCreationButton extends StatelessWidget {
  const OccasionCreationButton({
    super.key,
    required this.showChoices,
    required this.onGuided,
    required this.onQuick,
    this.builder,
  });

  final Widget Function(VoidCallback onPressed)? builder;
  final bool showChoices;
  final VoidCallback onGuided;
  final VoidCallback onQuick;

  Widget _button(VoidCallback onPressed) => builder?.call(onPressed) ?? FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 18),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(UnitStrings.addNewEvent),
            if (showChoices) ...[
              const SizedBox(width: 8),
              const ExcludeSemantics(
                  child: Icon(Icons.arrow_drop_down, size: 20)),
            ],
          ],
        ),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(StylesConfig.commonRoundness),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!showChoices) return _button(onQuick);
    final colors = Theme.of(context).colorScheme;
    return MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      consumeOutsideTap: true,
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomEnd,
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        )),
      ),
      menuChildren: [
        _option(
          context,
          onPressed: onGuided,
          title: OccasionSetupStrings.stepByStep,
          description: OccasionSetupStrings.guidedCreationDescription,
          background: colors.primaryContainer,
          foreground: colors.onPrimaryContainer,
        ),
        const SizedBox(height: 4),
        _option(
          context,
          onPressed: onQuick,
          title: OccasionSetupStrings.withoutWizard,
          description: OccasionSetupStrings.quickCreationDescription,
          foreground: colors.onSurface,
        ),
      ],
      builder: (context, controller, child) => _button(() {
        controller.isOpen ? controller.close() : controller.open();
      }),
    );
  }

  Widget _option(
    BuildContext context, {
    required VoidCallback onPressed,
    required String title,
    required String description,
    required Color foreground,
    Color? background,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return MenuItemButton(
      onPressed: onPressed,
      // MenuItemButton closes the menu before invoking the selected flow.
      closeOnActivate: true,
      style: MenuItemButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        padding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: SizedBox(
        width:
            math.min(270, math.max(80, MediaQuery.sizeOf(context).width - 112)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                style: textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700, color: foreground)),
            const SizedBox(height: 4),
            Text(description,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: foreground)),
          ],
        ),
      ),
    );
  }
}

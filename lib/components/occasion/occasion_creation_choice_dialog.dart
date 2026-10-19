import 'package:flutter/material.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_strings.dart';
import 'package:fstapp/components/unit/unit_strings.dart';
import 'package:fstapp/widgets/app_dialog.dart';

enum OccasionCreationChoice { guided, quick }

class OccasionCreationChoiceDialog extends StatelessWidget {
  const OccasionCreationChoiceDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppAlertDialog(
      title: Text(UnitStrings.addNewEvent),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      content: SizedBox(
        width: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              OccasionSetupStrings.chooseCreation,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            _CreationOption(
              choice: OccasionCreationChoice.guided,
              icon: Icons.confirmation_number_outlined,
              title: OccasionSetupStrings.stepByStep,
              description: OccasionSetupStrings.guidedCreationDescription,
              recommendation: OccasionSetupStrings.recommendedForTickets,
            ),
            const SizedBox(height: 12),
            _CreationOption(
              choice: OccasionCreationChoice.quick,
              icon: Icons.edit_calendar_outlined,
              title: OccasionSetupStrings.withoutWizard,
              description: OccasionSetupStrings.quickCreationDescription,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreationOption extends StatelessWidget {
  const _CreationOption({
    required this.choice,
    required this.icon,
    required this.title,
    required this.description,
    this.recommendation,
  });

  final OccasionCreationChoice choice;
  final IconData icon;
  final String title;
  final String description;
  final String? recommendation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final recommended = recommendation != null;
    return OutlinedButton(
      onPressed: () => Navigator.of(context).pop(choice),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(16),
        foregroundColor: colors.onSurface,
        backgroundColor: recommended ? colors.primaryContainer : colors.surface,
        side: BorderSide(
          color: recommended ? colors.primary : colors.outlineVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              icon,
              size: 24,
              color: recommended
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (recommendation != null) ...[
                  Text(
                    recommendation!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: recommended
                        ? colors.onPrimaryContainer
                        : colors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: recommended
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ExcludeSemantics(
            child: Icon(
              Icons.chevron_right,
              size: 20,
              color: recommended
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';

class OccasionSetupReviewRow extends StatelessWidget {
  const OccasionSetupReviewRow(
    this.label,
    this.value, {
    super.key,
    this.hasError = false,
  });
  final String label, value;
  final bool hasError;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelWidget = Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        );
        final valueWidget = SelectableText(
          value,
          style: hasError
              ? TextStyle(color: Theme.of(context).colorScheme.error)
              : null,
        );
        if (constraints.maxWidth < 540) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelWidget, valueWidget],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 205, child: labelWidget),
            Expanded(child: valueWidget),
          ],
        );
      },
    ),
  );
}

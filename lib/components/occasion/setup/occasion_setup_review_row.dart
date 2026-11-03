import 'package:material_ui/material_ui.dart';

class OccasionSetupReviewRow extends StatelessWidget {
  const OccasionSetupReviewRow(this.label, this.value, {super.key});
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final labelWidget = Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        );
        if (constraints.maxWidth < 540) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelWidget, SelectableText(value)],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 205, child: labelWidget),
            Expanded(child: SelectableText(value)),
          ],
        );
      },
    ),
  );
}

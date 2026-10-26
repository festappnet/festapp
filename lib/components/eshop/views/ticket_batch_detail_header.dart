import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/utilities_all.dart';
import '../ticket_batch_strings.dart';

/// Keeps batch-wide printing separate from actions on selected tickets.
class TicketBatchDetailHeader extends StatelessWidget {
  const TicketBatchDetailHeader({
    super.key,
    required this.batch,
    required this.selectedCount,
    required this.onBack,
    required this.printActions,
    required this.selectionActions,
    required this.lookup,
    this.notices = const [],
  });

  final Map<String, dynamic> batch;
  final int selectedCount;
  final VoidCallback onBack;
  final List<Widget> printActions, selectionActions, notices;
  final Widget lookup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = batch['counts'] as Map;
    final secondary = theme.colorScheme.onSurfaceVariant;
    String text(String key) => TicketBatchStrings.text(key);
    String money(String key) =>
        Utilities.formatPrice(context, (batch[key] as num? ?? 0).toDouble(),
            currencyCode: batch['currency'] as String);
    Widget summary(String label, String value) => Text.rich(TextSpan(children: [
          TextSpan(text: '$label: ', style: TextStyle(color: secondary)),
          TextSpan(
              text: value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ]));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 760;
        final heading = Row(children: [
          BackButton(onPressed: onBack),
          const SizedBox(width: 4),
          Expanded(
              child: Text(batch['title'] as String,
                  style: theme.textTheme.titleLarge)),
        ]);
        final printing = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: printActions);
        final selection = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(TicketBatchStrings.selectedCount(selectedCount),
                    style:
                        theme.textTheme.bodyMedium?.copyWith(color: secondary)),
              ),
              ...selectionActions,
            ]);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (narrow) ...[
              heading,
              if (printActions.isNotEmpty) ...[
                const SizedBox(height: 8),
                printing,
              ],
            ] else
              Row(children: [
                Expanded(child: heading),
                const SizedBox(width: 16),
                Flexible(
                    child: Align(
                        alignment: Alignment.centerRight, child: printing))
              ]),
            const SizedBox(height: 12),
            Wrap(spacing: 24, runSpacing: 8, children: [
              summary(text('available'), '${counts['available']}'),
              summary(text('sold'), '${counts['soldActive']}'),
              summary(text('voided'),
                  '${(counts['voidedUnsold'] as num? ?? 0) + (counts['cancelledAfterSale'] as num? ?? 0)}'),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 24, runSpacing: 8, children: [
              summary(text('stockValue'), money('stockValue')),
              summary(text('receivedAmount'), money('receivedAmount')),
            ]),
            for (final notice in notices)
              Padding(padding: const EdgeInsets.only(top: 8), child: notice),
            const Divider(height: 24),
            if (narrow) ...[
              Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: lookup)),
              const SizedBox(height: 12),
              selection,
            ] else
              Row(children: [
                SizedBox(width: 320, child: lookup),
                const SizedBox(width: 16),
                Expanded(
                    child: Align(
                        alignment: Alignment.centerRight, child: selection)),
              ]),
            if (selectionActions.isNotEmpty && selectedCount == 0) ...[
              const SizedBox(height: 8),
              Text(text('selectionHint'),
                  style: theme.textTheme.bodySmall?.copyWith(color: secondary)),
            ],
          ],
        );
      }),
    );
  }
}

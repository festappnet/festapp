import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/utilities_all.dart';

import 'discount_strings.dart';

/// Same compact, cent-preserving presentation as web and email summaries.
String formatDiscountPrice(BuildContext context, num value, String? currency) {
  final cents = (value * 100).round();
  final digits = cents % 100 == 0
      ? 0
      : cents % 10 == 0
      ? 1
      : 2;
  return Utilities.formatPrice(
    context,
    value.toDouble(),
    currencyCode: currency,
    decimalDigits: digits,
  );
}

/// Displays the server's original, discount and net amounts without repricing.
class DiscountSummary extends StatelessWidget {
  const DiscountSummary({super.key, required this.discount});

  final Map<String, dynamic> discount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget amountRow(String key, {bool total = false}) {
      final style = total
          ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
          : theme.textTheme.bodyMedium;
      final amount = formatDiscountPrice(
        context,
        discount[key] as num,
        discount['currency'],
      );
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(DiscountStrings.text(key), style: style)),
            const SizedBox(width: 16),
            Text(
              key == 'discount' ? '−$amount' : amount,
              style: style?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.end,
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${DiscountStrings.text('code')}: '),
                    TextSpan(
                      text: '${discount['code']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              amountRow('base'),
              amountRow('discount'),
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Divider(height: 1),
              ),
              amountRow('net', total: true),
            ],
          ),
        ),
      ),
    );
  }
}

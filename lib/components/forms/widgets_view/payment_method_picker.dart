import 'package:flutter/material.dart';
import 'package:festapp_core/forms.dart';
import '../payment_method_strings.dart';

class PaymentMethodPicker extends StatelessWidget {
  const PaymentMethodPicker(
      {super.key,
      required this.options,
      required this.surface,
      required this.selected,
      required this.onChanged});
  final FormPaymentOptions options;
  final String surface;
  final String? selected;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final methods = options.availableFor(surface);
    if (methods.length == 1 && methods.single == 'bank') {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(PaymentMethodStrings.text('title'),
          style: Theme.of(context).textTheme.titleMedium),
      if (methods.length > 1)
        for (final method in methods)
          RadioListTile<String>(
            value: method,
            groupValue: selected,
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
            title: Text(PaymentMethodStrings.text(method)),
            contentPadding: EdgeInsets.zero,
          )
      else if (methods.length == 1)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(PaymentMethodStrings.text(methods.single))),
      if (selected == 'stripe') ...[
        if (options.recipientName?.isNotEmpty == true)
          Text(PaymentMethodStrings.recipient(options.recipientName!)),
        Text(PaymentMethodStrings.text('fullAmount')),
        Text(PaymentMethodStrings.reservation(options.reservationSeconds)),
        Text(PaymentMethodStrings.text('stripeHint')),
      ],
      if (options.stripeConfigured && !methods.contains('stripe'))
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                PaymentMethodStrings.reason(options.stripeReasonFor(surface)))),
      if (methods.isEmpty)
        Semantics(
            liveRegion: true,
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(PaymentMethodStrings.text('unavailable')))),
    ]);
  }
}

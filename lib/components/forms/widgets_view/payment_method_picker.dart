import 'package:festapp_core/payments.dart';
import 'package:material_ui/material_ui.dart';
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
    final implicitBank = methods.length == 1 && methods.single == 'bank';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!implicitBank)
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
            title: Text(PaymentMethodStrings.text(paymentConnectors.get(method)?.labelKey ?? method)),
            contentPadding: EdgeInsets.zero,
          )
      else if (methods.length == 1 && !implicitBank)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(PaymentMethodStrings.text(paymentConnectors.get(methods.single)?.labelKey ?? methods.single))),
      if (selected == 'cash') Text(options.cashInstructions.isEmpty ? PaymentMethodStrings.text('cashInstructionsDefault') : options.cashInstructions),
      if (paymentConnectors.containsHosted(selected)) ...[
        if (options.providers[selected]?.recipientName?.isNotEmpty == true)
          Text(PaymentMethodStrings.recipient(options.providers[selected]!.recipientName!)),
        Text(PaymentMethodStrings.text('fullAmount')),
        Text(PaymentMethodStrings.reservation(options.reservationSeconds)),
        Text(PaymentMethodStrings.text(paymentConnectors.get(selected)!.hintKey)),
      ],
      if (options.cardConfigured && !methods.any(paymentConnectors.containsHosted))
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                PaymentMethodStrings.reason(options.cardReasonFor(surface)))),
      if (methods.isEmpty)
        Semantics(
            liveRegion: true,
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(PaymentMethodStrings.text('unavailable')))),
    ]);
  }
}

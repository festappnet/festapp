import 'package:flutter/material.dart';
import 'package:fstapp/components/forms/payment_method_strings.dart';

/// The form's saved payment policy, independent of temporary availability.
enum FormPaymentMethod { bank, stripe, both }

class PaymentMethodCards extends StatelessWidget {
  const PaymentMethodCards({
    super.key,
    required this.value,
    required this.canSelectStripe,
    required this.onChanged,
    this.stripeFirst = false,
  });

  final bool stripeFirst;
  final FormPaymentMethod? value;
  final bool canSelectStripe;
  final ValueChanged<FormPaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        // Stack early when enlarged text needs more room.
        final columns =
            size.maxWidth >= 600 * MediaQuery.textScalerOf(context).scale(1)
                ? 3
                : 1;
        final width = (size.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final method in (stripeFirst
              ? const [
                  FormPaymentMethod.stripe,
                  FormPaymentMethod.bank,
                  FormPaymentMethod.both
                ]
              : FormPaymentMethod.values))
            SizedBox(width: width, child: _card(context, method)),
        ]);
      });

  Widget _card(BuildContext context, FormPaymentMethod method) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = value == method;
    final enabled = method == FormPaymentMethod.bank || canSelectStripe;
    final title = PaymentMethodStrings.text(switch (method) {
      FormPaymentMethod.bank => 'onlyBank',
      FormPaymentMethod.stripe => 'onlyStripe',
      FormPaymentMethod.both => 'bothMethods',
    });
    final description = PaymentMethodStrings.text(switch (method) {
      FormPaymentMethod.bank => 'bankDescription',
      FormPaymentMethod.stripe => 'stripeDescription',
      FormPaymentMethod.both => 'bothDescription',
    });
    final radius = BorderRadius.circular(8);
    return Semantics(
      container: true,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
      label: '$title. $description',
      onTap: enabled ? () => onChanged(method) : null,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? colors.primaryContainer : colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: selected ? colors.primary : colors.outline,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('payment-method-${method.name}'),
            borderRadius: radius,
            onTap: enabled ? () => onChanged(method) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                        switch (method) {
                          FormPaymentMethod.bank =>
                            Icons.account_balance_outlined,
                          FormPaymentMethod.stripe =>
                            Icons.credit_card_outlined,
                          FormPaymentMethod.both => Icons.payments_outlined,
                        },
                        color: selected
                            ? colors.onPrimaryContainer
                            : enabled
                                ? colors.onSurface
                                : colors.onSurfaceVariant),
                    const Spacer(),
                    Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: selected ? colors.primary : colors.outline),
                  ]),
                  const SizedBox(height: 12),
                  Text(title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: selected
                            ? colors.onPrimaryContainer
                            : enabled
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 4),
                  Text(description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                      )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

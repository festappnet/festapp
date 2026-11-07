import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/forms/payment_method_strings.dart';

/// The form's saved payment policy, independent of temporary availability.
enum FormPaymentMethod { bank, online, both, cash }

class PaymentMethodCards extends StatelessWidget {
  const PaymentMethodCards({
    super.key,
    required this.value,
    required this.canSelectOnline,
    required this.onChanged,
    this.onlineFirst = false,
    this.showOnline = true,
    this.onlineTitle,
  });

  final bool onlineFirst;
  final bool showOnline;
  final String? onlineTitle;
  final FormPaymentMethod? value;
  final bool canSelectOnline;
  final ValueChanged<FormPaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      // Each row shares its natural height, including wrapped translations.
      final columns =
          size.maxWidth >= 600 * MediaQuery.textScalerOf(context).scale(1)
          ? 2
          : 1;
      final methods = [
        for (final method
            in (onlineFirst
                ? const [
                    FormPaymentMethod.online,
                    FormPaymentMethod.bank,
                    FormPaymentMethod.both,
                    FormPaymentMethod.cash,
                  ]
                : FormPaymentMethod.values))
          if (showOnline ||
              method == FormPaymentMethod.bank ||
              method == FormPaymentMethod.cash)
            method,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var start = 0; start < methods.length; start += columns) ...[
            if (start > 0) const SizedBox(height: 12),
            if (columns == 1)
              _card(context, methods[start])
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var offset = 0; offset < columns; offset++) ...[
                      if (offset > 0) const SizedBox(width: 12),
                      Expanded(
                        child: start + offset < methods.length
                            ? _card(context, methods[start + offset])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ],
      );
    },
  );

  Widget _card(BuildContext context, FormPaymentMethod method) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = value == method;
    final enabled =
        method == FormPaymentMethod.cash ||
        method == FormPaymentMethod.bank ||
        canSelectOnline;
    final title = method == FormPaymentMethod.online && onlineTitle != null
        ? onlineTitle!
        : PaymentMethodStrings.text(switch (method) {
            FormPaymentMethod.cash => 'cash',
            FormPaymentMethod.bank => 'onlyBank',
            FormPaymentMethod.online => 'onlyStripe',
            FormPaymentMethod.both => 'bothMethods',
          });
    final description = PaymentMethodStrings.text(switch (method) {
      FormPaymentMethod.cash => 'cashDescription',
      FormPaymentMethod.bank => 'bankDescription',
      FormPaymentMethod.online => 'stripeDescription',
      FormPaymentMethod.both => 'bothDescription',
    });
    final radius = BorderRadius.circular(12);
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
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        switch (method) {
                          FormPaymentMethod.cash => Icons.payments_outlined,
                          FormPaymentMethod.bank =>
                            Icons.account_balance_outlined,
                          FormPaymentMethod.online =>
                            Icons.credit_card_outlined,
                          FormPaymentMethod.both => Icons.payments_outlined,
                        },
                        color: selected
                            ? colors.onPrimaryContainer
                            : enabled
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                      ),
                      const Spacer(),
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: selected ? colors.primary : colors.outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: selected
                          ? colors.onPrimaryContainer
                          : enabled
                          ? colors.onSurface
                          : colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

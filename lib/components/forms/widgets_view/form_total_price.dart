import 'package:festapp_core/forms.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/utilities_all.dart';

/// The floating quote follows the same currency precision as the review.
/// Temporary card unavailability does not change configured price precision.
class FormTotalPrice extends StatelessWidget {
  const FormTotalPrice(
      {super.key,
      required this.amount,
      this.currencyCode,
      this.payments,
      this.style});
  final double amount;
  final String? currencyCode;
  final Map<String, dynamic>? payments;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
        Utilities.formatPrice(context, amount,
            currencyCode: currencyCode,
            decimalDigits:
                FormPaymentOptions.fromJson(payments).stripeConfigured
                    ? null
                    : 0),
        style: style,
      );
}

import 'package:material_ui/material_ui.dart';
import '../form_strings.dart';

class PaymentQrEmailSetting extends StatelessWidget {
  const PaymentQrEmailSetting({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    value: value,
    onChanged: onChanged,
    title: Text(FormStrings.labelPaymentQrInEmail),
    subtitle: Text(FormStrings.helperPaymentQrInEmail),
  );
}

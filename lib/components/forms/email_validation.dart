import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

/// Flutter adapter for the shared contact-address rules.
class EmailValidation {
  static String? Function(String?) validator({
    String? errorText,
    bool checkNullOrEmpty = true,
  }) => (value) {
    if (!checkNullOrEmpty && (value == null || value.isEmpty)) return null;
    return EmailAddress.isValid(value) ? null : errorText ?? CommonStrings.invalidFormat;
  };
}

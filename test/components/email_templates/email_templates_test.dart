import 'package:flutter_test/flutter_test.dart';

import 'email_template_dialog_cases.dart' as email_template_dialog;
import 'email_template_model_cases.dart' as email_template_model;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('email_template_dialog', email_template_dialog.main);
  group('email_template_model', email_template_model.main);
}

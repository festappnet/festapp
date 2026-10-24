import 'package:flutter_test/flutter_test.dart';
import 'reception_gating_cases.dart' as suite0;
import 'manual_login_code_field_cases.dart' as suite1;
import 'login_qr_transition_cases.dart' as suite2;

// Standard binding, default locale; scoped resources stay with their source.
void main() {
  group('reception_gating', suite0.main);
  group('manual_login_code_field', suite1.main);
  group('login_qr_transition', suite2.main);
}

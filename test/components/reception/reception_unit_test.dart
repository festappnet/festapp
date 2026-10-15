import 'package:flutter_test/flutter_test.dart';

import 'login_qr_payload_cases.dart' as suite0;
import 'reception_command_error_cases.dart' as suite1;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('login_qr_payload', suite0.main);
  group('reception_command_error', suite1.main);
}

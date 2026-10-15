import 'package:flutter_test/flutter_test.dart';

import 'account_deletion_service_cases.dart' as suite0;
import 'admin_companion_relationships_cases.dart' as suite1;
import 'companion_commands_cases.dart' as suite2;
import 'companion_model_cases.dart' as suite3;
import 'companion_visibility_cases.dart' as suite4;
import 'login_feedback_cases.dart' as suite5;
import 'logout_flow_cases.dart' as suite6;
import 'occasion_editor_data_cases.dart' as suite7;
import 'password_change_flow_cases.dart' as suite8;
import 'password_reset_request_cases.dart' as suite9;
import 'profile_commands_cases.dart' as suite10;
import 'profile_load_recovery_cases.dart' as suite11;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('account_deletion_service', suite0.main);
  group('admin_companion_relationships', suite1.main);
  group('companion_commands', suite2.main);
  group('companion_model', suite3.main);
  group('companion_visibility', suite4.main);
  group('login_feedback', suite5.main);
  group('logout_flow', suite6.main);
  group('occasion_editor_data', suite7.main);
  group('password_change_flow', suite8.main);
  group('password_reset_request', suite9.main);
  group('profile_commands', suite10.main);
  group('profile_load_recovery', suite11.main);
}

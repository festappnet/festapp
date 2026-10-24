import 'package:flutter_test/flutter_test.dart';

import 'account_deletion_service_cases.dart' as suite0;
import 'admin_companion_relationships_cases.dart' as suite1;
import 'companion_commands_cases.dart' as suite2;
import 'companion_model_cases.dart' as suite3;
import 'occasion_editor_data_cases.dart' as suite7;
import 'profile_commands_cases.dart' as suite10;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('account_deletion_service', suite0.main);
  group('admin_companion_relationships', suite1.main);
  group('companion_commands', suite2.main);
  group('companion_model', suite3.main);
  group('occasion_editor_data', suite7.main);
  group('profile_commands', suite10.main);
}

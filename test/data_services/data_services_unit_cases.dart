import 'package:flutter_test/flutter_test.dart';

import 'app_config_rpc_cases.dart' as suite0;
import 'auth_refresh_recovery_cases.dart' as suite1;
import 'offline_data_service_cases.dart' as suite2;
import 'saved_program_pending_state_cases.dart' as suite3;
import 'update_service_cases.dart' as suite4;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('app_config_rpc', suite0.main);
  group('auth_refresh_recovery', suite1.main);
  group('offline_data_service', suite2.main);
  group('saved_program_pending_state', suite3.main);
  group('update_service', suite4.main);
}

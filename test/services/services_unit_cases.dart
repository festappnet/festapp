import 'package:flutter_test/flutter_test.dart';

import 'backend_activation_service_cases.dart' as suite0;
import 'installation_cutover_service_cases.dart' as suite1;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('backend_activation_service', suite0.main);
  group('installation_cutover_service', suite1.main);
}

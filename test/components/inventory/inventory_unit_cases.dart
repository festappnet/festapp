import 'package:flutter_test/flutter_test.dart';

import 'inventory_resource_commands_cases.dart' as suite0;
import 'spot_commands_cases.dart' as suite1;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('inventory_resource_commands', suite0.main);
  group('spot_commands', suite1.main);
}

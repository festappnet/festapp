import 'package:flutter_test/flutter_test.dart';

import 'information_commands_cases.dart' as suite0;
import 'information_expansion_state_cases.dart' as suite1;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('information_commands', suite0.main);
  group('information_expansion_state', suite1.main);
}

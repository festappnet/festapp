import 'package:flutter_test/flutter_test.dart';

import 'cleaning_commands_cases.dart' as suite0;
import 'cleaning_offline_banner_cases.dart' as suite1;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('cleaning_commands', suite0.main);
  group('cleaning_offline_banner', suite1.main);
}

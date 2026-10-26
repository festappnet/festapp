import 'package:flutter_test/flutter_test.dart';

import 'platform_route_parser_cases.dart' as suite0;
import 'tab_route_contract_cases.dart' as suite1;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('platform_route_parser', suite0.main);
  group('tab_route_contract', suite1.main);
}

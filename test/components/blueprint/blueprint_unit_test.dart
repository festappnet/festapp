import 'package:flutter_test/flutter_test.dart';

import 'blueprint_order_metadata_cases.dart' as suite0;
import 'blueprint_seat_adapter_cases.dart' as suite1;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('blueprint_order_metadata', suite0.main);
  group('blueprint_seat_adapter', suite1.main);
}

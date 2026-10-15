import 'package:flutter_test/flutter_test.dart';

import 'fio_fetch_time_cases.dart' as suite0;
import 'iban_utils_cases.dart' as suite1;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('fio_fetch_time', suite0.main);
  group('iban_utils', suite1.main);
}

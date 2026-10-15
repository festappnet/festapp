import 'package:flutter_test/flutter_test.dart';

import 'image_control_client_cases.dart' as suite0;
import 'image_url_helper_cases.dart' as suite1;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('image_control_client', suite0.main);
  group('image_url_helper', suite1.main);
}

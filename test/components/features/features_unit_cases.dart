import 'package:flutter_test/flutter_test.dart';

import 'companion_feature_cases.dart' as suite0;
import 'counseling_gating_cases.dart' as suite1;
import 'services_feature_cases.dart' as suite2;
import 'feature_settings_editor_cases.dart' as editors;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('settings_editor', editors.main);
  group('companion_feature', suite0.main);
  group('counseling_gating', suite1.main);
  group('services_feature', suite2.main);
}

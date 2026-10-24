import 'package:flutter_test/flutter_test.dart';

import 'offline_map_bundle_manager_cases.dart' as offline_map_bundle_manager;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('offline_map_bundle_manager', offline_map_bundle_manager.main);
}

import 'package:flutter_test/flutter_test.dart';
import 'offline_banner_layout_cases.dart' as suite0;
import 'offline_sync_timestamp_cases.dart' as suite1;

// Standard binding, default locale; scoped resources stay with their source.
void main() {
  group('offline_banner_layout', suite0.main);
  group('offline_sync_timestamp', suite1.main);
}

import 'client_command_replacements_cases.dart' as replacements;
import 'package:flutter_test/flutter_test.dart';

import 'client_command_transport_cases.dart' as suite1;
import 'client_sync_context_cases.dart' as suite2;
import 'client_sync_endpoint_service_cases.dart' as suite3;
import 'occasion_media_cache_cases.dart' as suite8;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('client_command_replacements', replacements.main);
  group('client_command_transport', suite1.main);
  group('client_sync_context', suite2.main);
  group('client_sync_endpoint_service', suite3.main);
  group('occasion_media_cache', suite8.main);
}

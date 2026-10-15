import 'package:flutter_test/flutter_test.dart';

import 'client_command_response_cases.dart' as suite0;
import 'client_command_transport_cases.dart' as suite1;
import 'client_sync_context_cases.dart' as suite2;
import 'client_sync_endpoint_service_cases.dart' as suite3;
import 'client_sync_projection_tracker_cases.dart' as suite4;
import 'client_sync_protocol_cases.dart' as suite5;
import 'client_sync_remote_cases.dart' as suite6;
import 'client_sync_store_cases.dart' as suite7;
import 'occasion_media_cache_cases.dart' as suite8;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('client_command_response', suite0.main);
  group('client_command_transport', suite1.main);
  group('client_sync_context', suite2.main);
  group('client_sync_endpoint_service', suite3.main);
  group('client_sync_projection_tracker', suite4.main);
  group('client_sync_protocol', suite5.main);
  group('client_sync_remote', suite6.main);
  group('client_sync_store', suite7.main);
  group('occasion_media_cache', suite8.main);
}

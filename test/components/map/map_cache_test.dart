import 'package:flutter_test/flutter_test.dart';

import 'offline_map_file_downloader_cases.dart' as offline_map_file_downloader;
import 'offline_map_bundle_manager_cases.dart' as offline_map_bundle_manager;
import 'offline_map_bundle_manifest_cases.dart' as offline_map_bundle_manifest;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('offline_map_file_downloader', offline_map_file_downloader.main);
  group('offline_map_bundle_manager', offline_map_bundle_manager.main);
  group('offline_map_bundle_manifest', offline_map_bundle_manifest.main);
}

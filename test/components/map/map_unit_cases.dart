import 'package:flutter_test/flutter_test.dart';

import 'external_map_navigation_cases.dart' as suite0;
import 'map_commands_cases.dart' as suite3;
import 'map_deep_link_route_identity_cases.dart' as suite4;
import 'map_path_direction_layout_cases.dart' as suite5;
import 'map_viewport_coordinator_cases.dart' as suite7;
import 'maplibre_place_icon_rasterizer_cases.dart' as suite8;
import 'maplibre_scene_controller_cases.dart' as suite9;
import 'offline_map_configuration_cases.dart' as suite12;
import 'place_type_column_builder_cases.dart' as suite13;
import 'public_map_session_cases.dart' as suite14;
import 'warm_map_lifecycle_cases.dart' as suite15;

import 'map_edge_indicator_layout_cases.dart' as map_edge_indicator_layout;
import 'map_locate_coordinator_cases.dart' as map_locate_coordinator;
import 'maplibre_focus_contract_cases.dart' as maplibre_focus_contract;
import 'maplibre_style_assembler_cases.dart' as maplibre_style_assembler;
import 'maplibre_style_image_pixel_ratio_cases.dart'
    as maplibre_style_image_pixel_ratio;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('external_map_navigation', suite0.main);
  group('map_commands', suite3.main);
  group('map_deep_link_route_identity', suite4.main);
  group('map_path_direction_layout', suite5.main);
  group('map_viewport_coordinator', suite7.main);
  group('maplibre_place_icon_rasterizer', suite8.main);
  group('maplibre_scene_controller', suite9.main);
  group('offline_map_configuration', suite12.main);
  group('place_type_column_builder', suite13.main);
  group('public_map_session', suite14.main);
  group('warm_map_lifecycle', suite15.main);
  group('map_edge_indicator_layout', map_edge_indicator_layout.main);
  group('map_locate_coordinator', map_locate_coordinator.main);
  group('maplibre_focus_contract', maplibre_focus_contract.main);
  group('maplibre_style_assembler', maplibre_style_assembler.main);
  group('maplibre_style_image_pixel_ratio',
      maplibre_style_image_pixel_ratio.main);
}

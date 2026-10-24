import 'package:flutter_test/flutter_test.dart';

import 'data_grid_action_confirmation_cases.dart'
    as data_grid_action_confirmation;
import 'data_grid_column_header_cases.dart' as data_grid_column_header;
import 'data_grid_dirty_actions_cases.dart' as data_grid_dirty_actions;
import 'data_grid_helper_cases.dart' as data_grid_helper;
import 'tab_refresh_cases.dart' as tab_refresh;
import 'versioned_admin_models_cases.dart' as versioned_admin_models;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('data_grid_action_confirmation', data_grid_action_confirmation.main);
  group('data_grid_column_header', data_grid_column_header.main);
  group('data_grid_dirty_actions', data_grid_dirty_actions.main);
  group('data_grid_helper', data_grid_helper.main);
  group('tab_refresh', tab_refresh.main);
  group('versioned_admin_models', versioned_admin_models.main);
}

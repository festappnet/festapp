import 'package:flutter_test/flutter_test.dart';

import 'group_commands_cases.dart' as suite0;
import 'user_groups_editor_data_cases.dart' as suite1;

import 'group_place_assignment_cases.dart' as group_place_assignment;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('group_commands', suite0.main);
  group('user_groups_editor_data', suite1.main);
  group('group_place_assignment', group_place_assignment.main);
}

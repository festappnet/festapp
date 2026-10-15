import 'package:flutter_test/flutter_test.dart';

import 'exclusive_group_commands_cases.dart' as suite2;
import 'saved_program_commands_cases.dart' as suite3;
import 'schedule_companion_loading_cases.dart' as suite5;

import 'event_page_theme_cases.dart' as event_page_theme;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('exclusive_group_commands', suite2.main);
  group('saved_program_commands', suite3.main);
  group('schedule_companion_loading', suite5.main);
  group('event_page_theme', event_page_theme.main);
}

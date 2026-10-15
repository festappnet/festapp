import 'package:flutter_test/flutter_test.dart';

import 'event_participants_access_cases.dart' as suite0;
import 'event_registration_state_cases.dart' as suite1;
import 'exclusive_group_commands_cases.dart' as suite2;
import 'saved_program_commands_cases.dart' as suite3;
import 'saved_program_mutation_coordinator_cases.dart' as suite4;
import 'schedule_companion_loading_cases.dart' as suite5;
import 'schedule_reload_coordinator_cases.dart' as suite6;
import 'suspicious_event_detector_cases.dart' as suite7;

import 'event_page_theme_cases.dart' as event_page_theme;
import 'event_model_duration_cases.dart' as event_model_duration;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('event_participants_access', suite0.main);
  group('event_registration_state', suite1.main);
  group('exclusive_group_commands', suite2.main);
  group('saved_program_commands', suite3.main);
  group('saved_program_mutation_coordinator', suite4.main);
  group('schedule_companion_loading', suite5.main);
  group('schedule_reload_coordinator', suite6.main);
  group('suspicious_event_detector', suite7.main);
  group('event_page_theme', event_page_theme.main);
  group('event_model_duration', event_model_duration.main);
}

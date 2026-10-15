import 'package:flutter_test/flutter_test.dart';
import 'event_grid_record_cases.dart' as suite0;
import 'event_metadata_item_cases.dart' as suite1;
import 'saved_program_ui_cases.dart' as suite2;
import 'program_notification_settings_cases.dart' as suite3;

// Standard binding, default locale; scoped resources stay with their source.
void main() {
  group('event_grid_record', suite0.main);
  group('event_metadata_item', suite1.main);
  group('saved_program_ui', suite2.main);
  group('program_notification_settings', suite3.main);
}

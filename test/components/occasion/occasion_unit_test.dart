import 'package:flutter_test/flutter_test.dart';

import 'news_badge_controller_cases.dart' as suite0;
import 'occasion_save_state_cases.dart' as suite1;

import 'occasion_commands_cases.dart' as occasion_commands;
import 'occasion_media_copier_cases.dart' as occasion_media_copier;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('news_badge_controller', suite0.main);
  group('occasion_save_state', suite1.main);
  group('occasion_commands', occasion_commands.main);
  group('occasion_media_copier', occasion_media_copier.main);
}

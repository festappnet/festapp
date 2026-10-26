import 'package:flutter_test/flutter_test.dart';

import 'db_speakers_compatibility_cases.dart' as suite0;
import 'speaker_commands_cases.dart' as suite1;
import 'speakers_mapping_cases.dart' as suite2;

// Keep these suites in one engine; each group owns its test hooks.
// Widget and platform-global tests stay in separate *_test.dart files.
void main() {
  group('db_speakers_compatibility', suite0.main);
  group('speaker_commands', suite1.main);
  group('speakers_mapping', suite2.main);
}

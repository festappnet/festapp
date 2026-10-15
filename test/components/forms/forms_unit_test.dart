import 'package:flutter_test/flutter_test.dart';

import 'default_value_helper_cases.dart' as suite0;
import 'default_values_cases.dart' as suite1;
import 'form_commands_cases.dart' as suite2;
import 'form_metadata_cases.dart' as suite3;
import 'occasion_setup_defaults_cases.dart' as suite4;

import 'form_html_content_cases.dart' as form_html_content;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('default_value_helper', suite0.main);
  group('default_values', suite1.main);
  group('form_commands', suite2.main);
  group('form_metadata', suite3.main);
  group('occasion_setup_defaults', suite4.main);
  group('form_html_content', form_html_content.main);
}

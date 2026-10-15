import 'package:flutter_test/flutter_test.dart';

import 'form_deletion_cases.dart' as form_deletion;
import 'form_editor_answer_preview_cases.dart' as form_editor_answer_preview;

// These suites use fallback strings; localized editor suites run separately.
void main() {
  group('form_deletion', form_deletion.main);
  group('form_editor_answer_preview', form_editor_answer_preview.main);
}

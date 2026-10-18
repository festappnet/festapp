import 'package:flutter_test/flutter_test.dart';

import 'template_authoring_cases.dart' as template_authoring;
import 'html_clipboard_cases.dart' as html_clipboard;
import 'html_editor_document_cases.dart' as html_editor_document;
import 'html_media_service_cases.dart' as html_media_service;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('template_authoring', template_authoring.main);
  group('html_clipboard', html_clipboard.main);
  group('html_editor_document', html_editor_document.main);
  group('html_media_service', html_media_service.main);
}

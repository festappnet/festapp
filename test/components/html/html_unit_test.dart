import 'package:flutter_test/flutter_test.dart';

import 'html_clipboard_cases.dart' as html_clipboard;
import 'html_contact_links_cases.dart' as html_contact_links;
import 'html_document_codec_cases.dart' as html_document_codec;
import 'html_editor_document_cases.dart' as html_editor_document;
import 'html_media_service_cases.dart' as html_media_service;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('html_clipboard', html_clipboard.main);
  group('html_contact_links', html_contact_links.main);
  group('html_document_codec', html_document_codec.main);
  group('html_editor_document', html_editor_document.main);
  group('html_media_service', html_media_service.main);
}

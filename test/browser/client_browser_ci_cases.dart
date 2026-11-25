@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import '../components/html/html_image_preview_cases.dart' as preview;
import '../components/navigation/platform_route_parser_cases.dart' as routing;
import 'account_webauthn_browser_cases.dart' as webauthn;
import 'browser_preference_store_test.dart' as preferences;
import 'ticket_wallet_upload_browser_cases.dart' as wallet;

void main() {
  group('routing', routing.main);
  group('preferences', preferences.main);
  group('preview', preview.main);
  group('webauthn', webauthn.main);
  group('wallet', wallet.main);
}

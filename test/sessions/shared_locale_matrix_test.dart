import '../support/register_client_suites.dart';
import 'czech_key_fallback_cases.dart' as suite0;
import '../components/users/google_login_panel_cases.dart' as suite1;

void main() {
  registerClientSuites({
    'czech_key_fallback': suite0.main,
    'google_login_panel': suite1.main,
  });
}

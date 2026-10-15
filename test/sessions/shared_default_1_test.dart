import '../support/register_client_suites.dart';
import 'default_locale_1_cases.dart' as suite0;
import '../widgets/widgets_cases.dart' as suite1;
import 'visual_primitives_cases.dart' as suite2;
import '../services/auth_session_storage_cases.dart' as suite3;

void main() {
  registerClientSuites({
    'default_locale_1': suite0.main,
    'widgets': suite1.main,
    'visual_primitives': suite2.main,
    'auth_session_storage': suite3.main,
  });
}

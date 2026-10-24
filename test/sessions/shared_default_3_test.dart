import '../support/register_client_suites.dart';
import 'default_locale_4_cases.dart' as suite0;
import 'default_locale_5_cases.dart' as suite1;

void main() {
  registerClientSuites({
    'default_locale_4': suite0.main,
    'default_locale_5': suite1.main,
  });
}

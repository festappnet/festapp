import '../support/register_client_suites.dart';
import 'default_locale_3_cases.dart' as suite0;
import 'default_locale_2_cases.dart' as suite1;

void main() {
  registerClientSuites({
    'default_locale_3': suite0.main,
    'default_locale_2': suite1.main,
  });
}

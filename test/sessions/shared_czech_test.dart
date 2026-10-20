import '../support/register_client_suites.dart';
import 'czech_catalog_3_cases.dart' as suite0;
import 'czech_catalog_2_cases.dart' as suite1;
import 'czech_catalog_1_cases.dart' as suite2;

void main() {
  registerClientSuites({
    'czech_catalog_3': suite0.main,
    'czech_catalog_2': suite1.main,
    'czech_catalog_1': suite2.main,
  });
}

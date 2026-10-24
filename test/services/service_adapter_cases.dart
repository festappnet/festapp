import '../support/register_client_suites.dart';
import 'services_unit_cases.dart' as suite0;
import 'connectivity_service_cases.dart' as suite1;
import 'notification_helper_cases.dart' as suite2;
import 'storage_helper_cases.dart' as suite3;

void main() {
  registerClientSuites({
    'services_unit': suite0.main,
    'connectivity_service': suite1.main,
    'notification_helper': suite2.main,
    'storage_helper': suite3.main,
  });
}

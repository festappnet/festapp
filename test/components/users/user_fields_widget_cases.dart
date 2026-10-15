import '../../support/register_client_suites.dart';
import 'occasion_user_grid_cases.dart' as suite0;
import 'import_helper_cases.dart' as suite1;
import 'companion_accommodation_field_cases.dart' as suite2;
import 'users_unit_cases.dart' as suite3;

void main() {
  registerClientSuites({
    'occasion_user_grid': suite0.main,
    'import_helper': suite1.main,
    'companion_accommodation_field': suite2.main,
    'users_unit': suite3.main,
  });
}

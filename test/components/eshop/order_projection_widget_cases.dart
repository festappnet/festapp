import '../../support/register_client_suites.dart';
import 'models/order_email_cell_cases.dart' as suite0;
import 'eshop_unit_cases.dart' as suite1;
import '../inventory/inventory_unit_cases.dart' as suite2;
import '../scan/scan_field_mappings_cases.dart' as suite3;
import '../reception/reception_unit_cases.dart' as suite4;

void main() {
  registerClientSuites({
    'order_email_cell': suite0.main,
    'eshop_unit': suite1.main,
    'inventory_unit': suite2.main,
    'scan_field_mappings': suite3.main,
    'reception_unit': suite4.main,
  });
}

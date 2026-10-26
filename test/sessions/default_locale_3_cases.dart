import '../support/register_client_suites.dart';
import '../components/map/map_surface_widget_cases.dart' as suite0;
import '../components/forms/forms_contract_widget_cases.dart' as suite1;
import '../components/email_delivery/email_delivery_widget_cases.dart'
    as suite2;
import '../components/forms/forms_field_widget_cases.dart' as suite3;
import '../components/eshop/views/add_cash_payment_dialog_cases.dart' as suite4;
import '../components/users/companion_admin_dialog_cases.dart' as suite5;
import '../components/ticket_layout/ticket_canvas_selection_cases.dart'
    as suite6;
import '../components/occasion/occasion_home_navigation_contract_cases.dart'
    as suite7;
import '../components/navigation/navigation_unit_cases.dart' as suite8;
import '../components/blueprint/blueprint_unit_cases.dart' as suite9;

void main() {
  registerClientSuites({
    'map_surface_widget': suite0.main,
    'forms_contract_widget': suite1.main,
    'email_delivery_widget': suite2.main,
    'forms_field_widget': suite3.main,
    'add_cash_payment_dialog': suite4.main,
    'companion_admin_dialog': suite5.main,
    'ticket_canvas_selection': suite6.main,
    'occasion_home_navigation_contract': suite7.main,
    'navigation_unit': suite8.main,
    'blueprint_unit': suite9.main,
  });
}

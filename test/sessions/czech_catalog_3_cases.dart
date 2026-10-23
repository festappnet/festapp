import '../support/register_client_suites.dart';
import '../components/eshop/occasion_report_cases.dart' as suite0;
import '../components/eshop/product_price_scheduling_cases.dart' as suite1;
import '../components/navigation/object_route_dirty_dialog_cases.dart'
    as suite2;
import '../components/eshop/ticket_usage_action_cases.dart' as suite3;
import '../components/eshop/order_update_email_dialog_cases.dart' as suite5;
import '../components/inventory/inventory_pool_card_cases.dart' as suite6;

void main() {
  registerClientSuites({
    'occasion_report': suite0.main,
    'product_price_scheduling': suite1.main,
    'object_route_dirty_dialog': suite2.main,
    'ticket_usage_action': suite3.main,
    'order_update_email_dialog': suite5.main,
    'inventory_pool_card': suite6.main,
  });
}

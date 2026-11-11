import '../support/register_client_suites.dart';
import '../components/email_delivery/email_delivery_legend_timeline_cases.dart' as suite0;
import '../components/eshop/order_customer_payment_details_cases.dart' as suite1;
import '../components/eshop/order_email_repair_design_cases.dart' as suite2;
import '../components/eshop/order_places_overview_cases.dart' as suite3;
import '../components/eshop/ticket_batch_detail_header_cases.dart' as suite4;

void main() {
  registerClientSuites({
    'email_delivery_legend_timeline': suite0.main,
    'order_customer_payment_details': suite1.main,
    'order_email_repair_design': suite2.main,
    'order_places_overview': suite3.main,
    'ticket_batch_detail_header': suite4.main,
  });
}

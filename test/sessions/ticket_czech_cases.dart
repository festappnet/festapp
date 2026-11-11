import '../support/register_client_suites.dart';
import '../components/notification_center/notification_center_time_cases.dart'
    as suite0;
import '../components/forms/public_link_settings_cases.dart' as suite1;
import '../components/forms/form_payment_defaults_cases.dart' as suite2;
import '../components/occasion/occasion_setup_ticket_gallery_cases.dart'
    as suite3;
import '../components/eshop/order_payment_summary_cases.dart' as suite4;
import '../components/stripe_payments/form_payment_settings_cases.dart'
    as suite5;

void main() {
  registerClientSuites({
    'notification_center_time': suite0.main,
    'public_link_settings': suite1.main,
    'form_payment_defaults': suite2.main,
    'occasion_setup_ticket_gallery': suite3.main,
    'order_payment_summary': suite4.main,
    'form_payment_settings': suite5.main,
  });
}

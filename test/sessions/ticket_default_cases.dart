import '../support/register_client_suites.dart';
import '../components/notification_center/notification_center_cases.dart'
    as suite0;
import '../components/notification_center/notification_center_prepared_cases.dart'
    as suite1;
import '../components/forms/form_appearance_theme_cases.dart' as suite2;
import '../components/occasion/occasion_setup_appearance_cases.dart' as suite3;
import '../components/occasion/occasion_setup_ticket_loading_cases.dart'
    as suite4;
import '../components/eshop/views/add_cash_payment_dialog_cases.dart' as suite5;

void main() {
  registerClientSuites({
    'notification_center': suite0.main,
    'notification_center_prepared': suite1.main,
    'form_appearance_theme': suite2.main,
    'occasion_setup_appearance': suite3.main,
    'occasion_setup_ticket_loading': suite4.main,
    'add_cash_payment_dialog': suite5.main,
  });
}

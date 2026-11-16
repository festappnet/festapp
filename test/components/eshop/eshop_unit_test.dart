import '../../support/register_client_suites.dart';
import 'order_blueprint_cache_cases.dart' as suite0;
import 'order_detail_save_changes_cases.dart' as suite1;
import 'order_email_repair_dialog_cases.dart' as suite2;
import 'order_detail_scroll_storage_cases.dart' as suite3;
import 'ticket_batch_commands_cases.dart' as suite4;
import 'payment_policy_cases.dart' as suite5;

void main() {
  registerClientSuites({
    'order_blueprint_cache': suite0.main,
    'order_detail_save_changes': suite1.main,
    'order_email_repair_dialog': suite2.main,
    'order_detail_scroll_storage': suite3.main,
    'ticket_batch_commands': suite4.main,
    'payment_policy': suite5.main,
  });
}

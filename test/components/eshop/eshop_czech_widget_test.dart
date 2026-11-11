import '../../support/register_client_suites.dart';
import 'order_payment_summary_cases.dart' as suite0;
import 'order_history_seat_labels_cases.dart' as suite1;
import 'ticket_batch_navigation_cases.dart' as suite2;

void main() {
  registerClientSuites({
    'order_payment_summary': suite0.main,
    'order_history_seat_labels': suite1.main,
    'ticket_batch_navigation': suite2.main,
  });
}

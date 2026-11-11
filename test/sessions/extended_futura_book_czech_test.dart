import '../support/register_client_suites.dart';
import '../components/occasion/occasion_setup_feedback_cases.dart' as suite0;
import '../components/occasion/occasion_setup_preview_performance_cases.dart' as suite1;
import '../components/occasion/ticket_email_delivery_cases.dart' as suite2;

void main() {
  registerClientSuites({
    'occasion_setup_feedback': suite0.main,
    'occasion_setup_preview_performance': suite1.main,
    'ticket_email_delivery': suite2.main,
  });
}

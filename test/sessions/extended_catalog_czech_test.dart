import '../support/register_client_suites.dart';
import '../components/occasion/occasion_setup_ticket_gallery_cases.dart' as suite0;
import '../components/occasion/occasion_setup_ticket_matrix_cases.dart' as suite1;

void main() {
  registerClientSuites({
    'occasion_setup_ticket_gallery': suite0.main,
    'occasion_setup_ticket_matrix': suite1.main,
  });
}

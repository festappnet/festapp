import '../support/register_client_suites.dart';
import '../components/schedule/light_timeline_initial_day_cases.dart' as suite0;
import '../components/schedule/schedule_initial_day_cases.dart' as suite1;

void main() {
  registerClientSuites({
    'light_timeline_initial_day': suite0.main,
    'schedule_initial_day': suite1.main,
  });
}

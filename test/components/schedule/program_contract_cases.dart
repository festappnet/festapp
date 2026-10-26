import '../../support/register_client_suites.dart';
import 'schedule_unit_cases.dart' as suite0;
import 'event_model_client_sync_cases.dart' as suite1;
import '../timeline/advanced_timeline_day_list_cases.dart' as suite2;
import '../features/features_unit_cases.dart' as suite3;

void main() {
  registerClientSuites({
    'schedule_unit': suite0.main,
    'event_model_client_sync': suite1.main,
    'advanced_timeline_day_list': suite2.main,
    'features_unit': suite3.main,
  });
}

import '../../support/register_client_suites.dart';
import 'cleaning_unit_cases.dart' as suite0;
import 'cleaning_gating_cases.dart' as suite1;
import '../information/information_unit_cases.dart' as suite2;
import '../news/news_unit_cases.dart' as suite3;

void main() {
  registerClientSuites({
    'cleaning_unit': suite0.main,
    'cleaning_gating': suite1.main,
    'information_unit': suite2.main,
    'news_unit': suite3.main,
  });
}

// Compatible CI roots only. SDK, font and fallback scopes stay separate.
import '../../test/support/register_client_suites.dart';
import '../../test/components/schedule/schedule_initial_day_cases.dart'
    as suite0;
import '../../test/components/eshop/order_detail_save_changes_cases.dart'
    as suite1;
import '../../test/components/eshop/order_detail_answers_cases.dart'
    as suite2;
import '../../test/components/eshop/order_commands_cases.dart'
    as suite3;

void main() {
  registerClientSuites({
    'schedule_initial_day_cases': suite0.main,
    'order_detail_save_changes_cases': suite1.main,
    'order_detail_answers_cases': suite2.main,
    'order_commands_cases': suite3.main,
  }, orderVariable: 'FESTAPP_CI_GROUP_ORDER');
}

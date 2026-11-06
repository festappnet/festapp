import '../support/register_client_suites.dart';
import '../components/eshop/order_detail_viewer_cases.dart' as suite0;
import '../components/occasion/occasion_setup_story_shell_cases.dart' as suite1;

void main() {
  registerClientSuites({
    'order_detail_viewer': suite0.main,
    'occasion_setup_story_shell': suite1.main,
  });
}

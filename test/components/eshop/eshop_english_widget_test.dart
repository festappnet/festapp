import '../../support/register_client_suites.dart';
import 'async_download_button_cases.dart' as suite0;
import 'order_detail_answers_cases.dart' as suite1;

void main() {
  registerClientSuites({
    'async_download_button': suite0.main,
    'order_detail_answers': suite1.main,
  });
}

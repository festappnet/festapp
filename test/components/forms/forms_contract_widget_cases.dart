import '../../support/register_client_suites.dart';
import 'forms_unit_cases.dart' as suite0;
import 'forms_order_widget_cases.dart' as suite1;
import '../html/html_unit_cases.dart' as suite2;
import '../email_templates/email_templates_cases.dart' as suite3;

void main() {
  registerClientSuites({
    'forms_unit': suite0.main,
    'forms_order_widget': suite1.main,
    'html_unit': suite2.main,
    'email_templates': suite3.main,
  });
}

import '../support/register_client_suites.dart';
import '../components/forms/forms_editor_widget_cases.dart' as suite0;
import '../components/navigation/save_and_single_form_navigation_cases.dart'
    as suite1;
import '../components/forms/public_link_settings_cases.dart' as suite3;
import '../components/fonts/form_design_font_loading_cases.dart' as suite4;
import '../components/eshop/cancelled_order_read_only_cases.dart' as suite5;

void main() {
  registerClientSuites({
    'forms_editor_widget': suite0.main,
    'save_and_single_form_navigation': suite1.main,
    'public_link_settings': suite3.main,
    'form_design_font_loading': suite4.main,
    'cancelled_order_read_only': suite5.main,
  });
}

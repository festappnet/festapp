import '../support/register_client_suites.dart';
import '../components/forms/form_design_compatibility_cases.dart' as suite0;
import '../components/occasion/occasion_setup_appearance_panel_cases.dart'
    as suite1;

void main() {
  registerClientSuites({
    'form_design_compatibility': suite0.main,
    'occasion_setup_appearance_panel': suite1.main,
  });
}

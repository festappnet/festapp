import '../support/register_client_suites.dart';
import 'app_management/pwa_storage_advanced_settings_cases.dart' as suite1;
import 'client_changes/client_changes_tab_cases.dart' as suite2;
import 'occasion/material_3_chrome_compatibility_cases.dart' as suite4;

void main() {
  registerClientSuites({
    'pwa_storage_advanced_settings': suite1.main,
    'client_changes_tab': suite2.main,
    'material_3_chrome_compatibility': suite4.main,
  });
}

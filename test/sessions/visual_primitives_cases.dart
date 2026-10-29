import '../widgets/brand_loading_indicator_cases.dart' as brand_loading;
import '../support/register_client_suites.dart';
import '../theme_config_cases.dart' as suite0;
import '../components/shared/editor_action_bar_cases.dart' as suite1;
import '../components/breadcrumb_row_cases.dart' as suite2;
import '../services/dialog_helper_progress_cases.dart' as suite3;

void main() {
  registerClientSuites({
    'brand_loading': brand_loading.main,
    'theme_config': suite0.main,
    'editor_action_bar': suite1.main,
    'breadcrumb_row': suite2.main,
    'dialog_helper_progress': suite3.main,
  });
}

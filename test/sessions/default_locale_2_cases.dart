import '../support/register_client_suites.dart';
import '../components/single_data_grid/single_data_grid_widget_cases.dart'
    as suite0;
import '../components/speakers/speaker_widget_cases.dart' as suite1;
import '../components/app_shell_widget_cases.dart' as suite2;
import '../components/search/global_search_dialog_cases.dart' as suite3;
import '../components/shared/copy_button_cases.dart' as suite4;
import '../startup/startup_widget_cases.dart' as suite5;
import '../components/html/html_view_cases.dart' as suite6;
import '../components/occasion/occasion_unit_cases.dart' as suite7;
import '../data_services/data_services_unit_cases.dart' as suite8;

void main() {
  registerClientSuites({
    'single_data_grid_widget': suite0.main,
    'speaker_widget': suite1.main,
    'app_shell_widget': suite2.main,
    'global_search_dialog': suite3.main,
    'copy_button': suite4.main,
    'startup_widget': suite5.main,
    'html_view': suite6.main,
    'occasion_unit': suite7.main,
    'data_services_unit': suite8.main,
  });
}

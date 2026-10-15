import '../support/register_client_suites.dart';
import '../components/eshop/order_grid_filters_cases.dart' as suite0;
import '../components/news/news_presentation_widget_cases.dart' as suite1;
import '../components/occasion/occasion_navigation_bar_cases.dart' as suite2;
import '../components/map/map_presentation_widget_cases.dart' as suite3;
import '../components/icons/upload_icon_dialog_cases.dart' as suite4;
import '../components/bank_accounts/nested_dialog_cases.dart' as suite5;
import '../components/eshop/order_projection_widget_cases.dart' as suite6;
import '../components/offline/offline_presentation_widget_cases.dart' as suite7;
import '../components/schedule/program_contract_cases.dart' as suite8;
import '../components/cleaning/admin_contract_cases.dart' as suite9;

void main() {
  registerClientSuites({
    'order_grid_filters': suite0.main,
    'news_presentation_widget': suite1.main,
    'occasion_navigation_bar': suite2.main,
    'map_presentation_widget': suite3.main,
    'upload_icon_dialog': suite4.main,
    'nested_dialog': suite5.main,
    'order_projection_widget': suite6.main,
    'offline_presentation_widget': suite7.main,
    'program_contract': suite8.main,
    'admin_contract': suite9.main,
  });
}

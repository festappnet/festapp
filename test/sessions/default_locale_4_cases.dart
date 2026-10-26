import '../support/register_client_suites.dart';
import '../components/navigation/routed_tab_navigation_cases.dart' as suite0;
import '../components/navigation/object_route_access_cases.dart' as suite1;
import '../components/schedule/program_presentation_widget_cases.dart'
    as suite2;
import '../components/eshop/product_grid_record_cases.dart' as suite3;
import '../components/reception/reception_entry_widget_cases.dart' as suite4;
import '../components/unit/unit_presentation_widget_cases.dart' as suite5;
import '../components/map/map_unit_cases.dart' as suite7;
import '../services/service_adapter_cases.dart' as suite8;
import '../data_services/client_sync/client_sync_adapter_cases.dart' as suite9;

void main() {
  registerClientSuites({
    'routed_tab_navigation': suite0.main,
    'object_route_access': suite1.main,
    'program_presentation_widget': suite2.main,
    'product_grid_record': suite3.main,
    'reception_entry_widget': suite4.main,
    'unit_presentation_widget': suite5.main,
    'map_unit': suite7.main,
    'service_adapter': suite8.main,
    'client_sync_adapter': suite9.main,
  });
}

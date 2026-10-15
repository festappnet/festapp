import '../../support/register_client_suites.dart';
import 'map_renderer_host_cases.dart' as suite0;
import 'legacy_map_focus_contract_cases.dart' as suite1;
import 'path_node_cases.dart' as suite2;
import 'map_cache_cases.dart' as suite3;

void main() {
  registerClientSuites({
    'map_renderer_host': suite0.main,
    'legacy_map_focus_contract': suite1.main,
    'path_node': suite2.main,
    'map_cache': suite3.main,
  });
}

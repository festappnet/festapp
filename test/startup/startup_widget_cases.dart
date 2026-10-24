import '../support/register_client_suites.dart';
import 'app_bootstrap_cases.dart' as suite0;
import 'app_router_deep_link_cases.dart' as suite1;
import 'router_service_post_login_cases.dart' as suite2;
import '../router_reserved_paths_cases.dart' as suite3;

void main() {
  registerClientSuites({
    'app_bootstrap': suite0.main,
    'app_router_deep_link': suite1.main,
    'router_service_post_login': suite2.main,
    'router_reserved_paths': suite3.main,
  });
}

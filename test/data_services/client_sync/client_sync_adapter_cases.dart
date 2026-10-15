import '../../support/register_client_suites.dart';
import 'client_sync_unit_cases.dart' as suite0;
import 'client_sync_service_cases.dart' as suite1;
import 'client_sync_projection_cases.dart' as suite2;
import 'supabase_private_sync_remote_cases.dart' as suite3;

void main() {
  registerClientSuites({
    'client_sync_unit': suite0.main,
    'client_sync_service': suite1.main,
    'client_sync_projection': suite2.main,
    'supabase_private_sync_remote': suite3.main,
  });
}

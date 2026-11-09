import '../support/register_client_suites.dart';
import '../data_services/form_editor_rpc_test.dart' as suite;

void main() => registerClientSuites({'form_editor_rpc_test': suite.main});

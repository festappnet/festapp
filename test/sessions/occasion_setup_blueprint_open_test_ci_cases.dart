import '../support/register_client_suites.dart';
import '../components/occasion/occasion_setup_blueprint_open_test.dart'
    as suite;

void main() =>
    registerClientSuites({'occasion_setup_blueprint_open_test': suite.main});

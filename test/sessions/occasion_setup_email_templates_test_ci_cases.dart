import '../support/register_client_suites.dart';
import '../components/occasion/occasion_setup_email_templates_test.dart'
    as suite;

void main() =>
    registerClientSuites({'occasion_setup_email_templates_test': suite.main});

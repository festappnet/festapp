import '../support/register_client_suites.dart';
import '../data_services/rights_explicit_occasion_test.dart' as suite;

void main() =>
    registerClientSuites({'rights_explicit_occasion_test': suite.main});

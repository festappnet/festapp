import '../support/register_client_suites.dart';
import '../components/eshop/ticket_delivery_request_test.dart' as suite;

void main() =>
    registerClientSuites({'ticket_delivery_request_test': suite.main});

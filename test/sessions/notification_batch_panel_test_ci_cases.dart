import '../support/register_client_suites.dart';
import '../components/notification_center/notification_batch_panel_test.dart'
    as suite;

void main() =>
    registerClientSuites({'notification_batch_panel_test': suite.main});

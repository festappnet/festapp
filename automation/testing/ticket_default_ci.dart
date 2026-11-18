// Compatible CI roots only. SDK, font and fallback scopes stay separate.
import '../../test/support/register_client_suites.dart';
import '../../test/sessions/customer_self_service_settings_test.dart'
    as suite0;
import '../../test/components/notification_center/notification_email_settings_test.dart'
    as suite1;
import '../../test/components/email_templates/email_templates_cases.dart'
    as suite2;
import '../../test/components/ticket_layout/ticket_wallet_cases.dart'
    as suite3;
import '../../test/data_services/client_command_identity_cases.dart'
    as suite4;
import '../../test/components/blueprint/blueprint_template_groups_test.dart'
    as suite5;

void main() {
  registerClientSuites({
    'customer_self_service_settings_test': suite0.main,
    'notification_email_settings_test': suite1.main,
    'email_templates_cases': suite2.main,
    'ticket_wallet_cases': suite3.main,
    'client_command_identity_cases': suite4.main,
    'blueprint_template_groups_test': suite5.main,
  }, orderVariable: 'FESTAPP_CI_GROUP_ORDER');
}

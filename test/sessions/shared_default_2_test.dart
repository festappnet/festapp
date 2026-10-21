import '../components/occasion/occasion_setup_details_cases.dart'
    as occasion_setup_details;
import '../components/occasion/occasion_setup_communication_cases.dart'
    as occasion_setup_communication;
import '../components/occasion/occasion_setup_invitations_cases.dart'
    as occasion_setup_invitations;
import '../components/eshop/order_delete_availability_cases.dart'
    as order_delete_availability;
import '../components/forms/form_read_only_inspection_cases.dart'
    as form_read_only_inspection;
import '../components/html/html_image_preview_cases.dart' as html_image_preview;
import '../components/images/recovering_image_cases.dart' as recovering_image;
import '../data_services/client_sync/client_command_activation_cases.dart'
    as client_command_activation;
import '../services/last_administration_context_cases.dart'
    as last_administration_context;
import '../services/bounded_database_opener_cases.dart'
    as bounded_database_opener;
import '../past_occasion_years_cases.dart' as past_occasion_years;
import '../components/activities/activity_commands_cases.dart'
    as activity_commands;
import '../components/groups/group_save_reconciliation_cases.dart'
    as group_save_reconciliation;
import '../components/bank_accounts/bank_sync_contacts_cases.dart'
    as bank_sync_contacts;
import '../components/occasion/demo_occasion_navigation_cases.dart'
    as demo_occasion_navigation;
import '../components/occasion/occasion_setup_story_cases.dart'
    as occasion_setup_story;
import '../components/eshop/report_number_format_cases.dart'
    as report_number_format;
import '../components/eshop/tickets_tab_data_cases.dart' as tickets_tab_data;
import '../components/forms/admin_offer_form_link_cases.dart'
    as admin_offer_form_link;
import '../support/register_client_suites.dart';
import 'default_locale_3_cases.dart' as suite0;
import 'default_locale_2_cases.dart' as suite1;

void main() {
  registerClientSuites({
    'occasion_setup_details': occasion_setup_details.main,
    'occasion_setup_communication': occasion_setup_communication.main,
    'occasion_setup_invitations': occasion_setup_invitations.main,
    'order_delete_availability': order_delete_availability.main,
    'form_read_only_inspection': form_read_only_inspection.main,
    'html_image_preview': html_image_preview.main,
    'recovering_image': recovering_image.main,
    'client_command_activation': client_command_activation.main,
    'last_administration_context': last_administration_context.main,
    'bounded_database_opener': bounded_database_opener.main,
    'past_occasion_years': past_occasion_years.main,
    'activity_commands': activity_commands.main,
    'group_save_reconciliation': group_save_reconciliation.main,
    'bank_sync_contacts': bank_sync_contacts.main,
    'demo_occasion_navigation': demo_occasion_navigation.main,
    'occasion_setup_story': occasion_setup_story.main,
    'report_number_format': report_number_format.main,
    'tickets_tab_data': tickets_tab_data.main,
    'admin_offer_form_link': admin_offer_form_link.main,
    'default_locale_3': suite0.main,
    'default_locale_2': suite1.main,
  });
}

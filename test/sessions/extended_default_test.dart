import '../support/register_client_suites.dart';
import '../components/blueprint/blueprint_editor_feedback_cases.dart' as suite0;
import '../components/blueprint/blueprint_table_seating_cases.dart' as suite1;
import '../components/blueprint/seat_order_commands_cases.dart' as suite2;
import '../components/blueprint/ticket_cancellation_commands_cases.dart' as suite3;
import '../components/dialogs/responsive_search_empty_cases.dart' as suite4;
import '../components/eshop/order_email_navigation_cases.dart' as suite5;
import '../components/eshop/ticket_batch_print_downloads_cases.dart' as suite6;
import '../components/forms/form_appearance_theme_cases.dart' as suite7;
import '../components/forms/form_opening_timer_cases.dart' as suite8;
import '../components/forms/form_total_price_cases.dart' as suite9;
import '../components/forms/primary_product_guard_cases.dart' as suite10;
import '../components/mcp/mcp_connection_cases.dart' as suite11;
import '../components/navigation/help_organization_picker_cases.dart' as suite12;
import '../components/navigation/organizer_creation_entry_cases.dart' as suite13;
import '../components/navigation/reservations_capability_tabs_cases.dart' as suite14;
import '../components/navigation/ticketing_catalog_boundary_cases.dart' as suite15;
import '../components/notification_center/notification_center_prepared_cases.dart' as suite16;
import '../components/occasion/occasion_setup_email_document_cases.dart' as suite17;
import '../components/occasion/occasion_setup_ticket_loading_cases.dart' as suite18;
import '../components/single_data_grid/data_grid_number_format_cases.dart' as suite19;
import '../components/stripe_payments/canonical_quote_refresh_cases.dart' as suite20;
import '../components/stripe_payments/hidden_feature_cases.dart' as suite21;
import '../components/stripe_payments/stripe_feature_cases.dart' as suite22;
import '../components/stripe_payments/stripe_payment_link_cases.dart' as suite23;
import '../components/ticket_layout/ticket_text_autofit_cases.dart' as suite24;
import '../components/unit/app_landing_card_cases.dart' as suite25;
import '../components/users/occasion_team_invitation_cases.dart' as suite26;
import '../data_services/client_command_identity_cases.dart' as suite27;
import '../services/batch_progress_dialog_cases.dart' as suite28;
import '../services/deferred_external_url_cases.dart' as suite29;
import '../services/help_destination_cases.dart' as suite30;
import '../services/organizer_destination_cases.dart' as suite31;
import '../services/payment_deadline_cases.dart' as suite32;
import '../startup/public_occasion_scope_cases.dart' as suite33;
import '../widgets/synced_adaptive_theme_cases.dart' as suite34;

void main() {
  registerClientSuites({
    'blueprint_editor_feedback': suite0.main,
    'blueprint_table_seating': suite1.main,
    'seat_order_commands': suite2.main,
    'ticket_cancellation_commands': suite3.main,
    'responsive_search_empty': suite4.main,
    'order_email_navigation': suite5.main,
    'ticket_batch_print_downloads': suite6.main,
    'form_appearance_theme': suite7.main,
    'form_opening_timer': suite8.main,
    'form_total_price': suite9.main,
    'primary_product_guard': suite10.main,
    'mcp_connection': suite11.main,
    'help_organization_picker': suite12.main,
    'organizer_creation_entry': suite13.main,
    'reservations_capability_tabs': suite14.main,
    'ticketing_catalog_boundary': suite15.main,
    'notification_center_prepared': suite16.main,
    'occasion_setup_email_document': suite17.main,
    'occasion_setup_ticket_loading': suite18.main,
    'data_grid_number_format': suite19.main,
    'canonical_quote_refresh': suite20.main,
    'hidden_feature': suite21.main,
    'stripe_feature': suite22.main,
    'stripe_payment_link': suite23.main,
    'ticket_text_autofit': suite24.main,
    'app_landing_card': suite25.main,
    'occasion_team_invitation': suite26.main,
    'client_command_identity': suite27.main,
    'batch_progress_dialog': suite28.main,
    'deferred_external_url': suite29.main,
    'help_destination': suite30.main,
    'organizer_destination': suite31.main,
    'payment_deadline': suite32.main,
    'public_occasion_scope': suite33.main,
    'synced_adaptive_theme': suite34.main,
  });
}

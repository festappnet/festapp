import '../support/register_client_suites.dart';
import '../components/blueprint/blueprint_editor_file_drop_cases.dart' as suite0;
import '../components/blueprint/blueprint_legend_cases.dart' as suite1;
import '../components/blueprint/blueprint_mobile_pan_cases.dart' as suite2;
import '../components/eshop/ticket_batch_presentation_cases.dart' as suite3;
import '../components/forms/appearance_color_controls_cases.dart' as suite4;
import '../components/forms/email_domain_suffix_cases.dart' as suite5;
import '../components/forms/form_validation_cases.dart' as suite6;
import '../components/forms/presale_content_cases.dart' as suite7;
import '../components/forms/sale_opening_notifications_cases.dart' as suite8;
import '../components/notification_center/notification_center_time_cases.dart' as suite9;
import '../components/occasion/breadcrumb_creation_choice_cases.dart' as suite10;
import '../components/scan/scan_ticket_identity_cases.dart' as suite11;
import '../components/shared/editor_file_drop_region_cases.dart' as suite12;
import '../components/stripe_payments/admin_payment_precision_cases.dart' as suite13;
import '../components/stripe_payments/card_refund_decision_cases.dart' as suite14;
import '../components/stripe_payments/form_payment_settings_cases.dart' as suite15;
import '../components/stripe_payments/payment_access_cases.dart' as suite16;
import '../components/stripe_payments/payment_method_cards_cases.dart' as suite17;
import '../components/stripe_payments/payment_method_preview_cases.dart' as suite18;
import '../components/stripe_payments/stripe_connect_callback_cases.dart' as suite19;
import '../components/stripe_payments/stripe_products_dialog_cases.dart' as suite20;
import '../components/stripe_payments/unit_card_payments_cases.dart' as suite21;
import '../components/unit/unit_measurement_settings_cases.dart' as suite22;
import '../services/locale_date_time_cases.dart' as suite23;

void main() {
  registerClientSuites({
    'blueprint_editor_file_drop': suite0.main,
    'blueprint_legend': suite1.main,
    'blueprint_mobile_pan': suite2.main,
    'ticket_batch_presentation': suite3.main,
    'appearance_color_controls': suite4.main,
    'email_domain_suffix': suite5.main,
    'form_validation': suite6.main,
    'presale_content': suite7.main,
    'sale_opening_notifications': suite8.main,
    'notification_center_time': suite9.main,
    'breadcrumb_creation_choice': suite10.main,
    'scan_ticket_identity': suite11.main,
    'editor_file_drop_region': suite12.main,
    'admin_payment_precision': suite13.main,
    'card_refund_decision': suite14.main,
    'form_payment_settings': suite15.main,
    'payment_access': suite16.main,
    'payment_method_cards': suite17.main,
    'payment_method_preview': suite18.main,
    'stripe_connect_callback': suite19.main,
    'stripe_products_dialog': suite20.main,
    'unit_card_payments': suite21.main,
    'unit_measurement_settings': suite22.main,
    'locale_date_time': suite23.main,
  });
}

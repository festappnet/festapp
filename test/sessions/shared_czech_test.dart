import '../components/occasion/occasion_sale_cases.dart' as occasion_sale;
import '../components/occasion/occasion_setup_copy_cases.dart'
    as occasion_setup_copy;
import '../components/occasion/demo_occasion_banner_cases.dart'
    as demo_occasion_banner;
import '../components/occasion/demo_occasions_section_cases.dart'
    as demo_occasions_section;
import '../components/occasion/occasion_cover_draft_cases.dart'
    as occasion_cover_draft;
import '../components/occasion/occasion_setup_draft_card_cases.dart'
    as occasion_setup_draft_card;
import '../components/eshop/waitlist_order_detail_cases.dart'
    as waitlist_order_detail;
import '../components/eshop/price_wave_availability_cases.dart'
    as price_wave_availability;
import '../components/eshop/waitlist_history_cases.dart' as waitlist_history;
import '../components/eshop/waitlist_toolbar_cases.dart' as waitlist_toolbar;
import '../components/eshop/history_delete_cases.dart' as history_delete;
import '../components/eshop/order_state_width_cases.dart' as order_state_width;
import '../components/occasion_settings/advanced_link_visibility_cases.dart'
    as advanced_link_visibility;
import '../components/navigation/unit_occasion_draft_navigation_cases.dart'
    as unit_occasion_draft_navigation;
import '../components/navigation/inventory_navigation_behavior_cases.dart'
    as inventory_navigation_behavior;
import '../components/forms/waitlist_offers_dialog_cases.dart'
    as waitlist_offers_dialog;
import '../components/forms/form_capacity_settings_cases.dart'
    as form_capacity_settings;
import '../components/blueprint/blueprint_text_preparation_cases.dart'
    as blueprintTextPreparation;
import '../support/register_client_suites.dart';
import '../components/blueprint/blueprint_background_picker_cases.dart'
    as blueprint_background_picker;
import '../components/blueprint/blueprint_layout_assets_cases.dart'
    as blueprintAssets;
import '../components/blueprint/blueprint_image_upload_cases.dart'
    as blueprintImageUpload;
import '../components/occasion/blueprint_setup_layout_draft_cases.dart'
    as blueprintSetupDraft;
import '../components/blueprint/blueprint_layout_host_cases.dart'
    as blueprintHost;
import '../components/blueprint/blueprint_layout_ui_cases.dart'
    as blueprintLayoutUi;
import 'czech_catalog_3_cases.dart' as suite0;
import 'czech_catalog_2_cases.dart' as suite1;
import 'czech_catalog_1_cases.dart' as suite2;

void main() {
  registerClientSuites({
    'occasion_sale': occasion_sale.main,
    'occasion_setup_copy': occasion_setup_copy.main,
    'demo_occasion_banner': demo_occasion_banner.main,
    'demo_occasions_section': demo_occasions_section.main,
    'occasion_cover_draft': occasion_cover_draft.main,
    'occasion_setup_draft_card': occasion_setup_draft_card.main,
    'waitlist_order_detail': waitlist_order_detail.main,
    'price_wave_availability': price_wave_availability.main,
    'waitlist_history': waitlist_history.main,
    'waitlist_toolbar': waitlist_toolbar.main,
    'history_delete': history_delete.main,
    'order_state_width': order_state_width.main,
    'advanced_link_visibility': advanced_link_visibility.main,
    'unit_occasion_draft_navigation': unit_occasion_draft_navigation.main,
    'inventory_navigation_behavior': inventory_navigation_behavior.main,
    'waitlist_offers_dialog': waitlist_offers_dialog.main,
    'form_capacity_settings': form_capacity_settings.main,
    'czech_catalog_3': suite0.main,
    'czech_catalog_2': suite1.main,
    'czech_catalog_1': suite2.main,
    'blueprint_layout_ui': blueprintLayoutUi.main,
    'blueprint_background_picker': blueprint_background_picker.main,
    'blueprint_layout_host': blueprintHost.main,
    'blueprint_text_preparation': blueprintTextPreparation.main,
    'blueprint_layout_assets': blueprintAssets.main,
    'blueprint_image_upload': blueprintImageUpload.main,
    'blueprint_setup_layout_draft': blueprintSetupDraft.main,
  });
}

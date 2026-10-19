import '../support/register_client_suites.dart';
import '../components/blueprint/blueprint_background_picker_cases.dart'
    as blueprint_background_picker;
import '../components/blueprint/blueprint_layout_assets_cases.dart'
    as blueprintAssets;
import '../components/blueprint/blueprint_image_upload_cases.dart'
    as blueprintImageUpload;
import '../components/forms/default_values_cases.dart' as formDefaultValues;
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
    'czech_catalog_3': suite0.main,
    'czech_catalog_2': suite1.main,
    'czech_catalog_1': suite2.main,
    'blueprint_layout_ui': blueprintLayoutUi.main,
    'blueprint_background_picker': blueprint_background_picker.main,
    'blueprint_layout_host': blueprintHost.main,
    'blueprint_layout_assets': blueprintAssets.main,
    'blueprint_image_upload': blueprintImageUpload.main,
    'blueprint_form_default_values': formDefaultValues.main,
    'blueprint_setup_layout_draft': blueprintSetupDraft.main,
  });
}

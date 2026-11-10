import '../support/register_client_suites.dart';
import '../components/bank_accounts/bank_failure_diagnostic_cases.dart' as suite0;
import '../components/bank_accounts/connection_refresh_cases.dart' as suite1;
import '../components/blueprint/blueprint_focus_navigation_cases.dart' as suite2;
import '../components/blueprint/seating_cases.dart' as suite3;
import '../components/eshop/order_detail_split_pane_cases.dart' as suite4;
import '../components/eshop/order_grid_activation_revision_cases.dart' as suite5;
import '../components/forms/form_creation_visibility_cases.dart' as suite6;
import '../components/forms/organization_identity_cases.dart' as suite7;
import '../components/forms/verification_review_cases.dart' as suite8;

void main() {
  registerClientSuites({
    'bank_failure_diagnostic': suite0.main,
    'connection_refresh': suite1.main,
    'blueprint_focus_navigation': suite2.main,
    'seating_transition': suite3.main,
    'order_detail_split_pane': suite4.main,
    'order_grid_activation_revision': suite5.main,
    'form_creation_visibility': suite6.main,
    'organization_identity': suite7.main,
    'verification_review': suite8.main,
  });
}

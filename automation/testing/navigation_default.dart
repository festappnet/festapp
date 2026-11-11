import '../../test/components/users/member_access_batch_cases.dart'
    as access_batch;
import '../../test/components/users/member_access_dialog_cases.dart'
    as access_dialog;
import '../../test/support/register_client_suites.dart';
import '../../test/components/navigation/routed_tab_navigation_cases.dart'
    as s0;
import '../../test/components/breadcrumb_row_cases.dart' as s1;
import '../../test/components/navigation/ticketing_catalog_boundary_cases.dart'
    as s2;
import '../../test/components/unit/unit_presentation_widget_cases.dart' as s3;
import '../../test/components/single_data_grid/single_data_grid_widget_cases.dart'
    as s4;
import '../../test/components/users/profile_commands_cases.dart' as s5;
import '../../test/components/users/occasion_user_grid_cases.dart' as s6;

void main() {
  registerClientSuites({
    'routed_tab_navigation': s0.main,
    'breadcrumb_row': s1.main,
    'ticketing_catalog_boundary': s2.main,
    'unit_presentation_widget': s3.main,
    'single_data_grid_widget': s4.main,
    'profile_commands': s5.main,
    'occasion_user_grid': s6.main,
    'member_access_batch': access_batch.main,
    'member_access_dialog': access_dialog.main,
  });
}

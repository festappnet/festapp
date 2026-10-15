import '../support/register_client_suites.dart';
import '../components/html/rich_html_editor_lifecycle_cases.dart' as suite0;
import '../components/event_feedback/feedback_widget_cases.dart' as suite1;
import '../components/features/map_feature_cases.dart' as suite2;
import '../components/fonts/font_family_picker_cases.dart' as suite3;
import '../components/users/profile_companion_widget_cases.dart' as suite4;
import '../components/users/user_fields_widget_cases.dart' as suite5;
import '../components/ticket_layout/ticket_layout_unit_cases.dart' as suite6;
import '../components/map/mbtiles_vector_tile_provider_cases.dart' as suite7;

void main() {
  registerClientSuites({
    'rich_html_editor_lifecycle': suite0.main,
    'feedback_widget': suite1.main,
    'map_feature': suite2.main,
    'font_family_picker': suite3.main,
    'profile_companion_widget': suite4.main,
    'user_fields_widget': suite5.main,
    'ticket_layout_unit': suite6.main,
    'mbtiles_vector_tile_provider': suite7.main,
  });
}

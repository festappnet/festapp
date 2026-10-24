import '../../support/register_client_suites.dart';
import 'speaker_picker_field_cases.dart' as suite0;
import 'counseling_widgets_cases.dart' as suite1;
import 'speakers_unit_cases.dart' as suite2;
import '../groups/groups_unit_cases.dart' as suite3;
import '../groups/group_place_dialog_cases.dart' as suite4;

void main() {
  registerClientSuites({
    'speaker_picker_field': suite0.main,
    'counseling_widgets': suite1.main,
    'speakers_unit': suite2.main,
    'groups_unit': suite3.main,
    'group_place_dialog': suite4.main,
  });
}

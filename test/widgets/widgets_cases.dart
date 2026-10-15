import 'package:flutter_test/flutter_test.dart';

import 'app_dialog_cases.dart' as app_dialog;
import 'app_text_selection_cases.dart' as app_text_selection;
import 'logo_widget_cases.dart' as logo_widget;
import 'time_date_picker_cases.dart' as time_date_picker;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('app_dialog', app_dialog.main);
  group('app_text_selection', app_text_selection.main);
  group('logo_widget', logo_widget.main);
  group('time_date_picker', time_date_picker.main);
}

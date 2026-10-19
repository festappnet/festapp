import 'package:flutter_test/flutter_test.dart';

import 'email_wrapper_geometry_cases.dart' as email_wrapper_geometry;
import 'email_preview_context_cases.dart' as email_preview_context;
import 'email_visual_authoring_cases.dart' as email_visual_authoring;
import 'email_template_save_cases.dart' as email_template_save;
import 'email_authoring_cases.dart' as email_authoring;
import 'email_template_dialog_cases.dart' as email_template_dialog;
import 'email_template_model_cases.dart' as email_template_model;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('email_wrapper_geometry', email_wrapper_geometry.main);
  group('email_preview_context', email_preview_context.main);
  group('email_visual_authoring', email_visual_authoring.main);
  group('email_authoring', email_authoring.main);
  group('email_template_dialog', email_template_dialog.main);
  group('email_template_save', email_template_save.main);
  group('email_template_model', email_template_model.main);
}

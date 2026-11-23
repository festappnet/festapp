import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/theme_config.dart';

import '../form_strings.dart';
import '../models/form_editor_draft.dart';
import '../models/form_presentation.dart';

import '../waitlist_strings.dart';

DateTime? formDefaultClosingTime(FormEditorDraft form) =>
    (form.occasionEndTime ?? form.occasionModel?.endTime)?.toOccasionTime();

class FormAvailabilityStatus extends StatelessWidget {
  const FormAvailabilityStatus({
    super.key,
    required this.form,
    this.showWaitlist = true,
  });

  final FormEditorDraft form;
  final bool showWaitlist;

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;
    final now = DateTime.now();
    final closingTime = form.definition.endTime ?? formDefaultClosingTime(form);

    if (!(form.definition.isOpen ?? true)) {
      text = FormStrings.formClosedMessage;
      color = ThemeConfig.redColor(context);
    } else if (form.definition.startTime != null &&
        now.isBefore(form.definition.startTime!)) {
      text = FormStrings.scheduledWithTime(
        DateFormat.Md().add_jm().format(form.definition.startTime!),
      );
      color = ThemeConfig.redColor(context);
    } else if (closingTime != null && now.isAfter(closingTime)) {
      text = FormStrings.endedWithTime(
        DateFormat.Md().add_jm().format(closingTime),
      );
      color = ThemeConfig.redColor(context);
    } else if (showWaitlist && form.definition.isWaitlist) {
      text = WaitlistStrings.formOpenWaitlistMessage;
      color = ThemeConfig.warningColor(context);
    } else {
      text = FormStrings.formOpenMessage;
      color = Theme.of(context).primaryColor;
    }

    return Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.bold),
    );
  }
}

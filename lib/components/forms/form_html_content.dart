import 'package:fstapp/components/html/rich_html_editor_controller.dart';

import 'models/form_model.dart';
import 'models/holder_models/birth_date_field_holder.dart';
import 'widgets_view/form_helper.dart';

/// Explicit HTML inventory for the form writer; never guess from '<' in strings.
Future<void> prepareFormHtml(
    FormModel form, HtmlSaveCoordinator coordinator) async {
  final owner = HtmlMediaOwner.occasion(form.occasionId);
  Future<String?> prepare(String? value) async =>
      value == null ? null : await coordinator.prepare(value, owner);
  form.header = await prepare(form.header);
  form.headerOff = await prepare(form.headerOff);
  final schedule = form.data?[FormModel.metaSchedule];
  if (schedule is Map && schedule[FormModel.metaCountdownTitle] is String) {
    schedule[FormModel.metaCountdownTitle] =
        await prepare(schedule[FormModel.metaCountdownTitle] as String);
  }
  for (final field in form.relatedFields) {
    field.description = await prepare(field.description);
    for (final option in field.options) {
      option.description = await prepare(option.description);
    }
    if (field.type == FormHelper.fieldTypeBirthDate ||
        field.type == FormHelper.fieldTypeBirthYear) {
      final value = field.data?[BirthDateFieldHolder.metaMessage];
      if (value is String)
        field.data[BirthDateFieldHolder.metaMessage] = await prepare(value);
    }
    final type = field.productType;
    if (type != null) {
      type.description = await prepare(type.description);
      for (final product in type.products ?? []) {
        product.description = await prepare(product.description);
      }
    }
  }
}

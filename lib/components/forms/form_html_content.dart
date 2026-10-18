import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';

import 'models/form_editor_draft.dart';
import 'models/holder_models/birth_date_field_holder.dart';

/// Explicit HTML inventory for the form writer; never guess from '<' in strings.
Future<void> prepareFormHtml(
    FormEditorDraft form, HtmlSaveCoordinator coordinator) async {
  final owner = HtmlMediaOwner.occasion(form.definition.occasionId);
  Future<String?> prepare(String? value) async =>
      value == null ? null : await coordinator.prepare(value, owner);
  form.definition =
      form.definition.copyWith(header: await prepare(form.definition.header));
  form.definition = form.definition
      .copyWith(headerOff: await prepare(form.definition.headerOff));
  if (form.definition.countdownTitle != null) {
    form.definition = form.definition
        .withCountdownTitle(await prepare(form.definition.countdownTitle));
  }
  if (form.definition.beforeStartMessage != null) {
    form.definition = form.definition
        .withBeforeStartMessage(await prepare(form.definition.beforeStartMessage));
  }
  for (final field in form.relatedFields) {
    field.definition = field.definition
        .copyWith(description: await prepare(field.definition.description));
    for (final option in field.options) {
      option.description = await prepare(option.description);
    }
    if (field.definition.type == FormMetadata.fieldTypeBirthDate ||
        field.definition.type == FormMetadata.fieldTypeBirthYear) {
      final value = field.definition.data?[BirthDateFieldHolder.metaMessage];
      if (value is String)
        field.definition = field.definition.copyWith(data: {
          ...?field.definition.data,
          BirthDateFieldHolder.metaMessage: await prepare(value)
        });
    }
    final type = field.definition.productType;
    if (type != null) {
      field.definition = field.definition.copyWith(
          productType: type.copyWith(
        description: await prepare(type.description),
        products: type.products == null
            ? null
            : await Future.wait(type.products!.map((product) async => product
                .copyWith(description: await prepare(product.description)))),
      ));
    }
  }
}

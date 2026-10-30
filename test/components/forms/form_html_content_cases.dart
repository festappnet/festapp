import 'package:festapp_core/forms.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as image;
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/form_html_content.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/models/form_option_draft.dart';
import 'package:fstapp/components/forms/models/holder_models/birth_date_field_holder.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/html/html_media_service.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'form writer prepares every nested HTML destination and preserves non HTML metadata',
      () async {
    final png =
        Uint8List.fromList(image.encodePng(image.Image(width: 1, height: 1)));
    var uploads = 0;
    final coordinator =
        HtmlSaveCoordinator(media: HtmlMediaDraft(upload: (_, scope) async {
      expect(scope, const HtmlMediaOwner.occasion(12));
      uploads++;
      return 'https://assets.test/form.png';
    }));
    addTearDown(coordinator.dispose);
    final src = await coordinator.media
        .addBytes(png, const HtmlMediaOwner.occasion(12));
    final html = '<p style="font:italic bold 18px Arial;color:red">Text</p>'
        '<img src="$src" alt="Test">';
    final option = FormOptionDraft('one', 'One', description: html);
    final product = ProductModel(description: html);
    final type = ProductTypeModel(description: html, products: [product]);
    final field = FormFieldDraft(
        description: html,
        options: [option],
        productType: type,
        type: FormMetadata.fieldTypeBirthDate,
        data: {BirthDateFieldHolder.metaMessage: html});
    final form = FormEditorDraft(
        occasionId: 12,
        header: html,
        headerOff: html,
        relatedFields: [
          field
        ],
        data: {
          FormDefinition.metaSchedule: {
            FormDefinition.metaCountdownTitle: html,
            FormDefinition.metaBeforeStartMessage: html
          },
          FormDefinition.metaPaymentMessage: {'type': 'name_surname'},
          'unrelated': html
        });
    await prepareFormHtml(form, coordinator);
    for (final value in [
      form.definition.header,
      form.definition.headerOff,
      form.definition.countdownTitle,
      form.definition.beforeStartMessage,
      field.definition.description,
      option.description,
      field.definition.productType!.products!.single.description,
      field.definition.productType!.description,
      field.definition.data[BirthDateFieldHolder.metaMessage]
    ]) {
      expect(value, contains('https://assets.test/form.png'));
      expect(value, isNot(contains('html-draft.invalid')));
      expect(value, isNot(contains('Arial')));
      expect(value, isNot(contains('color:')));
      expect(value, contains('<strong><em>Text</em></strong>'));
    }
    expect(uploads, 1);
    expect(form.definition.data![FormDefinition.metaPaymentMessage],
        {'type': 'name_surname'});
    expect(form.definition.data!['unrelated'], html);
  });
}

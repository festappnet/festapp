import 'dart:typed_data';
import 'package:image/image.dart' as image;
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/form_html_content.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/models/form_option_model.dart';
import 'package:fstapp/components/forms/models/holder_models/birth_date_field_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/product_type_model.dart';
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
    final html = '<img src="$src" alt="Test">';
    final option = FormOptionModel('one', 'One', description: html);
    final product = ProductModel(description: html);
    final type = ProductTypeModel(description: html, products: [product]);
    final field = FormFieldModel(
        description: html,
        options: [option],
        productType: type,
        type: FormHelper.fieldTypeBirthDate,
        data: {BirthDateFieldHolder.metaMessage: html});
    final form = FormModel(
        occasionId: 12,
        header: html,
        headerOff: html,
        relatedFields: [
          field
        ],
        data: {
          FormModel.metaSchedule: {FormModel.metaCountdownTitle: html},
          FormModel.metaPaymentMessage: {'type': 'name_surname'},
          'unrelated': html
        });
    await prepareFormHtml(form, coordinator);
    for (final value in [
      form.header,
      form.headerOff,
      form.countdownTitle,
      field.description,
      option.description,
      product.description,
      type.description,
      field.data[BirthDateFieldHolder.metaMessage]
    ]) {
      expect(value, contains('https://assets.test/form.png'));
      expect(value, isNot(contains('html-draft.invalid')));
    }
    expect(uploads, 1);
    expect(form.data![FormModel.metaPaymentMessage], {'type': 'name_surname'});
    expect(form.data!['unrelated'], html);
  });
}

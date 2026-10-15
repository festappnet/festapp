import 'package:festapp_core/forms.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:festapp_core/eshop.dart';

void main() {
  test('blueprint products stay out of regular form and ticket choices', () {
    final spotType = ProductTypeModel(type: ProductModel.spotType, products: [
      ProductModel(id: 10, title: 'Seat', price: 450),
    ]);
    final form = FormEditorDraft(relatedFields: [
      FormFieldDraft(id: 1, type: FormMetadata.fieldTypeTicket),
      FormFieldDraft(
        id: 5,
        type: FormMetadata.fieldTypeSpot,
        isTicketField: true,
        isHidden: false,
      ),
      FormFieldDraft(
        id: 2,
        type: FormMetadata.fieldTypeProductType,
        isTicketField: true,
        productType: spotType,
      ),
      FormFieldDraft(
        id: 3,
        type: FormMetadata.fieldTypeProductType,
        isTicketField: true,
        productType: ProductTypeModel(products: [
          ProductModel(id: 11, title: 'Meal', price: 100),
        ]),
      ),
      FormFieldDraft(
        id: 4,
        type: FormMetadata.fieldTypeProductType,
        productType: spotType,
      ),
    ]);
    final holder = FormHolder.fromDefinition(form.freeze());
    expect(holder.fields.map((field) => field.id), [1]);
    expect(holder.getTicket()!.fields.map((field) => field.id), [5, 3]);
  });
}

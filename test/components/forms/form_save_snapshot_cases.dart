import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:festapp_core/eshop.dart';

void main() {
  test('save snapshot replaces generated field IDs and acknowledged versions without rebasing unrelated cached choices', () {
    final related = ProductTypeModel(
      id: 3,
      aggregateVersion: 4,
      products: [ProductModel(id: 9, aggregateVersion: 6, title: 'Before')],
    );
    final unrelated = ProductTypeModel(
      id: 42,
      aggregateVersion: 7,
      products: [ProductModel(id: 99, aggregateVersion: 8, title: 'Cached')],
    );
    final draft = FormEditorDraft(
      id: 1,
      occasionId: 7,
      key: 'preserved-editor-key',
      link: 'old-link',
      aggregateVersion: 2,
      relatedFields: [
        FormFieldDraft(id: 11, type: 'product_type', productType: related),
      ],
    );
    draft.captureProductCatalog([related, unrelated]);
    draft.deletedFieldIds.add(12);
    final previous = FormEditBundle(
      form: draft,
      productTypes: [related, unrelated],
      products: [...related.products!, ...unrelated.products!],
      availableBankAccounts: [],
    );
    final response = <String, dynamic>{
      'aggregate_version': 3,
      'link': 'saved-link',
      'product_versions': {'9': 7, '99': 999},
      'product_type_versions': {'3': 5, '42': 999},
      'authoring': {
        'form': {
          'id': 1,
          'occasion': 7,
          'title': 'Saved',
          'aggregate_version': 3,
        },
        'fields': [
          {'id': 13, 'type': 'product_type', 'product_type': 3},
        ],
        'productTypes': [
          {'id': 3, 'occasion': 7, 'aggregate_version': 5},
        ],
        'products': [
          {
            'id': 9,
            'product_type': 3,
            'occasion': 7,
            'title': 'Saved product',
            'aggregate_version': 7,
          },
        ],
        'productVersions': {'9': 7},
        'productTypeVersions': {'3': 5},
      },
    };
    final saved = FormEditBundle.fromSave(draft, response).form;
    expect(saved.relatedFields.single.definition.id, 13);
    expect(saved.definition.key, 'preserved-editor-key');
    expect(saved.definition.link, 'saved-link');
    expect(saved.deletedFieldIds, isEmpty);
    expect(saved.aggregateVersion, 3);
    expect(saved.toEditedJson()['expected_product_versions'], {
      '9': 7,
      '99': 8,
    });
    expect(saved.toEditedJson()['expected_product_type_versions'], {
      '3': 5,
      '42': 7,
    });
    final merged = previous.afterSave(saved);
    expect(merged.products.firstWhere((p) => p.id == 9).title, 'Saved product');
    expect(merged.products.firstWhere((p) => p.id == 99).title, 'Cached');
    expect(
      merged.productTypes.firstWhere((p) => p.id == 42).aggregateVersion,
      7,
    );
  });
}

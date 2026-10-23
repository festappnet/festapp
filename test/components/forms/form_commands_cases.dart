import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'reservation_capability_store_cases.dart' as reservationCapability;
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/supabase_form_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('form draft freezes shared product versions before edits or deletion',
      () {
    final original = ProductModel.fromJson(
        {'id': 9, 'title': 'Original', 'aggregate_version': 4});
    final type =
        ProductTypeModel(id: 3, aggregateVersion: 2, products: [original]);
    final field = FormFieldDraft(id: 11, productType: type);
    final draft =
        FormEditorDraft(id: 1, aggregateVersion: 7, relatedFields: [field]);
    field.definition = field.definition.copyWith(
        productType: type.copyWith(products: [
      original.copyWith(title: 'Draft', aggregateVersion: 99)
    ]));
    draft.captureProductCatalog([
      type.copyWith(products: [original.copyWith(aggregateVersion: 99)])
    ]);
    expect(draft.toEditedJson()['expected_product_versions'], {'9': 4});
    expect(draft.toEditedJson()['expected_product_type_versions'], {'3': 2});
    draft.removeField(field);
    expect(draft.toEditedJson()['expected_product_versions'], {'9': 4});
    expect(draft.toEditedJson()['deleted_field_ids'], [11]);
    draft.acceptProductVersions({
      'product_versions': {'9': 5},
      'product_type_versions': {'3': 3}
    });
    expect(draft.toEditedJson()['expected_product_versions'], {'9': 5});
    expect(original.copyWith(price: 15).aggregateVersion, 4);
    expect(original.toJson().containsKey('aggregate_version'), false);
  });

  group('reservation_capability', reservationCapability.main);
  test('form lifecycle and blueprint saves use dedicated command RPCs',
      () async {
    final calls = <String>[];
    final commands = SupabaseFormCommands.withTransport(
      ClientCommandTransport((name, params) async {
        calls.add(name);
        if (name == 'duplicate_form_to_occasion_client_sync_v1')
          expect(params['p_locale'], 'cs');
        if (name == 'delete_form_client_sync_v1')
          expect(params['p_expected_version'], 4);
        return {
          'status': 'applied',
          'code': 200,
          'mutation': {
            'commandId': params['p_command_id'],
            'receiptId': params['p_command_id'],
            'commitId': '00000000-0000-4000-8000-000000000001',
            'replayed': false,
            'occurredAt': '2026-10-20T10:00:00Z',
          },
          'data': {
            'code': 200,
            'mutation': {
              'commandId': params['p_command_id'],
              'receiptId': params['p_command_id'],
              'commitId': '00000000-0000-4000-8000-000000000001',
              'replayed': false,
              'occurredAt': '2026-10-20T10:00:00Z',
            },
            'formId': 8,
            if (name == 'update_blueprint_client_sync_v1') ...{
              'blueprint_id': 2,
              'layout_revision': 1,
              'seatBindings': <Object>[]
            }
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    await commands.create(
      occasionLink: 'festival',
      link: 'registration',
      title: 'Registration',
    );
    expect(
      await commands.duplicate(
        sourceFormId: 3,
        targetOccasionLink: 'next-festival',
        locale: 'cs',
      ),
      8,
    );
    await commands.delete(8, expectedVersion: 4);
    await commands.save({'id': 1, 'occasion': 7});
    await commands.saveBlueprint({
      'id': 2,
      'occasion': 7,
      'layout': <String, dynamic>{
        'schemaVersion': 2,
        'symbolSetVersion': 1,
        'canvas': {
          'x': 0,
          'y': 0,
          'width': 1000,
          'height': 1000,
          'fill': '#FFFFFFFF'
        },
        'styles': <String, dynamic>{},
        'seatingDefaults': <String, dynamic>{},
        'textPolicy': {'language': 'und', 'direction': 'auto'},
        'nodes': <Object>[]
      },
      'textResourceIds': <String>[],
      'expected_layout_revision': 0
    });
    await expectLater(
        commands.saveBlueprint({'id': 2, 'objects': []}), throwsStateError);
    expect(calls, [
      'create_form_client_sync_v1',
      'duplicate_form_to_occasion_client_sync_v1',
      'delete_form_client_sync_v1',
      'update_form_client_sync_v1',
      'update_blueprint_client_sync_v1',
    ]);
  });
}

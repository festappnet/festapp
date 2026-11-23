import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/supabase_form_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:http/http.dart' as http;

import '../support/fixtures/local_storage_fixture.dart';
import '../support/fixtures/root_supabase_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerLocalStorageFixture();
  late RootSupabaseFixture fixture;
  late Map<String, dynamic> storedForm;
  late List<Map<String, dynamic>> submitted;
  late Map<String, dynamic> product;
  late bool failAfterSave;
  final productTypes = [
    {'id': 9, 'occasion': 7, 'aggregate_version': 1},
  ];
  final fields = [
    {'id': 12, 'type': 'name', 'title': 'Name', 'order': 0},
    {'id': 13, 'type': 'product_type', 'product_type': 9, 'order': 1},
  ];
  const link = 'spolutvurcem2026';
  setUp(() {
    storedForm = {
      'id': 1,
      'occasion': 7,
      'link': link,
      'title': 'Registration',
      'header': 'Intro',
      'is_open': true,
      'aggregate_version': 3,
    };
    submitted = [];
    failAfterSave = false;
    product = {
      'id': 30,
      'occasion': 7,
      'product_type': 9,
      'aggregate_version': 2,
      'title': 'Ticket',
      'price': 100,
      'currency_code': 'CZK',
    };
  });

  setUpAll(() async {
    fixture = await RootSupabaseFixture.open((request) async {
      final params = jsonDecode(request.body) as Map<String, dynamic>;
      Object response;
      var status = 200;
      if (request.url.path.endsWith('/get_form_for_edit')) {
        // Mirror the released get_form_for_edit(form_link text) boundary.
        if (failAfterSave && submitted.isNotEmpty) {
          status = 503;
          response = {'message': 'Temporary read failure'};
        } else if (params.length != 1 || params['form_link'] != link) {
          status = 404;
          response = {
            'code': 'PGRST202',
            'message': 'Could not find public.get_form_for_edit(input_data)',
          };
        } else {
          response = {
            'code': 200,
            'data': {
              'form': storedForm,
              'form_fields': fields,
              'product_types': productTypes,
              'products': [product],
              'available_bank_accounts': [],
            },
          };
        }
      } else if (request.url.path.endsWith('/update_form_client_sync_v1')) {
        final payload = Map<String, dynamic>.from(params['p_form'] as Map);
        submitted.add(payload);
        final version = storedForm['aggregate_version'] as int;
        final productVersion = product['aggregate_version'] as int;
        final productConflict =
            payload.containsKey('form_fields') &&
            (payload['expected_product_versions'] as Map)['30'] !=
                productVersion;
        final matches =
            payload['expected_aggregate_version'] == version &&
            !productConflict;
        if (matches) {
          for (final key in ['header', 'title', 'is_open']) {
            if (payload.containsKey(key)) storedForm[key] = payload[key];
          }
          storedForm['aggregate_version'] = version + 1;
        }
        response = {
          'status': matches ? 'applied' : 'conflict',
          'code': matches ? 200 : 409,
          'data': {
            'aggregate_version': storedForm['aggregate_version'],
            if (productConflict) 'entity_type': 'product',
            if (matches) ...{
              'link': link,
              'product_versions': {'30': productVersion},
              'product_type_versions': {'9': 1},
              'authoring': {
                'form': storedForm,
                'fields': fields,
                'products': [product],
                'productTypes': productTypes,
                'productVersions': {'30': productVersion},
                'productTypeVersions': {'9': 1},
              },
            },
          },
          'mutation': {
            'commandId': params['p_command_id'],
            'receiptId': params['p_command_id'],
            'replayed': false,
            'occurredAt': '2026-11-23T11:00:00Z',
          },
          'sync': {'replacements': <Object>[]},
        };
      } else if (request.url.path.endsWith('/get_form_by_link')) {
        expect(params, {
          'input_data': {
            'form_link': 'spolutvurcem2026',
            'client_capabilities': ['cash_reservations', 'no_payment_deadline'],
          },
        });
        response = {'code': 404};
      } else {
        throw StateError('Unexpected request: ${request.url.path}');
      }
      return http.Response(
        jsonEncode(response),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    });
  });
  tearDownAll(() => fixture.dispose());

  test(
    'editor loads its bundle through the released text RPC signature',
    () async {
      final bundle = await DbForms.getFormForEdit('spolutvurcem2026');
      expect(bundle, isNotNull);
      expect(bundle!.form.definition.link, 'spolutvurcem2026');
      expect(bundle.form.definition.title, 'Registration');
    },
  );

  test(
    'form save keeps payment errors and identifies message-free conflicts',
    () async {
      final responses = [
        (409, 'conflict', {'aggregate_version': 1}, 'FORM_SAVE_CONFLICT'),
        (
          400,
          'rejected',
          {'message': 'PAYMENT_CONFIGURATION_INCOMPLETE'},
          'PAYMENT_CONFIGURATION_INCOMPLETE',
        ),
      ];
      for (final (code, status, data, message) in responses) {
        final commands = SupabaseFormCommands.withTransport(
          ClientCommandTransport(
            (_, params) async => {
              'status': status,
              'code': code,
              'data': data,
              'mutation': {
                'commandId': params['p_command_id'],
                'receiptId': params['p_command_id'],
                'commitId': null,
                'replayed': false,
                'occurredAt': '2026-11-19T11:13:55Z',
              },
              'sync': {'replacements': <Object>[]},
            },
          ),
        );
        await expectLater(
          commands.save(FormEditorDraft(id: 1, occasionId: 7).toEditedJson()),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              message,
            ),
          ),
        );
      }
    },
  );

  test("save merges a stale tab's independent edit", () async {
    final editor = (await DbForms.getFormForEdit(link))!.form;
    final settings = (await DbForms.getFormForEdit(link))!.form;
    settings.definition = settings.definition.copyWith(title: 'Renamed');
    await DbForms.updateForm(settings);

    editor.definition = editor.definition.copyWith(header: 'New intro');
    final saved = await DbForms.updateForm(editor);

    expect(saved.definition.title, 'Renamed');
    expect(saved.definition.header, 'New intro');
    expect(submitted.map((p) => p['expected_aggregate_version']), [3, 3, 4]);
    for (final request in submitted) {
      expect(request, isNot(contains('form_fields')));
    }
    expect(submitted.last, isNot(contains('title')));
  });

  test(
    'saving availability leaves a scheduled product change intact',
    () async {
      final editor = (await DbForms.getFormForEdit(link))!.form;
      product['price'] = 120;
      product['aggregate_version'] = 3;
      editor.definition = editor.definition.copyWith(isOpen: false);

      final saved = await DbForms.updateForm(editor);

      expect(saved.definition.isOpen, false);
      final productType = saved.relatedFields.last.definition.productType!;
      expect(productType.products!.single.price, 120);
      expect(submitted.single, isNot(contains('form_fields')));
      expect(saved.toEditedJson()['expected_product_versions'], {'30': 3});
    },
  );

  test('an edited product still requires its original revision', () async {
    final editor = (await DbForms.getFormForEdit(link))!.form;
    final field = editor.relatedFields.last;
    final type = field.definition.productType!;
    field.definition = field.definition.copyWith(
      productType: type.copyWith(
        products: [type.products!.single.copyWith(price: 130)],
      ),
    );
    product['aggregate_version'] = 3;

    await expectLater(DbForms.updateForm(editor), throwsA(isA<StateError>()));
    expect(submitted.single['expected_product_versions'], {'30': 2});
    expect(product['price'], 100);
  });

  test('a policy read failure preserves the committed save receipt', () async {
    final editor = (await DbForms.getFormForEdit(link))!.form;
    editor.definition = editor.definition.copyWith(header: 'New intro');
    failAfterSave = true;

    final saved = await DbForms.updateForm(editor);

    expect(saved.definition.header, 'New intro');
    expect(saved.aggregateVersion, 4);
    expect(submitted, hasLength(1));
  });

  test('save preserves the draft when the same value changed', () async {
    final editor = (await DbForms.getFormForEdit(link))!.form;
    storedForm['aggregate_version'] = 4;
    storedForm['header'] = 'Other intro';
    editor.definition = editor.definition.copyWith(header: 'My intro');

    await expectLater(
      DbForms.updateForm(editor),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'FORM_SAVE_CONFLICT',
        ),
      ),
    );
    expect(submitted, hasLength(1));
    expect(storedForm['header'], 'Other intro');
    expect(editor.definition.header, 'My intro');
  });

  test('public reader retains cash capability negotiation', () async {
    expect(await DbForms.getFormFromLink('spolutvurcem2026'), isNull);
  });
}

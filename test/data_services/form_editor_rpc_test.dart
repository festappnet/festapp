import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:http/http.dart' as http;

import '../support/fixtures/root_supabase_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RootSupabaseFixture fixture;

  setUpAll(() async {
    fixture = await RootSupabaseFixture.open((request) async {
      final params = jsonDecode(request.body) as Map<String, dynamic>;
      Object response;
      var status = 200;
      if (request.url.path.endsWith('/get_form_for_edit')) {
        // Mirror the released get_form_for_edit(form_link text) boundary.
        if (params.length != 1 || params['form_link'] != 'spolutvurcem2026') {
          status = 404;
          response = {
            'code': 'PGRST202',
            'message': 'Could not find public.get_form_for_edit(input_data)',
          };
        } else {
          response = {
            'code': 200,
            'data': {
              'form': {
                'id': 1,
                'link': 'spolutvurcem2026',
                'title': 'Registration',
              },
              'form_fields': [],
              'product_types': [],
              'products': [],
              'available_bank_accounts': [],
            },
          };
        }
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

  test('public reader retains cash capability negotiation', () async {
    expect(await DbForms.getFormFromLink('spolutvurcem2026'), isNull);
  });
}

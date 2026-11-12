import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/payments/payment_policy.dart';
import 'package:fstapp/components/payments/db_payment_policy.dart';

Map<String, Object?> policy({int unit = 9}) => {
  'organizationId': 1,
  'unitId': unit,
  'revision': 2,
  'preferredMethod': 'orchard',
  'methods': <String, Object?>{
    'orchard': {
      'id': 'orchard',
      'mode': 'inherit',
      'inheritedFrom': 'organization',
      'organizationEnabled': true,
      'policyEnabled': true,
      'configured': true,
      'ready': false,
      'canConfigure': true,
    },
  },
};

Map<String, Object?> previewJson() => {
  'confirmation': List.filled(64, 'a').join(),
  'impact': {
    'openCollections': 2,
    'pendingRequests': 3,
    'issuedReferences': 4,
    'pendingBankInstructions': 0,
    'obligations': 5,
    'providerIntents': {'undispatched': 1, 'dispatched': 2, 'unknown': 3},
  },
};

http.Response response(
  Object value,
  http.Request request, {
  int status = 200,
}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
  request: request,
);

void main() {
  test('typed policy preserves arbitrary installed connectors and independent readiness', () {
    final value = PaymentPolicy.fromJson(policy());
    expect(value.methods['orchard']!.enabled, isTrue);
    expect(value.methods['orchard']!.ready, isFalse);
    expect(value.methods['orchard']!.mode, PaymentPolicyMode.inherit);
    expect(value.methods['bank'], isNull);
    expect(() => value.methods.clear(), throwsUnsupportedError);
  });

  test('malformed policy fails closed instead of choosing defaults', () {
    for (final override in [
      {'mode': 'invented'},
      {'policyEnabled': 'true'},
      {'id': 'bank'},
      {'configured': null},
    ]) {
      final json = policy();
      final methods = json['methods'] as Map<String, Object?>;
      methods['orchard'] = {
        ...methods['orchard'] as Map<String, Object?>,
        ...override,
      };
      expect(() => PaymentPolicy.fromJson(json), throwsFormatException);
    }
  });

  test('service rejects a valid policy belonging to another unit', () async {
    final client = SupabaseClient(
      'https://fixture.invalid',
      'fixture-key',
      httpClient: MockClient(
        (request) async => response(policy(unit: 10), request),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(
      DbPaymentPolicy(client).load(1, 9),
      throwsFormatException,
    );
  });

  test('typed preview rejects incomplete financial impact', () {
    const change = PaymentPolicyChange(
      organizationId: 1,
      unitId: 9,
      method: 'orchard',
      mode: PaymentPolicyMode.disabled,
    );
    final json = previewJson();
    (json['impact'] as Map<String, Object?>).remove('providerIntents');
    expect(
      () => PaymentPolicyPreview.fromJson(change, json),
      throwsFormatException,
    );
  });

  test(
    'command submits the exact immutable change bound to the confirmed preview',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://fixture.invalid',
        'fixture-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return response(
            request.url.path.endsWith('preview_payment_method_policy')
                ? previewJson()
                : {},
            request,
          );
        }),
      );
      addTearDown(client.dispose);
      final service = DbPaymentPolicy(client);
      const change = PaymentPolicyChange(
        organizationId: 1,
        unitId: 9,
        method: 'orchard',
        mode: PaymentPolicyMode.disabled,
      );
      final preview = await service.preview(change);
      expect(preview.impact.unknownIntents, 3);
      await service.command(preview);
      final before = jsonDecode(requests.first.body) as Map;
      final submitted = jsonDecode(requests.last.body) as Map;
      expect(submitted['input_data'], before['input_data']);
      expect(submitted['p_confirmation'], preview.confirmation);
      expect(submitted['p_command_id'], matches(RegExp(r'^[a-f0-9-]{36}$')));
    },
  );

  test('service preserves backend permission failures', () async {
    final client = SupabaseClient(
      'https://fixture.invalid',
      'fixture-key',
      httpClient: MockClient(
        (request) async => response(
          {'code': '42501', 'message': 'denied'},
          request,
          status: 403,
        ),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(
      DbPaymentPolicy(client).load(1, 9),
      throwsA(isA<PostgrestException>()),
    );
  });
}

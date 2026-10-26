import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/app_config_rpc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('uses v219 when the backend supports the transition contract', () async {
    final calls = <String>[];

    final result = await loadAppConfigWithLegacyFallback(
      invoke: (name) async {
        calls.add(name);
        return <String, dynamic>{'client_sync_v1': true};
      },
    );

    expect(calls, <String>['get_app_config_v219']);
    expect(result['client_sync_v1'], isTrue);
  });

  test('uses v218 directly when startup selected the legacy backend', () async {
    final calls = <String>[];

    final result = await loadAppConfigWithLegacyFallback(
      useLegacyContract: true,
      invoke: (name) async {
        calls.add(name);
        return <String, dynamic>{'code': 200};
      },
    );

    expect(calls, <String>['get_app_config_v218']);
    expect(result['code'], 200);
    expect(result['client_sync_v1'], isFalse);
  });

  test('falls back to v2 when a legacy backend predates v218', () async {
    final calls = <String>[];

    final result = await loadAppConfigWithLegacyFallback(
      useLegacyContract: true,
      invoke: (name) async {
        calls.add(name);
        if (name == 'get_app_config_v218') {
          throw const PostgrestException(
            message: 'function missing',
            code: 'PGRST202',
          );
        }
        return <String, dynamic>{
          'code': 200,
          'occasion': <String, dynamic>{'link': 'slunovrat'},
        };
      },
    );

    expect(calls, <String>['get_app_config_v218', 'get_app_config_v2']);
    expect(result['occasion']['link'], 'slunovrat');
    expect(result['client_sync_v1'], isFalse);
  });

  test('does not hide unrelated v218 failures on a legacy backend', () async {
    final calls = <String>[];

    await expectLater(
      loadAppConfigWithLegacyFallback(
        useLegacyContract: true,
        invoke: (name) async {
          calls.add(name);
          throw const PostgrestException(
            message: 'permission denied',
            code: '42501',
          );
        },
      ),
      throwsA(isA<PostgrestException>()),
    );

    expect(calls, <String>['get_app_config_v218']);
  });

  test('falls back to v218 only when v219 is absent', () async {
    final calls = <String>[];

    final result = await loadAppConfigWithLegacyFallback(
      invoke: (name) async {
        calls.add(name);
        if (name == 'get_app_config_v219') {
          throw const PostgrestException(
            message: 'function missing',
            code: 'PGRST202',
          );
        }
        return <String, dynamic>{
          'occasion': <String, dynamic>{'id': 1}
        };
      },
    );

    expect(calls, <String>['get_app_config_v219', 'get_app_config_v218']);
    expect(result['occasion']['id'], 1);
    expect(result['client_sync_v1'], isFalse);
  });

  test('does not hide unrelated PostgREST failures', () async {
    await expectLater(
      loadAppConfigWithLegacyFallback(
        invoke: (_) async => throw const PostgrestException(
          message: 'forbidden',
          code: '42501',
        ),
      ),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('accepts the web runtime wrapper for the exact missing v219 error',
      () async {
    final calls = <String>[];
    final result = await loadAppConfigWithLegacyFallback(
      invoke: (name) async {
        calls.add(name);
        if (name == 'get_app_config_v219') {
          throw Exception(
            'PostgrestException(code: PGRST202, function: get_app_config_v219)',
          );
        }
        return <String, dynamic>{'code': 'ok'};
      },
    );

    expect(calls, <String>['get_app_config_v219', 'get_app_config_v218']);
    expect(result['client_sync_v1'], isFalse);
  });
}

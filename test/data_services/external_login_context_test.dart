import 'package:crypto/crypto.dart';
import 'package:fstapp/services/account_mfa_settings_service.dart';
import 'package:fstapp/services/backend_activation_service.dart';
import 'package:http/testing.dart';

import 'package:festapp_core/program.dart' as occasion_time;

import '../support/fixtures/root_supabase_fixture.dart';
import '../support/fixtures/local_app_storage_fixture.dart';
import '../support/fixtures/rights_context_fixture.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('external login loads authenticated app config before reporting completion', () async {
    const userId = '00000000-0000-4000-8000-000000000001';
    const factorId = '00000000-0000-4000-8000-000000000002';
    const challengeId = '00000000-0000-4000-8000-000000000003';
    final requests = <String>[];
    occasion_time.OccasionTimeContext.initializeTimeZones();
    final state = RightsContextFixture();
    addTearDown(state.dispose);
    final storage = await LocalAppStorageFixture.open();
    addTearDown(storage.dispose);
    FlutterSecureStorage.setMockInitialValues({});
    addTearDown(() => const FlutterSecureStorage().deleteAll());
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    String tokenPart(Map<String, Object> claims) =>
        base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
    String tokenFor(String proof) {
      final header = tokenPart({'alg': 'HS256', 'typ': 'JWT'});
      final claims = tokenPart({
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'sub': userId,
        'proof': proof,
      });
      return '$header.$claims.Zml4dHVyZQ';
    }

    final token = tokenFor('first');
    final verifiedToken = tokenFor('totp');
    final user = {
      'id': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'person@example.com',
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': {},
      'user_metadata': {},
    };
    Map<String, dynamic> session(String accessToken) => {
      'access_token': accessToken,
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': user,
    };
    var requiresTotp = false;
    var securityProofRequired = false;
    var recoveryHeld = false;
    var passwordToken = token;
    final fixture = await RootSupabaseFixture.open((request) async {
      requests.add(request.url.path);
      http.Response reply(Object payload) => http.Response(
        jsonEncode(payload),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
      if (request.url.path == '/auth/v1/token') {
        return reply(session(passwordToken));
      }
      if (request.url.path == '/auth/v1/user') {
        return reply({
          ...user,
          'factors': [
            {
              'id': factorId,
              'status': 'verified',
              'factor_type': 'totp',
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
            },
          ],
        });
      }
      if (request.url.path == '/auth/v1/factors/$factorId/challenge') {
        return reply({
          'id': challengeId,
          'type': 'totp',
          'expires_at': 4102444800,
        });
      }
      if (request.url.path == '/auth/v1/factors/$factorId/verify') {
        expect(jsonDecode(request.body), {
          'challenge_id': challengeId,
          'code': '012345',
        });
        return reply(session(verifiedToken));
      }
      if (request.url.path == '/rest/v1/user_info') {
        return http.Response(
          jsonEncode([
            {'id': userId},
          ]),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/rest/v1/rpc/get_account_assurance_v1') {
        final params = jsonDecode(request.body) as Map;
        expect(params['p_organization'], AppConfig.organization);
        if (recoveryHeld) return reply('account_recovery');
        if (params['p_account_security'] == true && securityProofRequired) {
          return reply('proof_required');
        }
        return reply(
          requiresTotp &&
                  request.headers['authorization'] != 'Bearer $verifiedToken'
              ? 'mfa_required'
              : 'allowed',
        );
      }
      if (request.url.path ==
          '/rest/v1/rpc/get_mfa_recovery_registration_actor_v1') {
        final params = jsonDecode(request.body) as Map;
        expect(params['p_organization'], AppConfig.organization);
        return reply({'decision': 'allowed'});
      }
      if (request.url.path.startsWith('/rest/v1/rpc/get_app_config_')) {
        expect(
          request.headers['authorization'],
          'Bearer ${requiresTotp ? verifiedToken : token}',
        );
        return http.Response(
          jsonEncode({
            'code': 200,
            'user_info': {
              'id': userId,
              'units': [
                {'id': 980, 'title': 'First'},
                {'id': 981, 'title': 'Second'},
              ],
            },
            'organization': {'title': 'Authenticated organization'},
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '{}',
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(fixture.dispose);
    {
      RightsService.occasionLinkModelNotifier.value = null;
      await AuthService.completeExternalLogin({
        'organization': AppConfig.organization,
        'userId': userId,
        'session': {'refresh_token': 'fixture-refresh'},
      });
      expect(
        requests.where(
          (path) => path.startsWith('/rest/v1/rpc/get_app_config_'),
        ),
        isNotEmpty,
      );
      final assurance = requests.indexOf(
        '/rest/v1/rpc/get_account_assurance_v1',
      );
      expect(assurance, isNonNegative);
      expect(assurance, lessThan(requests.indexOf('/rest/v1/user_info')));
      expect(
        assurance,
        lessThan(
          requests.indexWhere(
            (path) => path.startsWith('/rest/v1/rpc/get_app_config_'),
          ),
        ),
      );
      expect(RightsService.currentUser()?.id, userId);
      expect(RightsService.currentUser()?.units?.map((unit) => unit.id), [
        980,
        981,
      ]);
      expect(
        RightsService.occasionLinkModel?.organization?.title,
        'Authenticated organization',
      );
    }
    await OfflineDataService.saveUserInfo(
      UserInfoModel(id: userId, name: 'First account'),
    );
    await StorageHelper.set(
      UserInfoModel.userInfoOffline,
      jsonEncode({
        'id': 'different-account',
        'name': 'Historical global cache',
      }),
    );
    expect((await OfflineDataService.getUserInfo())?.name, 'First account');
    expect(AuthService.privateCacheOwner, '${AppConfig.organization}/$userId');

    requiresTotp = true;
    requests.clear();
    try {
      await AuthService.login(
        AppConfig.getUserPrefix('person@example.invalid'),
        'fixture-password',
      );
      fail('First-factor sign-in must require an enrolled factor');
    } on AccountVerificationRequired catch (pending) {
      expect(
        requests.any((path) => path.startsWith('/rest/v1/rpc/get_app_config_')),
        isFalse,
      );
      expect(pending.verification.factors.single.id, factorId);
      expect(AuthService.privateCacheOwner, isNull);
      expect(await OfflineDataService.getUserInfo(), isNull);
      await AuthService.restoreOfflineAssurance();
      expect(AuthService.privateCacheOwner, isNull);
      await AuthService.verifyAccountLogin(
        pending.verification,
        factorId,
        '012345',
      );
      expect(
        AuthService.privateCacheOwner,
        '${AppConfig.organization}/$userId',
      );
      expect((await OfflineDataService.getUserInfo())?.name, 'First account');
      expect(RightsService.currentUser()?.id, userId);
    }

    passwordToken = tokenFor('refreshed-without-server-decision');
    await Supabase.instance.client.auth.setSession('fixture-refresh');
    await AuthService.restoreOfflineAssurance();
    expect(AuthService.privateCacheOwner, isNull);
    expect(await OfflineDataService.getUserInfo(), isNull);

    passwordToken = verifiedToken;
    final client = Supabase.instance.client;
    await client.auth.setSession('fixture-refresh');
    final steps = <String>[];
    String? codeChallenge;
    final supportCode = 's' * 43;
    final recoveryToken = tokenFor('held-password-proof');
    final broker = MockClient((request) async {
      final step = request.url.path.split('/').last;
      steps.add(step);
      final payload = request.body.isEmpty
          ? {}
          : jsonDecode(request.body) as Map;
      final result = switch (step) {
        'channel' => {
          'methods': {
            'totp': {'offer': true, 'registration': true},
          },
        },
        'start' => {
          'callback':
              'https://app.fixture.invalid/app/google-auth?mfa_code=${'c' * 43}',
        },
        'claim' => {'id': 'fixture-receipt', 'method': 'totp'},
        'enroll' => {
          'id': factorId,
          'totp': {
            'uri': 'otpauth://totp/Fixture?secret=FIXTURE',
            'secret': 'FIXTURE',
          },
        },
        'verify' => {
          'access_token': verifiedToken,
          'refresh_token': 'fixture-refresh',
        },
        'remove' => {'removed': true, 'revokesSession': true},
        _ => throw StateError('Unexpected broker operation'),
      };
      if (step != 'channel') {
        expect(
          request.headers['authorization'],
          'Bearer ${recoveryHeld ? recoveryToken : verifiedToken}',
        );
      }
      if (step == 'start') {
        expect(payload['inPlace'], true);
        expect(payload['recoveryCode'], recoveryHeld ? supportCode : isNull);
        expect(
          payload['redirectUri'],
          'https://app.fixture.invalid/app/google-auth',
        );
        codeChallenge = payload['codeChallenge'] as String;
      }
      if (step == 'claim') {
        final digest = sha256.convert(
          utf8.encode(payload['codeVerifier'] as String),
        );
        expect(
          base64UrlEncode(digest.bytes).replaceAll('=', ''),
          codeChallenge,
        );
      }
      if (['claim', 'enroll', 'verify'].contains(step)) {
        expect(payload['recovery'], recoveryHeld ? true : isNull);
      }
      if (step == 'verify') expect(payload['code'], '012345');
      if (step == 'remove') expect(payload['confirmDisable'], true);
      return http.Response(jsonEncode(result), 200);
    });
    final settings = AccountMfaSettingsService(
      ResolvedBackend(
        supabaseUrl: 'https://fixture.invalid',
        anonKey: 'synthetic-fixture',
        organizationId: AppConfig.organization,
        profileSha256: '',
        isCanonical: true,
      ),
      client,
      broker,
      'fixture-native',
      origin: 'https://app.fixture.invalid',
    );
    addTearDown(settings.dispose);
    final inventory = await settings.load();
    expect(inventory.registrationMethods, {'totp'});
    expect(inventory.factors.single.id, factorId);
    securityProofRequired = true;
    await expectLater(
      settings.enrollTotp(),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          'proof_required',
        ),
      ),
    );
    expect(steps, ['channel']);
    securityProofRequired = false;
    final setup = await settings.enrollTotp();
    expect(steps, ['channel', 'start', 'claim', 'enroll']);
    expect(setup.secret, 'FIXTURE');

    passwordToken = tokenFor('changed-settings-session');
    await client.auth.setSession('fixture-refresh');
    await expectLater(
      settings.verifyTotp(setup, '012345'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          'invalid_session',
        ),
      ),
    );
    expect(steps.last, 'enroll');
    passwordToken = verifiedToken;
    await client.auth.setSession('fixture-refresh');
    await settings.verifyTotp(setup, '012345');
    expect(
      await settings.remove(inventory.factors.single, confirmDisable: true),
      isTrue,
    );
    expect(steps.sublist(steps.length - 2), ['verify', 'remove']);

    recoveryHeld = true;
    passwordToken = recoveryToken;
    await client.auth.setSession('fixture-refresh');
    final held = await AuthService.pendingAccountVerification();
    expect(held?.recovery, isTrue);
    expect(held?.canReplaceFactor, isTrue);
    expect(AuthService.privateCacheOwner, isNull);
    AuthService.requireCurrentVerification(held!);
    final replacement = await settings.enrollTotp(recoveryCode: supportCode);
    expect(replacement.recovery, isTrue);
    await settings.verifyTotp(replacement, '012345');
    await AuthService.cancelAccountVerification(held);
    expect(client.auth.currentSession?.accessToken, verifiedToken);
    expect(AuthService.privateCacheOwner, isNull);
    expect(steps.sublist(steps.length - 4), [
      'start',
      'claim',
      'enroll',
      'verify',
    ]);
  });
}

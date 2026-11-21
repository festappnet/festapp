import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/account_mfa_settings_service.dart';
import 'package:fstapp/services/account_webauthn_browser_web.dart';
import 'package:fstapp/services/backend_activation_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

void main() {
  test(
    'Flutter web exchanges a passkey code only for its registered callback',
    () async {
      final credentials = web.window.navigator.credentials;
      final previousGet = credentials['get'];
      addTearDown(() => credentials['get'] = previousGet);
      var active = true;
      var cancelInBrowser = true;
      credentials['get'] = ((JSObject _) {
        if (cancelInBrowser) active = false;
        final assertion = JSObject();
        assertion['toJSON'] =
            (() => {'id': 'fixture-credential'}.jsify() as JSObject).toJS;
        return Future<JSObject?>.value(assertion).toJS;
      }).toJS;

      const userId = '00000000-0000-4000-8000-000000000001';
      String encode(Map<String, Object?> data) =>
          base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
      final header = encode({'alg': 'HS256', 'typ': 'JWT'});
      final claims = encode({
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'sub': userId,
      });
      final accessToken = '$header.$claims.Zml4dHVyZQ';
      final backend = ResolvedBackend(
        supabaseUrl: 'https://backend.fixture.invalid',
        anonKey: 'synthetic-fixture',
        organizationId: AppConfig.organization,
        profileSha256: '',
        isCanonical: true,
      );
      AccountMfaSettingsService.configure(backend);
      final sdk = SupabaseClient(
        backend.supabaseUrl,
        backend.anonKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/auth/v1/user');
          expect(request.headers['authorization'], 'Bearer $accessToken');
          return http.Response(
            jsonEncode({
              'id': userId,
              'email': 'person@example.invalid',
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
              'app_metadata': {},
              'user_metadata': {},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(sdk.dispose);
      var callbackOrigin = 'https://other.fixture.invalid';
      String? challenge;
      final calls = <String>[];
      final code = 'a' * 43;
      final broker = MockClient((request) async {
        expect(request.headers['authorization'], isNull);
        final step = request.url.path.split('/').last;
        calls.add(step);
        final body = jsonDecode(request.body) as Map;
        Object result;
        switch (step) {
          case 'options':
            expect(
              body['redirectUri'],
              'https://app.fixture.invalid/app/google-auth',
            );
            expect(body['organization'], backend.organizationId);
            challenge = body['codeChallenge'] as String;
            result = {
              'challenge_id': 'fixture-challenge',
              'options': {'challenge': 'AQID'},
            };
          case 'verify':
            expect(body['challengeId'], 'fixture-challenge');
            expect(body['credential']['id'], 'fixture-credential');
            result = {
              'callback': '$callbackOrigin/app/google-auth?passkey_code=$code',
            };
          case 'exchange':
            expect(body['code'], code);
            expect(body['clientId'], 'fixture-web');
            expect(
              base64Url
                  .encode(
                    sha256
                        .convert(utf8.encode(body['codeVerifier'] as String))
                        .bytes,
                  )
                  .replaceAll('=', ''),
              challenge,
            );
            result = {
              'organization': backend.organizationId,
              'userId': userId,
              'session': {
                'access_token': accessToken,
                'refresh_token': 'fixture-refresh',
              },
            };
          default:
            throw StateError('Unexpected passkey step $step');
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = AccountMfaSettingsService(
        backend,
        sdk,
        broker,
        'fixture-web',
        origin: 'https://app.fixture.invalid',
      );
      addTearDown(service.dispose);

      await expectLater(
        service.signInWithPasskey(isActive: () => active),
        throwsA(isA<AuthException>()),
      );
      expect(calls, ['options']);
      expect(sdk.auth.currentSession, isNull);
      active = true;
      cancelInBrowser = false;
      await expectLater(
        service.signInWithPasskey(isActive: () => active),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            'invalid_auth_handoff',
          ),
        ),
      );
      expect(calls, ['options', 'options', 'verify']);
      expect(sdk.auth.currentSession, isNull);
      callbackOrigin = 'https://app.fixture.invalid';
      final session = await service.signInWithPasskey(isActive: () => true);
      expect(session.user.id, userId);
      expect(sdk.auth.currentSession?.accessToken, accessToken);
      expect(calls, [
        'options',
        'options',
        'verify',
        'options',
        'verify',
        'exchange',
      ]);
    },
  );

  test('assertion and creation require local verification on both browser API variants', () async {
    final original = globalContext['PublicKeyCredential'];
    final credentials = web.window.navigator.credentials;
    final originalGet = credentials['get'];
    final originalCreate = credentials['create'];
    addTearDown(() {
      globalContext['PublicKeyCredential'] = original;
      credentials['get'] = originalGet;
      credentials['create'] = originalCreate;
    });
    final bytes = Uint8List.fromList([1, 2, 3]);
    final raw = bytes.toJS;
    final buffer = bytes.buffer.toJS;
    final options = {
      'challenge': 'AQID',
      'rpId': 'localhost',
      'userVerification': 'preferred',
      'allowCredentials': [
        {'id': 'AQID', 'type': 'public-key'},
      ],
    };
    for (final modern in [true, false]) {
      var parserUsed = false;
      final constructor = JSObject();
      if (modern) {
        constructor['parseRequestOptionsFromJSON'] = ((JSObject request) {
          parserUsed = true;
          expect(request['userVerification'].dartify(), 'required');
          expect(request['challenge'].dartify(), 'AQID');
          return {
                'challenge': raw,
                'rpId': 'localhost',
                'userVerification': 'required',
                'allowCredentials': [
                  {'id': raw, 'type': 'public-key'},
                ],
              }.jsify()
              as JSObject;
        }).toJS;
      }
      globalContext['PublicKeyCredential'] = constructor;

      final credential =
          {
                'id': 'AQID',
                'type': 'public-key',
                'rawId': buffer,
                'authenticatorAttachment': 'platform',
                'response': {
                  'authenticatorData': buffer,
                  'clientDataJSON': buffer,
                  'signature': buffer,
                  'userHandle': null,
                },
              }.jsify()
              as JSObject;
      credential['getClientExtensionResults'] = (() => JSObject()).toJS;
      if (modern) {
        credential['toJSON'] =
            (() =>
                    {
                          'id': 'AQID',
                          'response': {'signature': 'AQID', 'userHandle': null},
                        }.jsify()
                        as JSObject)
                .toJS;
      }
      credentials['get'] = ((JSObject request) {
        final publicKey = request['publicKey'] as JSObject;
        expect(publicKey['rpId'].dartify(), 'localhost');
        expect(publicKey['userVerification'].dartify(), 'required');
        expect((publicKey['challenge'] as JSUint8Array).toDart, [1, 2, 3]);
        final allowed =
            (publicKey['allowCredentials'] as JSArray<JSObject>).toDart;
        expect((allowed.single['id'] as JSUint8Array).toDart, [1, 2, 3]);
        return Future<JSObject?>.value(credential).toJS;
      }).toJS;

      expect(supportsWebAuthn, isTrue);
      final assertion = await takeWebAuthnAssertion(options);
      expect(parserUsed, modern);
      expect(assertion['id'], 'AQID');
      final response = assertion['response'] as Map;
      expect(response['signature'], 'AQID');
      expect(response['userHandle'], isNull);
      if (!modern) {
        expect(assertion['rawId'], 'AQID');
        expect(response['clientDataJSON'], 'AQID');
      }

      final creationOptions = {
        'challenge': 'AQID',
        'user': {'id': 'AQID', 'name': 'fixture'},
        'authenticatorSelection': {
          'userVerification': 'preferred',
          'residentKey': 'required',
        },
        'excludeCredentials': [
          {'id': 'AQID', 'type': 'public-key'},
        ],
      };
      var creationParserUsed = false;
      if (modern) {
        constructor['parseCreationOptionsFromJSON'] = ((JSObject request) {
          creationParserUsed = true;
          final selection = request['authenticatorSelection'] as JSObject;
          expect(selection['userVerification'].dartify(), 'required');
          expect(selection['residentKey'].dartify(), 'required');
          return {
                'challenge': raw,
                'user': {'id': raw},
                'authenticatorSelection': selection,
                'excludeCredentials': [
                  {'id': raw},
                ],
              }.jsify()
              as JSObject;
        }).toJS;
        credential['toJSON'] =
            (() =>
                    {
                          'id': 'AQID',
                          'response': {'attestationObject': 'AQID'},
                        }.jsify()
                        as JSObject)
                .toJS;
      }
      credential['response'] = {
        'attestationObject': buffer,
        'clientDataJSON': buffer,
      }.jsify();
      credentials['create'] = ((JSObject request) {
        final publicKey = request['publicKey'] as JSObject;
        final selection = publicKey['authenticatorSelection'] as JSObject;
        final user = publicKey['user'] as JSObject;
        expect(selection['userVerification'].dartify(), 'required');
        expect(selection['residentKey'].dartify(), 'required');
        expect((user['id'] as JSUint8Array).toDart, [1, 2, 3]);
        final excluded =
            (publicKey['excludeCredentials'] as JSArray<JSObject>).toDart;
        expect((excluded.single['id'] as JSUint8Array).toDart, [1, 2, 3]);
        return Future<JSObject?>.value(credential).toJS;
      }).toJS;
      final created = await createWebAuthnCredential(creationOptions);
      expect(creationParserUsed, modern);
      expect(created['id'], 'AQID');
      expect((created['response'] as Map)['attestationObject'], 'AQID');
    }
  });
}

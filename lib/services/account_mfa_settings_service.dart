import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/services/backend_activation_service.dart';
import 'package:fstapp/services/google_auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_webauthn_browser_stub.dart'
    if (dart.library.js_interop) 'account_webauthn_browser_web.dart';

class TotpSetup {
  const TotpSetup({
    required this.session,
    required this.receipt,
    required this.factorId,
    required this.uri,
    required this.secret,
    required this.recovery,
  });

  final Session session;
  final String receipt;
  final String factorId;
  final String uri;
  final String secret;
  final bool recovery;
}

class AccountMfaSettingsService {
  static ResolvedBackend? _backend;

  static void configure(ResolvedBackend backend) => _backend = backend;

  static bool get supportsChannel =>
      _backend != null &&
      (kIsWeb ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  static bool get supportsWebAuthnVerification =>
      supportsChannel && supportsWebAuthn;

  AccountMfaSettingsService(
    ResolvedBackend backend,
    this._client,
    this._http,
    this._clientId, {
    required String origin,
  }) : _endpoint = Uri.parse(backend.supabaseUrl),
       _anonKey = backend.anonKey,
       _origin = origin,
       _organization = backend.organizationId,
       _actor = _client.auth.currentUser?.id,
       _callback = Uri.parse(origin).resolve('/app/google-auth');

  static AccountMfaSettingsService open() => AccountMfaSettingsService(
    _backend!,
    Supabase.instance.client,
    http.Client(),
    GoogleAuthService.clientId,
    origin: kIsWeb ? Uri.base.origin : Uri.parse(AppConfig.webLink).origin,
  );

  final SupabaseClient _client;
  final http.Client _http;
  final Uri _endpoint;
  final String _anonKey;
  final String _origin;
  final String _clientId;
  final int _organization;
  final String? _actor;
  final Uri _callback;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _http.close();
  }

  Session _session([Session? expected]) {
    final current = _client.auth.currentSession;
    if (_disposed ||
        current == null ||
        current.user.id != _actor ||
        AppConfig.organization != _organization ||
        (expected != null && expected.accessToken != current.accessToken)) {
      throw const AuthException('invalid_session');
    }
    return current;
  }

  void _requireRequestScope(Session? session, bool anonymous) {
    if (!anonymous) {
      _session(session);
    } else if (_disposed ||
        _actor != null ||
        _client.auth.currentSession != null ||
        AppConfig.organization != _organization) {
      throw const AuthException('invalid_session');
    }
  }

  Future<Map<String, dynamic>> _request(
    String operation, {
    Map<String, Object?>? data,
    Session? session,
    Map<String, String>? query,
    bool provider = false,
    bool anonymous = false,
  }) async {
    _requireRequestScope(session, anonymous);
    final path = _endpoint.resolve(
      '/auth/v1/${provider ? '' : 'festapp/mfa/'}$operation',
    );
    final uri = query == null ? path : path.replace(queryParameters: query);
    final request = http.Request(data == null ? 'GET' : 'POST', uri)
      ..followRedirects = false
      ..headers.addAll({
        if (!kIsWeb) 'Origin': _origin,
        if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
        if (session != null) 'apikey': _anonKey,
        if (data != null) 'Content-Type': 'application/json',
      });
    if (data != null) request.body = jsonEncode(data);
    final response = await http.Response.fromStream(await _http.send(request))
        .timeout(const Duration(seconds: 12));
    _requireRequestScope(session, anonymous);
    final result = jsonDecode(response.body);
    if (result is! Map) throw const AuthException('invalid_mfa_response');
    if (response.statusCode != 200) {
      throw AuthException(result['code']?.toString() ?? 'mfa_operation_failed');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, dynamic>> _channel({bool anonymous = false, Session? session}) => _request(
    'channel',
    anonymous: anonymous,
    session: session,
    query: {
      'client_id': _clientId,
      'organization': '$_organization',
      'redirect_uri': _callback.toString(),
    },
  );

  Future<({Set<String> registrationMethods, List<Factor> factors})>
  load() async {
    final session = _session();
    final user = await _client.auth.getUser(session.accessToken);
    _session(session);
    if (user.user?.id != _actor) throw const AuthException('invalid_session');
    final factors = (user.user!.factors ?? [])
        .where((factor) => factor.status == FactorStatus.verified)
        .toList();
    final registrationMethods = <String>{};
    try {
      final channel = await _channel(session: session);
      for (final method in [
        'totp',
        if (supportsWebAuthnCreation) ...['webauthn', 'passkey'],
      ]) {
        final flags = channel['methods']?[method];
        if (flags?['offer'] == true && flags?['registration'] == true) {
          registrationMethods.add(method);
        }
      }
    } catch (_) {
      _session(session);
    }
    _session(session);
    return (registrationMethods: registrationMethods, factors: factors);
  }

  static Future<bool> passkeySignInAvailable() async {
    if (!supportsWebAuthnVerification) return false;
    final service = open();
    try {
      final channel = await service._channel(anonymous: true);
      return channel['methods']?['passkey']?['offer'] == true &&
          channel['methods']?['passkey']?['signIn'] == true;
    } catch (_) {
      return false;
    } finally {
      service.dispose();
    }
  }

  Future<Session> signInWithPasskey({required bool Function() isActive}) async {
    if (!supportsWebAuthnVerification || !isActive()) {
      throw const AuthException('passkey_operation_unavailable');
    }
    final proof = _pkce();
    final signIn = 'festapp/passkey/sign-in';
    final options = await _request(
      '$signIn/options',
      provider: true,
      anonymous: true,
      data: {
        'clientId': _clientId,
        'organization': _organization,
        'redirectUri': _callback.toString(),
        'codeChallenge': proof.challenge,
      },
    );
    if (!isActive()) throw const AuthException('invalid_session');
    final credential = await takeWebAuthnAssertion(
      Map<String, Object?>.from(options['options'] as Map),
    );
    if (!isActive()) throw const AuthException('invalid_session');
    final verification = await _request(
      '$signIn/verify',
      provider: true,
      anonymous: true,
      data: {'challengeId': options['challenge_id'], 'credential': credential},
    );
    final code = _handoffCode(verification, 'passkey_code');
    if (!isActive()) throw const AuthException('invalid_session');
    final result = await _request(
      '$signIn/exchange',
      provider: true,
      anonymous: true,
      data: {
        'clientId': _clientId,
        'organization': _organization,
        'code': code,
        'codeVerifier': proof.verifier,
      },
    );
    final userId = result['userId'];
    final tokens = result['session'];
    if (!isActive() ||
        result['organization'] != _organization ||
        userId is! String ||
        tokens is! Map) {
      throw const AuthException('invalid_session');
    }
    final installed = (await _client.auth.setSession(
      tokens['refresh_token'] as String,
      accessToken: tokens['access_token'] as String,
    )).session;
    if (installed?.user.id != userId ||
        _client.auth.currentSession?.accessToken != installed?.accessToken ||
        AppConfig.organization != _organization) {
      throw const AuthException('invalid_session');
    }
    if (!isActive()) {
      await _client.auth.signOut(scope: SignOutScope.local);
      throw const AuthException('invalid_session');
    }
    return installed!;
  }

  Future<Session> _fresh() async {
    final session = _session();
    final decision = await _client.rpc(
      'get_account_assurance_v1',
      params: {'p_organization': _organization, 'p_account_security': true},
    );
    _session(session);
    if (decision == 'allowed') return session;
    if (decision == 'proof_required' || decision == 'mfa_required') {
      throw const AuthException('proof_required');
    }
    throw const AuthException('invalid_session');
  }

  Future<void> reauthenticateWithPassword(String password) async {
    final session = _session();
    final email = session.user.email;
    if (email == null) throw const AuthException('proof_required');
    final result = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (result.user?.id != _actor) throw const AuthException('invalid_session');
    await _fresh();
    await AuthService.authorizePrivateCache();
  }

  Future<void> reauthenticateWithTotp(String factorId, String code) async {
    final session = _session();
    final result = await _client.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code,
    );
    if (_session().accessToken != result.accessToken ||
        session.user.id != _actor) {
      throw const AuthException('invalid_session');
    }
    await _fresh();
    await AuthService.authorizePrivateCache();
  }

  Future<void> reauthenticateWithWebAuthn(Factor factor) async {
    final session = await verifyWebAuthnFactor(factor, _session());
    await _fresh();
    await AuthService.authorizePrivateCache();
    _session(session);
  }

  Future<({Session session, String receipt})> _registrationReceipt(
    String method, {
    String? recoveryCode,
  }) async {
    final recovery = recoveryCode != null;
    if (recoveryCode != null &&
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(recoveryCode)) {
      throw const AuthException('invalid_recovery_code');
    }
    final session = recovery ? _session() : await _fresh();
    final proof = _pkce();
    final start = await _request(
      'registration/start',
      session: session,
      data: {
        'clientId': _clientId,
        'organization': _organization,
        'redirectUri': _callback.toString(),
        'method': method,
        'codeChallenge': proof.challenge,
        'inPlace': true,
        if (recovery) 'recoveryCode': recoveryCode,
      },
    );
    final code = _handoffCode(start, 'mfa_code');
    final claim = await _request(
      'registration/claim',
      session: session,
      data: {
        'organization': _organization,
        'code': code,
        'codeVerifier': proof.verifier,
        if (recovery) 'recovery': true,
      },
    );
    final receipt = claim['id'] as String;
    if (claim['method'] != method) {
      throw const AuthException('invalid_mfa_handoff');
    }
    return (session: session, receipt: receipt);
  }

  ({String verifier, String challenge}) _pkce() {
    final random = Random.secure();
    final verifier = base64UrlEncode(
      List.generate(32, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    return (verifier: verifier, challenge: challenge);
  }

  String _handoffCode(Map<String, dynamic> result, String parameter) {
    final callback = Uri.tryParse(result['callback']?.toString() ?? '');
    final code = callback?.queryParameters[parameter];
    if (callback == null ||
        code == null ||
        callback.queryParametersAll.length != 1 ||
        callback.queryParametersAll[parameter]!.length != 1 ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(code) ||
        callback
                .replace(query: '')
                .toString()
                .replaceFirst(RegExp(r'\?$'), '') !=
            _callback.toString()) {
      throw const AuthException('invalid_auth_handoff');
    }
    return code;
  }

  Future<TotpSetup> enrollTotp({String? recoveryCode}) async {
    final recovery = recoveryCode != null;
    final registration = await _registrationReceipt(
      'totp',
      recoveryCode: recoveryCode,
    );
    final factor = await _request(
      'totp/enroll',
      session: registration.session,
      data: {'receipt': registration.receipt, if (recovery) 'recovery': true},
    );
    return TotpSetup(
      session: registration.session,
      receipt: registration.receipt,
      factorId: factor['id'] as String,
      uri: factor['totp']['uri'] as String,
      secret: factor['totp']['secret'] as String,
      recovery: recovery,
    );
  }

  Future<void> enrollWebAuthn({String? recoveryCode}) async {
    if (!supportsWebAuthnCreation) {
      throw const AuthException('invalid_webauthn_challenge');
    }
    final registration = await _registrationReceipt(
      'webauthn',
      recoveryCode: recoveryCode,
    );
    final session = registration.session;
    final scope = <String, Object?>{
      'receipt': registration.receipt,
      if (recoveryCode != null) 'recovery': true,
    };
    final factor = await _request(
      'webauthn/enroll',
      session: session,
      data: scope,
    );
    scope['factorId'] = factor['id'];
    final challenge = await _request(
      'webauthn/challenge',
      session: session,
      data: scope,
    );
    final options = _webAuthnChallenge(challenge, 'create');
    final credential = await createWebAuthnCredential(options);
    final verified = await _request(
      'webauthn/verify',
      session: session,
      data: {
        ...scope,
        'challengeId': challenge['id'],
        'credential': credential,
      },
    );
    final installed = await _installProof(session, verified);
    await _checkEnrollmentSession(installed, recovery: recoveryCode != null);
  }

  Future<void> enrollPasskey() async {
    if (!supportsWebAuthnCreation) {
      throw const AuthException('invalid_webauthn_challenge');
    }
    final registration = await _registrationReceipt('passkey');
    final session = registration.session;
    final scope = {'receipt': registration.receipt};
    final options = await _request(
      'festapp/passkey/registration/options',
      provider: true,
      session: session,
      data: scope,
    );
    final credential = await createWebAuthnCredential(
      Map<String, Object?>.from(options['options'] as Map),
    );
    await _request(
      'festapp/passkey/registration/verify',
      provider: true,
      session: session,
      data: {
        ...scope,
        'challengeId': options['challenge_id'],
        'credential': credential,
      },
    );
  }

  Future<void> verifyTotp(TotpSetup setup, String code) async {
    final result = await _request(
      'totp/verify',
      session: setup.session,
      data: {
        'receipt': setup.receipt,
        'factorId': setup.factorId,
        'code': code,
        if (setup.recovery) 'recovery': true,
      },
    );
    final verifiedSession = await _installProof(setup.session, result);
    await _checkEnrollmentSession(verifiedSession, recovery: setup.recovery);
  }

  Future<void> _checkEnrollmentSession(
    Session session, {
    required bool recovery,
  }) async {
    _session(session);
    if (recovery) {
      final decision = await _client.rpc(
        'get_account_assurance_v1',
        params: {'p_organization': _organization},
      );
      if (decision != 'account_recovery') {
        throw const AuthException('invalid_session');
      }
    } else if (!await AuthService.authorizePrivateCache()) {
      throw const AuthException('invalid_session');
    }
    _session(session);
  }

  Future<Session> verifyWebAuthnFactor(Factor factor, Session session) async {
    final path = 'factors/${Uri.encodeComponent(factor.id)}';
    final challenge = await _request(
      '$path/challenge',
      session: session,
      data: {},
      provider: true,
    );
    final assertion = await takeWebAuthnAssertion(
      _webAuthnChallenge(challenge, 'request'),
    );
    final verified = await _request(
      '$path/verify',
      session: session,
      provider: true,
      data: {
        'challenge_id': challenge['id'],
        'webauthn': {'type': 'request', 'credential_response': assertion},
      },
    );
    return _installProof(session, verified);
  }

  Map<String, Object?> _webAuthnChallenge(
    Map<String, dynamic> challenge,
    String type,
  ) {
    final webauthn = challenge['webauthn'];
    final options =
        webauthn is Map &&
            webauthn['type'] == type &&
            webauthn['credential_options'] is Map
        ? webauthn['credential_options']['publicKey']
        : null;
    if (options is! Map) {
      throw const AuthException('invalid_webauthn_challenge');
    }
    return Map<String, Object?>.from(options);
  }

  Future<Session> _installProof(
    Session previous,
    Map<String, dynamic> result,
  ) async {
    _session(previous);
    final installed = await _client.auth.setSession(
      result['refresh_token'] as String,
      accessToken: result['access_token'] as String,
    );
    final verifiedSession = installed.session;
    if (verifiedSession == null || installed.user?.id != _actor) {
      throw const AuthException('invalid_session');
    }
    return _session(verifiedSession);
  }

  Future<bool> remove(Factor factor, {required bool confirmDisable}) async {
    final session = await _fresh();
    final result = await _request(
      'factors/remove',
      session: session,
      data: {'factorId': factor.id, 'confirmDisable': confirmDisable},
    );
    if (result['removed'] != true) {
      throw const AuthException('mfa_operation_failed');
    }
    return result['revokesSession'] == true;
  }
}

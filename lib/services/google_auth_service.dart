import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'google_auth_browser_stub.dart'
    if (dart.library.js_interop) 'google_auth_browser_web.dart';

enum GoogleLoginStatus {
  idle,
  openingGoogle,
  completing,
  needsAccountProof,
  needsProfile,
  needsMfa,
  authenticated,
  cancelled,
  retryableError
}

class GoogleLoginState {
  final GoogleLoginStatus status;
  final Map<String, dynamic> result;
  final String? error;
  const GoogleLoginState(this.status, {this.result = const {}, this.error});
}

class GoogleAuthService {
  static final state =
      ValueNotifier(const GoogleLoginState(GoogleLoginStatus.idle));
  static const _storage = FlutterSecureStorage();
  static const _key = 'festapp-google-attempt-v1';
  static Map<String, dynamic>? _pending;
  static Uri? _callback;
  static Future<void>? _flight;
  static StreamSubscription<Uri>? _links;
  static bool navigationClaimed = false;
  static String? _lastCallback;
  static AppLifecycleListener? _lifecycle;
  static String get _origin =>
      kIsWeb ? Uri.base.origin : Uri.parse(AppConfig.webLink).origin;
  static String get _platform => kIsWeb
      ? 'flutter-web'
      : defaultTargetPlatform == TargetPlatform.android
          ? 'android'
          : 'ios';
  static String get clientId => '${AppConfig.organization}:$_platform:$_origin';
  static String _secret() =>
      base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)))
          .replaceAll('=', '');
  static String _hash(String value) =>
      base64UrlEncode(sha256.convert(utf8.encode(value)).bytes)
          .replaceAll('=', '');
  static Future<void> initializeLinks() async {
    if (kIsWeb) {
      _callback = consumeGoogleBrowserCallback();
      _lastCallback = _callback?.toString();
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    final cached = await _storage.read(key: _key);
    if (cached != null) {
      try {
        if ((jsonDecode(cached) as Map)['expires'] <=
            DateTime.now().millisecondsSinceEpoch) {
          await _storage.delete(key: _key);
        }
      } catch (_) {
        await _storage.delete(key: _key);
      }
    }
    _lifecycle ??= AppLifecycleListener(onResume: () {
      Future<void>.delayed(const Duration(seconds: 1), () {
        if (!hasCallback &&
            state.value.status == GoogleLoginStatus.openingGoogle) {
          state.value = const GoogleLoginState(GoogleLoginStatus.cancelled,
              error: 'provider_cancelled');
        }
      });
    });
    final links = AppLinks();
    final initial = await links.getInitialLink();
    if (initial != null) captureCallback(initial);
    _links ??= links.uriLinkStream.listen((uri) {
      if (uri.toString() == _lastCallback || !captureCallback(uri)) {
        return;
      }
      final route = RouterService.router.current.name;
      if (route != LoginRoute.name && route != SignupRoute.name) {
        RouterService.router.pushPath('/login');
      }
    });
  }

  static bool captureCallback(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.origin != Uri.parse(AppConfig.webLink).origin ||
        uri.path != '/app/google-auth' ||
        (!uri.queryParameters.containsKey('google_code') &&
            !uri.queryParameters.containsKey('google_error'))) {
      return false;
    }
    if (_lastCallback == uri.toString()) {
      return true;
    }
    _lastCallback = uri.toString();
    _callback = uri;
    state.value = const GoogleLoginState(GoogleLoginStatus.completing);
    return true;
  }

  static bool get hasCallback => _callback != null;
  static Future<Map<String, dynamic>> _request(
      String endpoint, Map<String, dynamic> body) async {
    late FunctionResponse response;
    try {
      response = await Supabase.instance.client.functions.invoke(
          'google-auth-$endpoint',
          body: {
            ...body,
            'organization': AppConfig.organization,
            'clientId': clientId
          },
          headers: kIsWeb ? null : {'Origin': _origin});
    } on FunctionException catch (error) {
      final details = error.details;
      throw AuthException(details is Map
          ? details['error']?.toString() ?? 'auth_temporarily_unavailable'
          : 'auth_temporarily_unavailable');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) throw AuthException(data['error'].toString());
    return data;
  }

  static Future<Map<String, dynamic>> identityStatus() =>
      _request('start', {'operation': 'identity_status'});
  static Future<bool> capability() async {
    try {
      return (await _request(
              'start', {'operation': 'capability'}))['enabled'] ==
          true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> start({String intent = 'login'}) async {
    if (_flight != null) return _flight;
    navigationClaimed = false;
    state.value = const GoogleLoginState(GoogleLoginStatus.openingGoogle);
    final returnPath =
        safeReturnPath(RouterService.getCurrentBrowserUri().path);
    _flight = _start(intent, returnPath).catchError((Object error) {
      _error(error);
    }).whenComplete(() => _flight = null);
    return _flight;
  }

  static Future<void> _start(String intent, String returnPath) async {
    final verifier = _secret();
    final response = await _request(
        'start', {'challenge': _hash(verifier), 'intent': intent});
    final destination = Uri.parse(response['url'] as String);
    if (destination.scheme != 'https' ||
        destination.path != '/functions/v1/google-auth-start' ||
        destination.origin !=
            Supabase.instance.client.rest.url.split('/rest/v1').first) {
      throw const AuthException('invalid_provider_proof');
    }
    _pending = {
      'returnPath': returnPath,
      'attempt': response['attempt'],
      'verifier': verifier,
      'expires':
          DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch
    };
    final encoded = jsonEncode(_pending);
    if (kIsWeb) {
      writeGoogleBrowserAttempt(encoded);
    } else {
      await _storage.write(key: _key, value: encoded);
    }
    final opened = await launchUrl(destination,
        mode: LaunchMode.externalApplication, webOnlyWindowName: '_self');
    if (!opened) throw const AuthException('auth_temporarily_unavailable');
  }

  static Future<void> finishPending() async {
    if (_callback == null || _flight != null) return;
    final callback = _callback!;
    _callback = null;
    state.value = const GoogleLoginState(GoogleLoginStatus.completing);
    _flight = _finish(callback).catchError((Object error) {
      _error(error);
    }).whenComplete(() => _flight = null);
    await _flight;
  }

  static Future<void> _finish(Uri callback) async {
    final encoded =
        kIsWeb ? readGoogleBrowserAttempt() : await _storage.read(key: _key);
    if (kIsWeb) {
      clearGoogleBrowserAttempt();
    } else {
      await _storage.delete(key: _key);
    }
    final error = callback.queryParameters['google_error'];
    if (error != null) {
      throw AuthException(error == 'provider_cancelled'
          ? 'provider_cancelled'
          : 'invalid_provider_proof');
    }
    if (encoded == null) throw const AuthException('attempt_expired');
    _pending = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
    if (_pending!['expires'] <= DateTime.now().millisecondsSinceEpoch ||
        _pending!['attempt'] != callback.queryParameters['google_attempt']) {
      throw const AuthException('attempt_expired');
    }
    await _accept(await _request('complete', {
      ..._pending!,
      'operation': 'claim',
      'code': callback.queryParameters['google_code']
    }));
  }

  static Future<void> advance(
      String operation, Map<String, dynamic> data) async {
    if (_flight != null) return _flight;
    _flight = _advance(operation, data).catchError((Object error) {
      _error(error);
    }).whenComplete(() => _flight = null);
    await _flight;
  }

  static Future<void> _advance(
      String operation, Map<String, dynamic> data) async {
    if (_pending == null ||
        _pending!['expires'] <= DateTime.now().millisecondsSinceEpoch) {
      throw const AuthException('attempt_expired');
    }
    final previous = state.value;
    state.value =
        GoogleLoginState(GoogleLoginStatus.completing, result: previous.result);
    await _accept(await _request(
        'complete', {..._pending!, 'operation': operation, ...data}));
  }

  static Future<void> _accept(Map<String, dynamic> result) async {
    if (result['status'] == 'authenticated' || result['status'] == 'unlinked') {
      if (result['status'] == 'authenticated') {
        await AuthService.completeExternalLogin(result);
      }
      final returnPath = _pending?['returnPath'];
      _pending = null;
      state.value = GoogleLoginState(GoogleLoginStatus.authenticated,
          result: {...result, 'returnPath': returnPath});
      return;
    }
    _pending!['continuation'] = result['continuation'];
    state.value = GoogleLoginState(
        result['status'] == 'needs_mfa'
            ? GoogleLoginStatus.needsMfa
            : result['status'] == 'needs_profile'
                ? GoogleLoginStatus.needsProfile
                : GoogleLoginStatus.needsAccountProof,
        result: result);
  }

  static void showAccountProof() {
    state.value = GoogleLoginState(GoogleLoginStatus.needsAccountProof,
        result: {...state.value.result, 'status': 'needs_account_proof'});
  }

  static String safeReturnPath(String value) =>
      RegExp(r'^/(?!/)[A-Za-z0-9/_-]*$').hasMatch(value) &&
              !value.contains('..')
          ? value
          : '/';
  static bool get isContinuation =>
      state.value.status == GoogleLoginStatus.openingGoogle ||
      state.value.status == GoogleLoginStatus.completing ||
      state.value.status == GoogleLoginStatus.needsAccountProof ||
      state.value.status == GoogleLoginStatus.needsProfile ||
      state.value.status == GoogleLoginStatus.needsMfa ||
      (state.value.status == GoogleLoginStatus.retryableError &&
          state.value.result.isNotEmpty);
  static void _error(Object error) {
    final code =
        error is AuthException ? error.message : 'auth_temporarily_unavailable';
    state.value = GoogleLoginState(
        code == 'provider_cancelled'
            ? GoogleLoginStatus.cancelled
            : GoogleLoginStatus.retryableError,
        result: state.value.result,
        error: code);
  }
}

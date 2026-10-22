import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/app_config.dart';

/// Native payment capabilities never enter a route, log or persistent store.
/// Return scope remains read-only; handoff belongs to the top-level web client.
class StripePaymentLinkInbox {
  StripePaymentLinkInbox(this.tenantOrigin);
  final Uri tenantOrigin;
  Map<String, String>? _pending;
  String? get pendingRoute =>
      _pending == null ? null : '/stripe/${_pending!['kind']}';

  static String? routeForPath(String path) => switch (path) {
        '/stripe/pay' || '/app/stripe/pay' => '/stripe/pay',
        '/stripe/return' || '/app/stripe/return' => '/stripe/return',
        _ => null,
      };

  bool capture(Uri uri) {
    final route = routeForPath(uri.path);
    if (route == null ||
        uri.scheme != 'https' ||
        tenantOrigin.scheme != 'https' ||
        uri.origin != tenantOrigin.origin ||
        uri.userInfo.isNotEmpty) return false;
    final kind = route.endsWith('/return') ? 'return' : 'pay';
    // Accept only the canonical server-issued shape, never ambiguous scopes,
    // duplicate parameters, credentials, or a write token on the return path.
    final String token;
    if (kind == 'pay') {
      if (uri.hasQuery || !RegExp(r'^pay=[a-f0-9]{64}$').hasMatch(uri.fragment))
        return false;
      token = uri.fragment.substring(4);
    } else {
      if (uri.hasFragment ||
          !RegExp(r'^return_handle=[a-f0-9]{64}$').hasMatch(uri.query))
        return false;
      token = uri.query.substring('return_handle='.length);
    }
    if (_pending?['kind'] == kind && _pending?['token'] == token) return false;
    _pending = {'kind': kind, 'token': token};
    return true;
  }

  Map<String, String>? consume({String? expectedKind}) {
    if (expectedKind != null && _pending?['kind'] != expectedKind) return null;
    final value = _pending;
    _pending = null;
    return value;
  }
}

class StripePaymentLinkService {
  static final inbox = StripePaymentLinkInbox(Uri.parse(AppConfig.webLink));
  static final revision = ValueNotifier<int>(0);
  static StreamSubscription<Uri>? _subscription;
  static Future<void> Function(String)? _navigate;
  static String? _queuedRoute;
  static bool get isNativeMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> initialize() async {
    if (!isNativeMobile) return;
    final links = AppLinks();
    // Android disables Flutter's native link handler and uses AppLinks.
    // iOS retains its existing universal-link AutoRoute owner; subscribing there
    // as well would deliver each resumed link twice and affect unrelated routes.
    if (defaultTargetPlatform == TargetPlatform.android)
      _subscription ??= links.uriLinkStream.listen((uri) {
        if (!capture(uri)) return;
        _dispatchQueued();
      }, onError: (Object _) {/* Never log an OS-delivered capability. */});
    final initial = await links.getInitialLink();
    if (initial != null && inbox.pendingRoute == null) {
      capture(initial);
      _dispatchQueued();
    }
  }

  static void _dispatchQueued() {
    final route = _queuedRoute, navigate = _navigate;
    if (route == null || navigate == null) return;
    _queuedRoute = null;
    unawaited(navigate(route).catchError((Object _) {}));
  }

  static bool capture(Uri uri) {
    if (!isNativeMobile || !inbox.capture(uri)) return false;
    _queuedRoute = inbox.pendingRoute;
    revision.value++;
    return true;
  }

  static void attachNavigator(
      Future<void> Function(String) navigate, String initialRoute) {
    _navigate = navigate;
    final route = _queuedRoute;
    _queuedRoute = null;
    if (route != null && route != initialRoute)
      unawaited(navigate(route).catchError((Object _) {}));
  }

  static void detachNavigator() => _navigate = null;
}

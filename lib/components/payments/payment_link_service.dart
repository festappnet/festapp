import 'package:festapp_core/payments.dart';

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/app_config.dart';

/// Native payment capabilities never enter a route, log or persistent store.
/// Return scope remains read-only; handoff belongs to the top-level web client.
class PaymentLinkInbox {
  PaymentLinkInbox(this.tenantOrigin, {PaymentConnectorRegistry? registry})
    : registry = registry ?? paymentConnectors;
  final PaymentConnectorRegistry registry;
  String? _pendingRoute;
  final Uri tenantOrigin;
  Map<String, String>? _pending;
  String? get pendingRoute => _pending == null ? null : _pendingRoute;

  static String? routeForPath(String path) {
    final canonical = path.startsWith('/app/') ? path.substring(4) : path;
    for (final connector in paymentConnectors.hosted) {
      if ([
        connector.payPath,
        connector.returnPath,
        '/payments/${connector.id}/pay',
        '/payments/${connector.id}/return',
      ].contains(canonical))
        return canonical;
    }
    return null;
  }

  PaymentConnector? _connector(String path) {
    final canonical = path.startsWith('/app/') ? path.substring(4) : path;
    for (final connector in registry.hosted) {
      if ([
        connector.payPath,
        connector.returnPath,
        '/payments/${connector.id}/pay',
        '/payments/${connector.id}/return',
      ].contains(canonical))
        return connector;
    }
    return null;
  }

  bool capture(Uri uri) {
    final connector = _connector(uri.path);
    final route = connector == null
        ? null
        : (uri.path.startsWith('/app/') ? uri.path.substring(4) : uri.path);
    if (route == null ||
        uri.scheme != 'https' ||
        tenantOrigin.scheme != 'https' ||
        uri.origin != tenantOrigin.origin ||
        uri.userInfo.isNotEmpty)
      return false;
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
    if (_pending?['kind'] == kind &&
        _pending?['token'] == token &&
        _pending?['provider'] == connector!.id)
      return false;
    _pending = {'provider': connector!.id, 'kind': kind, 'token': token};
    _pendingRoute = route;
    return true;
  }

  Map<String, String>? consume({
    String? expectedKind,
    String? expectedProvider,
  }) {
    if (expectedKind != null && _pending?['kind'] != expectedKind) return null;
    if (expectedProvider != null && _pending?['provider'] != expectedProvider)
      return null;
    final value = _pending;
    _pending = null;
    return value;
  }
}

class PaymentLinkService {
  static final inbox = PaymentLinkInbox(Uri.parse(AppConfig.webLink));
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
      _subscription ??= links.uriLinkStream.listen(
        (uri) {
          if (!capture(uri)) return;
          _dispatchQueued();
        },
        onError: (Object _) {
          /* Never log an OS-delivered capability. */
        },
      );
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
    Future<void> Function(String) navigate,
    String initialRoute,
  ) {
    _navigate = navigate;
    final route = _queuedRoute;
    _queuedRoute = null;
    if (route != null && route != initialRoute)
      unawaited(navigate(route).catchError((Object _) {}));
  }

  static void detachNavigator() => _navigate = null;
}

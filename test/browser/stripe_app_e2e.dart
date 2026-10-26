import 'dart:js_interop';
// Real Stripe app journeys against the task-owned HTTPS loopback Supabase proxy.
import 'package:flutter/widgets.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/main.dart' as app;

@JS('login')
external set _notificationLogin(JSFunction value);
@JS('logout')
external set _notificationLogout(JSFunction value);
@JS('tagCurrentSubscription')
external set _notificationTags(JSFunction value);

Future<void> main() async {
  final backend = Uri.parse(AppConfig.effectiveSupabaseUrl);
  if (backend.scheme != 'https' ||
      backend.host != '127.0.0.1' ||
      backend.port != 56584) {
    throw StateError(
        'Full-app E2E requires the isolated HTTPS backend on 56584');
  }
  // Notifications are an external production SDK, outside this local E2E.
  _notificationLogin = ((JSAny? _, JSFunction resolve, JSFunction reject) =>
      resolve.callAsFunction(null, null)).toJS;
  final complete = ((JSFunction resolve, JSFunction reject) =>
      resolve.callAsFunction(null, null)).toJS;
  _notificationLogout = complete;
  _notificationTags = complete;
  await app.main();
  WidgetsBinding.instance.ensureSemantics();
}

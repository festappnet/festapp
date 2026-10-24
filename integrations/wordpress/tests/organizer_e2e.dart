import 'dart:js_interop';
import 'package:flutter/widgets.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/main.dart' as app;
@JS('login')
external set _login(JSFunction value);
@JS('logout')
external set _logout(JSFunction value);
@JS('tagCurrentSubscription')
external set _tags(JSFunction value);
Future<void> main() async {
  final backend = Uri.parse(AppConfig.effectiveSupabaseUrl);
  if (backend.host != '127.0.0.1' || backend.port != 59821) {
    throw StateError('WordPress E2E requires its owned loopback backend');
  }
  _login = ((JSAny? _, JSFunction resolve, JSFunction reject) => resolve.callAsFunction(null, null)).toJS;
  final complete = ((JSFunction resolve, JSFunction reject) => resolve.callAsFunction(null, null)).toJS;
  _logout = complete;
  _tags = complete;
  await app.main();
  WidgetsBinding.instance.ensureSemantics();
}

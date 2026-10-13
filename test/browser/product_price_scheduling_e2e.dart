// Real application, local Auth/REST only. External push callbacks are stubbed.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/main.dart' as app;

Future<void> main() async {
  final backend = Uri.parse(AppConfig.effectiveSupabaseUrl);
  if (backend.host != '127.0.0.1' || backend.port != 56721) {
    throw StateError('Price E2E requires the disposable loopback backend');
  }
  AppConfig.organization = 1;
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.ensureSemantics();
  void resolve(JSFunction success, JSFunction failure) {
    success.callAsFunction(null, true.toJS);
  }

  globalContext['initializeOneSignal'] = resolve.toJS;
  globalContext['logout'] = resolve.toJS;
  globalContext['optIn'] = resolve.toJS;
  globalContext['optOut'] = resolve.toJS;
  globalContext['login'] =
      ((JSAny? user, JSFunction success, JSFunction failure) {
    success.callAsFunction(null, true.toJS);
  }).toJS;
  globalContext['addTags'] =
      ((JSAny? tags, JSFunction success, JSFunction failure) {
    success.callAsFunction(null, true.toJS);
  }).toJS;
  await app.main();
}

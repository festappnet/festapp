import 'dart:js_interop';
// The real app with synthetic local Supabase data and accessible headless UI.
import 'package:flutter/widgets.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/main.dart' as app;

@JS('login')
external set _notificationLogin(JSFunction value);
@JS('logout')
external set _notificationLogout(JSFunction value);
@JS('tagCurrentSubscription')
external set _notificationTags(JSFunction value);

@JS('globalThis.fetch')
external JSFunction get _fetch;
@JS('globalThis.fetch')
external set _fetch(JSFunction value);
@JS('globalThis.__festappE2EOriginalFetch')
external JSFunction? get _originalFetch;
@JS('globalThis.__festappE2EOriginalFetch')
external set _originalFetch(JSFunction? value);
@JS('globalThis')
external JSObject get _global;

// BrowserClient uses fetch. Flutter callbacks need not retain the bootstrap
// Zone, so route the E2E transport at the browser boundary, as the local JS host
// does. Public manifests and production URL validation remain unchanged.
void _routeLocalImages(int port) {
  _originalFetch ??= _fetch;
  final original = _originalFetch!;
  _fetch = ((JSAny? input, [JSAny? init]) {
    var forwarded = input;
    if (input != null && input.isA<JSString>()) {
      final uri = Uri.tryParse((input as JSString).toDart);
      final control = uri?.host == 'image-api.festapp.net';
      final image =
          const ['img.festapp.net', 'a.img.festapp.net'].contains(uri?.host);
      if (control || image) {
        if (uri!.scheme != 'https' || uri.userInfo.isNotEmpty) {
          throw StateError('Invalid image transport in local E2E');
        }
        forwarded = Uri(
                scheme: 'http',
                host: '127.0.0.1',
                port: port,
                path: image ? '/public${uri.path}' : uri.path,
                query: uri.query)
            .toString()
            .toJS;
      }
    }
    return original.callAsFunction(_global, forwarded, init);
  }).toJS;
}

Future<void> main() async {
  final backend = Uri.parse(AppConfig.effectiveSupabaseUrl);
  const port =
      int.fromEnvironment('FESTAPP_E2E_BACKEND_PORT', defaultValue: 56521);
  if (backend.host != '127.0.0.1' || backend.port != port) {
    throw StateError(
        'Full-app E2E requires the isolated local backend on $port');
  }
  // Notifications are an external production SDK, outside this local E2E.
  _notificationLogin = ((JSAny? _, JSFunction resolve, JSFunction reject) =>
      resolve.callAsFunction(null, null)).toJS;
  final complete = ((JSFunction resolve, JSFunction reject) =>
      resolve.callAsFunction(null, null)).toJS;
  _notificationLogout = complete;
  _notificationTags = complete;
  const imagePort = int.fromEnvironment('FESTAPP_E2E_IMAGE_PORT');
  if (imagePort != 0) {
    if (imagePort < 1024 || imagePort > 65535)
      throw StateError('Invalid E2E image port');
    _routeLocalImages(imagePort);
  }
  await app.main();
  WidgetsBinding.instance.ensureSemantics();
}

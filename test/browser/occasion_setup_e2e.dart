// Real application, local Auth/REST only. External push callbacks are stubbed.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/main.dart' as app;
import 'package:fstapp/data_services/synchro_service.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/rights_service.dart';

Future<void> main() async {
  final backend = Uri.parse(AppConfig.effectiveSupabaseUrl);
  if (backend.host != '127.0.0.1' ||
      backend.port !=
          const int.fromEnvironment('FESTAPP_TEST_BACKEND_PORT',
              defaultValue: 56821)) {
    throw StateError(
        'Wizard development requires the disposable loopback backend');
  }
  AppConfig.organization =
      const int.fromEnvironment('FESTAPP_TEST_ORGANIZATION', defaultValue: 1);
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
  await app.startApplication(initialize: () async {
    await app.initializeEverything();
    // Loopback uses the real current schema without production activation.
    SynchroService.configure(
      isLoggedIn: AuthService.isLoggedIn,
      getFullUserInfo: AuthService.getFullUserInfo,
      getCurrentOccasionId: RightsService.currentOccasionId,
      useLegacyAppConfig: false,
    );
  });
}

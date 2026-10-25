import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/stripe_payments/stripe_connect_callback_page.dart';
import 'package:fstapp/components/stripe_payments/stripe_connection_api.dart';
import 'package:fstapp/components/stripe_payments/stripe_connection_callback_owner.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

class CallbackApi implements StripeConnectionApi {
  final calls = <Map<String, String>>[];
  Map<String, dynamic> result = {'connected': true, 'unitId': 1};
  bool fail = false;
  @override
  Future<Map<String, dynamic>> complete(Map<String, String> callback) async {
    calls.add(Map.of(callback));
    if (fail) throw StateError('offline');
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() => environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())));

  testWidgets(
      'login replacement preserves callback until authenticated return and success clears memory',
      (tester) async {
    final owner = StripeConnectionCallbackOwner(), api = CallbackApi();
    Widget page({bool loggedIn = false, bool capture = false}) => MaterialApp(builder: DependencyMaterialBridge.builder,
            home: StripeConnectCallbackView(
          callbackOwner: owner,
          api: api,
          isLoggedIn: () => loggedIn,
          code: capture ? 'synthetic-code' : null,
          state: capture ? 'synthetic-state' : null,
        ));
    await environment.pumpWidget(tester, page(capture: true));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    // Login's replaceAll destroys the callback route rather than popping back.
    await environment.pumpWidget(tester, const MaterialApp(builder: DependencyMaterialBridge.builder, home: SizedBox()));
    expect(owner.retain(null),
        {'code': 'synthetic-code', 'state': 'synthetic-state'});
    await environment.pumpWidget(tester, page(loggedIn: true));
    await tester.pumpAndSettle();
    expect(api.calls, [
      {'code': 'synthetic-code', 'state': 'synthetic-state'}
    ]);
    expect(owner.retain(null), isNull);
  });

  testWidgets(
      'failed completion retains callback across disposal and provider cancellation clears it',
      (tester) async {
    final owner = StripeConnectionCallbackOwner(),
        api = CallbackApi()..fail = true;
    owner.retain({'error': 'access_denied', 'state': 'synthetic-state'});
    Widget page() => MaterialApp(builder: DependencyMaterialBridge.builder,
        home: StripeConnectCallbackView(
            callbackOwner: owner, api: api, isLoggedIn: () => true));
    await environment.pumpWidget(tester, page());
    await tester.pumpAndSettle();
    expect(owner.retain(null), isNotNull);
    await environment.pumpWidget(tester, const MaterialApp(builder: DependencyMaterialBridge.builder, home: SizedBox()));
    api
      ..fail = false
      ..result = {'status': 'cancelled'};
    await environment.pumpWidget(tester, page());
    await tester.pumpAndSettle();
    expect(api.calls.length, 2);
    expect(owner.retain(null), isNull);
  });

  test(
      'late success cannot clear a newer callback and callbacks are not mutable',
      () {
    final owner = StripeConnectionCallbackOwner();
    final previous = owner.retain({'code': 'old', 'state': 'old-state'})!;
    final current = owner.retain({'code': 'new', 'state': 'new-state'})!;
    owner.complete(previous);
    expect(owner.retain({}), same(current));
    expect(() => current.clear(), throwsUnsupportedError);
    owner.complete(current);
    expect(owner.retain(null), isNull);
  });
}

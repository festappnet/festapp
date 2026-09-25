import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/main.dart';
import 'package:fstapp/startup/startup_failure_policy.dart';

void main() {
  test('keeps the root route when no forced occasion is configured', () {
    expect(initialRouteForUri(Uri.parse('https://preview.example/')), '/');
  });

  test('preserves explicit web deep links', () {
    expect(
      initialRouteForUri(
          Uri.parse('https://preview.example/sample-event/news?filter=latest')),
      '/sample-event/news?filter=latest',
    );
  });

  test('unit admin deep links own their context load', () {
    expect(
      isUnitAdminStartupRoute(
          Uri.parse('https://vstupenky.online/unit/13/edit')),
      isTrue,
    );
    expect(
      isUnitAdminStartupRoute(Uri.parse('https://vstupenky.online/unit/13')),
      isFalse,
    );
    expect(
      isUnitAdminStartupRoute(
          Uri.parse('https://vstupenky.online/akh-ples/admin')),
      isFalse,
    );
  });

  testWidgets('preserves a password-reset deep link while initialization runs',
      (tester) async {
    const resetRoute = '/resetPassword?token=test-token';
    final initialization = Completer<void>();

    await tester.pumpWidget(FestappBootstrap(
      initialRoute: resetRoute,
      initialize: () => initialization.future,
      buildReadyApp: () => const SizedBox(),
    ));

    final loadingContext =
        tester.element(find.byKey(FestappBootstrap.loadingKey));
    expect(ModalRoute.of(loadingContext)?.settings.name, resetRoute);

    initialization.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('renders a launch surface while initialization is still pending',
      (tester) async {
    final initialization = Completer<void>();

    await tester.pumpWidget(FestappBootstrap(
      initialize: () => initialization.future,
      buildReadyApp: () => const MaterialApp(home: Text('ready')),
    ));

    expect(find.byKey(FestappBootstrap.loadingKey), findsOneWidget);
    expect(find.text('ready'), findsNothing);

    initialization.complete();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(FestappBootstrap.loadingKey), findsNothing);
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('opens the app shell after an unexpected initialization error',
      (tester) async {
    await tester.pumpWidget(FestappBootstrap(
      initialize: () => Future<void>.error(Exception('startup failed')),
      buildReadyApp: () => const MaterialApp(home: Text('offline shell')),
    ));

    await tester.pump();
    await tester.pump();

    expect(find.byKey(FestappBootstrap.loadingKey), findsNothing);
    expect(find.text('offline shell'), findsOneWidget);
  });

  test(
      'session recovery timeout does not turn a connected public startup offline',
      () {
    expect(
      shouldEnterOfflineAfterSessionInitializationFailure(
        wasAlreadyOffline: false,
        supabaseInitialized: true,
      ),
      isFalse,
    );
  });

  test('session initialization failure preserves a real offline state', () {
    expect(
      shouldEnterOfflineAfterSessionInitializationFailure(
        wasAlreadyOffline: true,
        supabaseInitialized: true,
      ),
      isTrue,
    );
    expect(
      shouldEnterOfflineAfterSessionInitializationFailure(
        wasAlreadyOffline: false,
        supabaseInitialized: false,
      ),
      isTrue,
    );
  });

  test(
      'clean cold start gets a longer occasion-loading window than cached startup',
      () {
    expect(
      occasionLoadTimeout(hasCachedSettings: false),
      const Duration(seconds: 15),
    );
    expect(
      occasionLoadTimeout(hasCachedSettings: true),
      const Duration(seconds: 5),
    );
  });
}

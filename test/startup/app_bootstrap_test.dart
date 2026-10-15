import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/services/bounded_database_opener.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/main.dart';
import 'package:fstapp/startup/startup_failure_policy.dart';

void main() {
  test('occasion startup retains query and fragment before alias replacement',
      () {
    const path = '/old/reservations/forms/f/settings?x=%2F#anchor';
    expect(initialRouteForUri(Uri.parse('https://preview.example$path')), path);
  });

  test('order view fragment survives cold startup', () {
    final uri = Uri.parse(
        'https://example.invalid/form/example#order?order_id=1&token=synthetic');
    expect(Uri.parse(initialRouteForUri(uri)).fragment, uri.fragment);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('pending database startup becomes actionable without launching the app', (tester) async {
    final pending = Completer<void>();
    var builds = 0;
    var retries = 0;
    await tester.pumpWidget(FestappBootstrap(
      initialize: () => pending.future,
      initializationTimeout: const Duration(milliseconds: 100),
      onRetry: () => retries++,
      buildReadyApp: () { builds++; return const SizedBox(); },
    ));
    await tester.pump(const Duration(milliseconds: 101));
    await tester.pump();
    expect(find.byKey(FestappBootstrap.loadingKey), findsNothing);
    expect(find.byKey(FestappBootstrap.failureKey), findsOneWidget);
    expect(builds, 0);
    await tester.tap(find.byType(FilledButton));
    expect(retries, 1);
    pending.complete();
    await tester.pump();
    expect(builds, 0, reason: 'Late initialization must not start alongside the failure surface');
    expect(find.byKey(FestappBootstrap.failureKey), findsOneWidget);
  });

  testWidgets('activation storage timeout fails closed with storage guidance', (tester) async {
    var builds = 0;
    await tester.pumpWidget(FestappBootstrap(
      initialize: () async => throw StorageOpenTimeoutException(const Duration(seconds: 5)),
      buildReadyApp: () { builds++; return const SizedBox(); },
    ));
    await tester.pumpAndSettle();
    expect(builds, 0);
    expect(find.byKey(FestappBootstrap.failureKey), findsOneWidget);
    expect(find.textContaining('Zavřete ostatní karty Festapp'), findsOneWidget);
  });

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

  test('personal form startup preserves capability only in its fragment', () {
    const path = '/form/example#waitlist?offer_id=offer&token=synthetic';
    final route = initialRouteForUri(Uri.parse('https://preview.example$path'));
    expect(route, path);
    expect(Uri.parse(route).hasQuery, isFalse);
    expect(Uri.parse(route).fragment, 'waitlist?offer_id=offer&token=synthetic');
    expect(initialRouteForUri(Uri.parse('https://preview.example/login#section')),
        '/login');
  });

  test('startup preserves nested tabs and both calendar query parameters', () {
    const path =
        '/event-a/reservations/forms/second/responses?day=2026-10-03&preview-day=2026-10-10';
    expect(initialRouteForUri(Uri.parse('https://preview.example$path')), path);
    expect(
        isUnitAdminStartupRoute(Uri.parse(
            'https://preview.example/unit/5/edit/bank-accounts/9/users')),
        isTrue);
  });

  test('Google callback resumes login after its query was consumed', () {
    for (final path in [
      '/app/google-auth',
      '/app/google-auth?google_error=provider_cancelled'
    ]) {
      expect(initialRouteForUri(Uri.parse('https://live.festapp.net$path')),
          '/login');
    }
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

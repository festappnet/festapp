import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/main.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/startup/startup_failure_policy.dart';

void main() {
  test(
      'private Stripe routes never load a default occasion and survive offline cold startup',
      () {
    for (final path in [
      '/stripe/pay',
      '/stripe/return',
      '/stripe/connect/callback',
      '/app/stripe/pay',
      '/app/stripe/return',
      '/app/stripe/connect/callback'
    ]) {
      expect(
          skipsDefaultOccasionAtStartup(
              Uri.parse('https://tickets.example$path')),
          isTrue,
          reason: path);
    }
    expect(
        skipsDefaultOccasionAtStartup(
            Uri.parse('https://tickets.example/stripe/foreign')),
        isFalse);
    for (final prefix in ['', '/app']) {
      expect(
          nativeInitialRoute(
              'https://tickets.example$prefix/stripe/pay#pay=${'a' * 64}'),
          '/stripe/pay');
      expect(
          nativeInitialRoute(
              'https://tickets.example$prefix/stripe/return?return_handle=${'b' * 64}'),
          '/stripe/return');
    }
    expect(nativeInitialRoute('/form/event#order?order_id=1'),
        '/form/event#order?order_id=1');
    expect(AppRouter.getRootLinks(), contains('stripe'));
    final offline = RightsService.useOfflineVersion,
        link = RightsService.currentLink;
    try {
      RightsService.useOfflineVersion = true;
      RightsService.currentLink = null;
      expect(AppRouter.getDefaultLink, returnsNormally);
    } finally {
      RightsService.useOfflineVersion = offline;
      RightsService.currentLink = link;
    }
  });
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
    expect(
        Uri.parse(route).fragment, 'waitlist?offer_id=offer&token=synthetic');
    expect(
        initialRouteForUri(Uri.parse('https://preview.example/login#section')),
        '/login');
  });

  test('startup preserves nested tabs and both calendar query parameters', () {
    const path =
        '/event-a/reservations/forms/second/responses?day=2026-10-03&preview-day=2026-10-10';
    expect(initialRouteForUri(Uri.parse('https://preview.example$path')), path);
    expect(
        skipsDefaultOccasionAtStartup(Uri.parse(
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
      skipsDefaultOccasionAtStartup(
          Uri.parse('https://vstupenky.online/unit/13/edit')),
      isTrue,
    );
    expect(
      skipsDefaultOccasionAtStartup(
          Uri.parse('https://vstupenky.online/unit/13')),
      isFalse,
    );
    expect(
      skipsDefaultOccasionAtStartup(
          Uri.parse('https://vstupenky.online/akh-ples/admin')),
      isFalse,
    );
  });

  test('organization admin startup does not require a default occasion', () {
    for (final path in [
      '/organizationEdit',
      '/organizationEdit/1',
      '/organizationEdit/1/?tab=verification',
      '/app/google-auth'
    ]) {
      expect(
          skipsDefaultOccasionAtStartup(
              Uri.parse('https://preview.example$path')),
          isTrue,
          reason: path);
    }
    for (final path in [
      '/organizationEditOther/1',
      '/event/organizationEdit/1',
      '/form/example',
      '/organizationEdit/not-an-id'
    ]) {
      expect(
          skipsDefaultOccasionAtStartup(
              Uri.parse('https://preview.example$path')),
          isFalse,
          reason: path);
    }
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

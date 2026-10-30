import 'dart:async';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:festapp_core/time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/notification_center/notification_center_bell.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fixtures/rights_context_fixture.dart';
import '../../support/fixtures/root_supabase_fixture.dart';

class _BellRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      path: '/event/reservations',
      page: PageInfo(
        'BellFixture',
        builder: (_) =>
            const Scaffold(appBar: null, body: NotificationCenterBell()),
      ),
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RootSupabaseFixture fixture;
  Completer<void>? contextGate;
  var badgeReads = 0;
  var contextReads = 0;

  Map<String, dynamic> context() => {
    'code': 200,
    'occasion': {'id': 17, 'link': 'event', 'data': <String, dynamic>{}},
    'organization': {'id': AppConfig.organization},
    'capabilities': {'navigation.administration': true},
    'demo_read_only': true,
  };

  setUpAll(() async {
    OccasionTimeContext.initializeTimeZones();
    PackageInfo.setMockInitialValues(
      appName: 'test',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    fixture = await RootSupabaseFixture.open((request) async {
      dynamic data;
      if (request.url.path.startsWith('/rest/v1/rpc/get_app_config_')) {
        contextReads++;
        await contextGate?.future;
        data = context();
      } else if (request.url.path.endsWith('/get_notification_center_badge')) {
        badgeReads++;
        data = {'timelineSupported': true, 'enabled': true, 'unread': true};
      } else {
        throw StateError('Unexpected request: ${request.url.path}');
      }
      return http.Response(
        jsonEncode(data),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
    const actor = '00000000-0000-4000-8000-000000000001';
    final token = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              'sub': actor,
            }),
          ),
        )
        .replaceAll('=', '');
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.$token.fixture',
        'refresh_token': 'fixture',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': actor,
          'aud': 'authenticated',
          'role': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });
  tearDownAll(() => fixture.dispose());
  setUp(() {
    badgeReads = 0;
    contextReads = 0;
    contextGate = null;
    final rights = RightsContextFixture(
      context: OccasionLinkModel.fromJson(context()),
    );
    addTearDown(rights.dispose);
  });

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      await tester.pump();
    }
  }

  Future<Future<bool> Function()> beginRefresh(WidgetTester tester) async {
    late Future<bool> update;
    await tester.runAsync(() async {
      update = RightsService.updateAppData(
        link: 'event',
        force: true,
        refreshOffline: false,
      );
      await Future<void>.delayed(Duration.zero);
    });
    return () => update;
  }

  Future<void> mount(WidgetTester tester) async {
    final router = _BellRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router.config(
          deepLinkBuilder: (_) => DeepLink.path('/event/reservations'),
        ),
      ),
    );
    await flush(tester);
  }

  testWidgets(
    'initial bell waits for context instead of reading preliminary rights',
    (tester) async {
      contextGate = Completer<void>();
      final update = await beginRefresh(tester);
      await mount(tester);
      final preliminaryReads = badgeReads;
      contextGate!.complete();
      await tester.runAsync(update);
      await flush(tester);
      expect(
        preliminaryReads,
        0,
        reason: 'pending context must not start an obsolete badge read',
      );
      expect(badgeReads, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('rights refresh reads badge once after final context arrives', (
    tester,
  ) async {
    await mount(tester);
    expect(badgeReads, 1);
    contextGate = Completer<void>();
    final update = await beginRefresh(tester);
    await flush(tester);
    final preliminaryReads = badgeReads;
    contextGate!.complete();
    await tester.runAsync(update);
    await flush(tester);
    expect(
      preliminaryReads,
      1,
      reason: 'clearing capabilities must not issue a preliminary read',
    );
    expect(badgeReads, 2);
    expect(contextReads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('disposed bell never reads after the context completes', (
    tester,
  ) async {
    contextGate = Completer<void>();
    final update = await beginRefresh(tester);
    await mount(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    contextGate!.complete();
    await tester.runAsync(update);
    await flush(tester);
    expect(badgeReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background bell waits for resume after the context completes', (
    tester,
  ) async {
    await mount(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    contextGate = Completer<void>();
    final update = await beginRefresh(tester);
    await flush(tester);
    contextGate!.complete();
    await tester.runAsync(update);
    await flush(tester);
    expect(badgeReads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flush(tester);
    expect(badgeReads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

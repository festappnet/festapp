import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/mcp/mcp_callback_window.dart';
import 'package:fstapp/components/mcp/mcp_connection_page.dart';
import 'package:fstapp/components/mcp/mcp_connection_service.dart';

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });

  test(
      'continuation only permits the exact issuer finish route and one opaque code',
      () {
    final code = List.filled(43, 'a').join();
    expect(
        McpConnectionService.resumeUri(
                'https://mcp.festapp.net/connect/uid/finish?resume=$code')
            .host,
        'mcp.festapp.net');
    for (final url in [
      'not-a-url',
      'https://evil.invalid/connect/uid/finish?resume=$code',
      'https://mcp.festapp.net.evil.invalid/connect/uid/finish?resume=$code',
      'https://user@mcp.festapp.net/connect/uid/finish?resume=$code',
      'https://mcp.festapp.net/token?resume=$code',
      'https://mcp.festapp.net/connect/uid/finish?resume=$code&redirect=https://evil.invalid',
      'https://mcp.festapp.net/connect/uid/finish?resume=short',
    ]) {
      expect(() => McpConnectionService.resumeUri(url), throwsFormatException);
    }
  });

  test('tenant confirmation has its own settings route with the opaque request',
      () {
    final result = AppRouter().matcher.match(
        '/settings/mcp-connect?request=opaque',
        includePrefixMatches: false);
    expect(result!.single.name, 'McpConnectionRoute');
    expect(result.single.queryParams.getString('request'), 'opaque');
  });

  testWidgets(
      'app login is offered without fetching account details anonymously',
      (tester) async {
    var called = false;
    await tester.pumpWidget(MaterialApp(
        home: McpConnectionPage(
      request: List.filled(43, 'r').join(),
      isLoggedIn: () => false,
      requester: (_, __, ___) async {
        called = true;
        return {};
      },
    )));
    expect(find.text('McpConnection.login'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(called, false);
  });

  testWidgets(
      'existing login sees consent and must explicitly select an occasion',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: McpConnectionPage(
      request: List.filled(43, 'r').join(),
      isLoggedIn: () => true,
      accountEmail: AppConfig.getUserPrefix('fixture@invalid'),
      requester: (_, operation, selected) async {
        calls++;
        expect(operation, 'details');
        expect(selected, isEmpty);
        return {
          'client': 'Codex',
          'occasions': [
            {'id': 7, 'title': 'Test event'}
          ]
        };
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('fixture@invalid'), findsOneWidget);
    expect(find.text('Test event'), findsOneWidget);
    FilledButton approve() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'McpConnection.approve'));
    expect(approve().onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(approve().onPressed, isNotNull);
    expect(calls, 1);
  });

  testWidgets(
      'expired request displays a recoverable error without a consent button',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: McpConnectionPage(
      request: List.filled(43, 'r').join(),
      isLoggedIn: () => true,
      accountEmail: AppConfig.getUserPrefix('fixture@invalid'),
      requester: (_, __, ___) async => throw StateError('expired'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('McpConnection.error'), findsOneWidget);
    expect(find.text('McpConnection.approve'), findsNothing);
  });
  testWidgets(
      'native completion stays on the tenant and waits for verified exchange',
      (tester) async {
    final callback = _CallbackWindow();
    var confirmed = false;
    await tester.pumpWidget(MaterialApp(
        home: McpConnectionPage(
      request: List.filled(43, 'r').join(),
      isLoggedIn: () => true,
      accountEmail: AppConfig.getUserPrefix('fixture@invalid'),
      openCallbackWindow: () => callback,
      requester: (_, operation, selected) async {
        if (operation == 'details')
          return {
            'client': 'Codex',
            'applicationType': 'native',
            'occasions': [
              {'id': 7, 'title': 'Test event'}
            ]
          };
        if (operation == 'approve') {
          expect(selected, {
            'type': 'occasions',
            'occasionIds': [7]
          });
          return {
            'resumeUrl':
                'https://mcp.festapp.net/connect/uid/finish?resume=${List.filled(43, 'a').join()}'
          };
        }
        expect(operation, 'status');
        return {'status': confirmed ? 'connected' : 'pending'};
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('McpConnection.approve'));
    await tester.tap(find.text('McpConnection.approve'));
    await tester.pump();
    expect(callback.target?.host, 'mcp.festapp.net');
    expect(find.text('McpConnection.connected'), findsNothing);
    expect(find.text('McpConnection.waitingForClient'), findsOneWidget);
    expect(callback.closed, false);
    confirmed = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('McpConnection.connected'), findsOneWidget);
    expect(find.text('McpConnection.closeHint'), findsOneWidget);
    expect(find.text('fixture@invalid'), findsOneWidget);
    expect(find.text(AppConfig.getUserPrefix('fixture@invalid')), findsNothing);
    expect(callback.closed, true);
  });
  testWidgets('whole organizer and creation require two explicit choices',
      (tester) async {
    Map<String, dynamic>? approved;
    final callback = _CallbackWindow();
    await tester.pumpWidget(MaterialApp(
        home: McpConnectionPage(
      request: List.filled(43, 'r').join(),
      isLoggedIn: () => true,
      accountEmail: 'fixture@invalid',
      openCallbackWindow: () => callback,
      requester: (_, operation, access) async {
        if (operation == 'details')
          return {
            'client': 'Codex',
            'applicationType': 'native',
            'canRequestCreate': true,
            'units': [
              {
                'id': 3,
                'title': 'Fixture organizer',
                'canCreateOccasions': true
              }
            ],
            'occasions': [
              {'id': 7, 'title': 'Fixture occasion'}
            ],
          };
        if (operation == 'approve') {
          approved = access;
          return {
            'resumeUrl':
                'https://mcp.festapp.net/connect/uid/finish?resume=${List.filled(43, 'r').join()}'
          };
        }
        return {'status': 'connected'};
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('McpConnection.allowCreate'), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Fixture occasion'), findsNothing);
    final checkbox =
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(checkbox.value, false);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('McpConnection.approve'));
    await tester.tap(find.text('McpConnection.approve'));
    await tester.pumpAndSettle();
    expect(approved, {'type': 'unit', 'unitId': 3, 'canCreateOccasions': true});
    expect(callback.closed, true);
  });
}

class _CallbackWindow implements McpCallbackWindow {
  Uri? target;
  bool closed = false;
  @override
  void navigate(Uri uri) {
    target = uri;
  }

  @override
  void close() {
    closed = true;
  }
}

import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.dart';
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
      accountEmail: 'fixture@invalid',
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
      accountEmail: 'fixture@invalid',
      requester: (_, __, ___) async => throw StateError('expired'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('McpConnection.error'), findsOneWidget);
    expect(find.text('McpConnection.approve'), findsNothing);
  });
}

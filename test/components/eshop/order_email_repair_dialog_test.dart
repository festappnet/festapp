import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/order_commands.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/eshop/views/order_email_repair_dialog.dart';
import 'package:fstapp/components/eshop/views/order_state_cell.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/email_delivery/order_email_issue.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import '../../support/fixtures/client_command_response_fixture.dart';
import '../../support/fixtures/localization_log_fixture.dart';

Map<String, dynamic> issue(String state,
        {String resolution = 'bounce', String id = 'source'}) =>
    {
      'source_message_id': id,
      'message_id': id,
      'kind': 'order_confirmation',
      'state': state,
      'resolution': resolution,
      'original_recipient': 'old@example.invalid',
    };
void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  test(
      'server issues own lifecycle, history does not determine current warning',
      () {
    expect(
        OrderEmailIssue.fromSummary(
            {'state': 'bounce', 'attention_count': 8, 'current_issues': []}),
        isEmpty);
    for (final state in [
      'bounce',
      'suppressed',
      'retry_wait',
      'unknown',
      'post_action_failed'
    ]) {
      final value = OrderEmailIssue(issue(state));
      expect(
          value.canResend, !['unknown', 'post_action_failed'].contains(state));
    }
    expect(
        OrderEmailIssue(issue('accepted', resolution: 'waiting_repair'))
            .canResend,
        isFalse);
    expect(OrderEmailIssue.fromSummary(null), isEmpty);
    final spam = OrderEmailIssue(issue('complaint'));
    expect(spam.blocksRecipient('old@example.invalid'), isTrue);
    expect(spam.blocksRecipient('fixed@example.invalid'), isFalse);
  });
  for (final state in [
    'bounce',
    'suppressed',
    'retry_wait',
    'unknown',
    'post_action_failed'
  ]) {
    testWidgets(
        'shared detail keeps the precise issue and read-only actions: $state',
        (tester) async {
      Future<dynamic> read(String name, Map<String, dynamic> args) async =>
          name == 'get_order_history'
              ? {
                  'code': 200,
                  'data': {
                    'order': {
                      'id': 4,
                      'occasion': 7,
                      'state': 'ordered',
                      'data': {'email': 'old@example.invalid'}
                    }
                  }
                }
              : {
                  'current_issues': [issue(state)]
                };
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: OrderEmailRepairDialog(
                  orderId: 4, occasionId: 7, read: read, canWrite: false))));
      await tester.pumpAndSettle();
      expect(find.textContaining('EmailDelivery.state.$state'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      if (state == 'unknown')
        expect(find.text('EmailDelivery.recovery.uncertain'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('show order closes the dialog and reveals its grid row',
      (tester) async {
    var revealed = false;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => OrderEmailRepairDialog(
                            orderId: 4,
                            occasionId: 7,
                            canWrite: false,
                            onShowOrder: () => revealed = true,
                            read: (name, args) async =>
                                name == 'get_order_history'
                                    ? {
                                        'code': 200,
                                        'data': {
                                          'order': {
                                            'id': 4,
                                            'occasion': 7,
                                            'state': 'ordered',
                                            'data': {
                                              'email': 'test@example.invalid'
                                            }
                                          }
                                        }
                                      }
                                    : {'current_issues': []})),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EmailDelivery.recovery.show'));
    await tester.pumpAndSettle();
    expect(revealed, isTrue);
    expect(find.byType(OrderEmailRepairDialog), findsNothing);
  });
  testWidgets('late object read after closing cannot display contact data',
      (tester) async {
    final response = Completer<dynamic>();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => OrderEmailRepairDialog(
                            orderId: 4,
                            occasionId: 7,
                            read: (name, args) => response.future,
                            canWrite: false)),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    response.complete({
      'code': 200,
      'data': {
        'order': {
          'occasion': 7,
          'data': {'email': 'private@example.invalid'}
        }
      }
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('private@example.invalid'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    testWidgets('AppBar opens shared dialog at 320px, 200 percent, dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var current = issue('bounce');
      var fail = false;
      Future<dynamic> read(String name, Map<String, dynamic> args) async {
        if (fail) throw StateError('offline');
        if (name == 'get_order_history')
          return {
            'code': 200,
            'data': {
              'order': {
                'id': 4,
                'occasion': 7,
                'order_symbol': 'TEST4',
                'state': 'ordered',
                'email_payment_version': 1,
                'email_payment_fingerprint': 'facts',
                'data': {
                  'email': 'current@example.invalid',
                  'name': 'Synthetic'
                },
              }
            }
          };
        return {
          'current_issues': [current]
        };
      }

      await tester.pumpWidget(MaterialApp(
          theme: ThemeConfig.theme(
              brightness: dark ? Brightness.dark : Brightness.light),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!),
          home: Builder(
              builder: (context) => Scaffold(
                      appBar: AppBar(actions: [
                    IconButton(
                        icon: const Icon(Icons.mail),
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => OrderEmailRepairDialog(
                                orderId: 4,
                                occasionId: 7,
                                read: read,
                                canWrite: false)))
                  ])))));
      await tester.tap(find.byIcon(Icons.mail));
      await tester.pumpAndSettle();
      expect(
          find.text('old@example.invalid', findRichText: true), findsNothing);
      expect(find.textContaining('old@example.invalid'), findsOneWidget);
      expect(find.textContaining('current@example.invalid'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
      current = issue('accepted', resolution: 'waiting_repair');
      fail = true;
      // Dismissal has no delivery mutation.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(OrderEmailRepairDialog), findsNothing);
    });
  }
  testWidgets(
      'save conflict reloads authoritative data and disables in-flight double click',
      (tester) async {
    final pending = Completer<Object?>();
    var requests = 0, reads = 0;
    late Map<String, dynamic> sent;
    final commands = SupabaseOrderCommands.withTransport(
        ClientCommandTransport((name, args) {
      requests++;
      sent = args;
      return pending.future;
    }, maxAttempts: 1));
    Future<dynamic> read(String name, Map<String, dynamic> args) async {
      reads++;
      if (name == 'get_order_history')
        return {
          'code': 200,
          'data': {
            'order': {
              'id': 4,
              'occasion': 7,
              'state': 'ordered',
              'email_payment_version': 1,
              'email_payment_fingerprint': 'facts',
              'data': {
                'email':
                    reads > 2 ? 'server@example.invalid' : 'old@example.invalid'
              },
            }
          }
        };
      return {
        'current_issues': [issue('bounce')]
      };
    }

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OrderEmailRepairDialog(
                orderId: 4,
                occasionId: 7,
                read: read,
                commands: commands,
                canWrite: true))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new@example.invalid');
    await tester.tap(find.text('EmailDelivery.recovery.resend'));
    await tester.pump();
    expect(requests, 1);
    expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(
                ElevatedButton, 'EmailDelivery.recovery.resend'))
            .onPressed,
        isNull);
    pending.complete(commandResponseFixture(sent['p_command_id'],
        status: 'conflict', code: 409));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('EmailDelivery.recovery.conflict'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'server@example.invalid');
    expect(sent['p_source_message'], 'source');
    expect(sent['p_resend'], true);
  });
  testWidgets(
      'warning beside order state uses current issues, not historical attention',
      (tester) async {
    final order = OrderModel(id: 4, state: 'ordered');
    order.emailDelivery = {
      'current_issues': [issue('suppressed'), issue('unknown', id: 'second')]
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 250,
                height: 50,
                child: OrderStateCell(
                    label: 'ORDERED',
                    background: Colors.white,
                    occasionId: 7,
                    order: order)))));
    expect(find.byIcon(Icons.mark_email_unread_outlined), findsOneWidget);
    order.emailDelivery = {
      'state': 'bounce',
      'attention_count': 2,
      'current_issues': []
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OrderStateCell(
                label: 'ORDERED', background: Colors.white, order: order))));
    expect(find.byIcon(Icons.mark_email_unread_outlined), findsNothing);
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/order_commands.dart';
import 'package:fstapp/components/eshop/views/order_email_repair_dialog.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:fstapp/theme_config.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import '../../support/fixtures/client_command_response_fixture.dart';

Map<String, dynamic> delivery(String id, String kind, String state,
        {bool obsolete = false, String? suppression}) => {
  'message_id': id, 'source_message_id': 'root-$id', 'kind': kind,
  'state': state, 'resolution': state, 'obsolete': obsolete,
  'original_recipient': 'customer@example.comcz',
  'recipient': 'customer@example.comcz',
  if (suppression != null) 'suppression_reason': suppression,
};

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() async {
    environment = WidgetEnvironmentFixture(locale: const Locale('cs'),
        translations: jsonDecode(File('assets/translations/cs.json').readAsStringSync()) as Map<String, dynamic>);
    final font = FontLoader('Futura')
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'))
      ..addFont(rootBundle.load('fonts/Futura PT Medium.ttf'));
    await font.load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<void> open(WidgetTester tester, List<Map<String, dynamic>> issues,
      {OrderCommands? commands, bool dark = false, double scale = 1,
       GlobalKey? captureKey, String state = 'sent', String? source,
       String storedEmail = 'customer@example.comcz'}) async {
    await environment.pumpWidget(tester, RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeConfig.theme(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
          onPressed: () => showDialog<void>(context: context,
            builder: (_) => OrderEmailRepairDialog(
              orderId: 4, occasionId: 7, canWrite: true, commands: commands,
              sourceMessageId: source, onShowOrder: () {},
              read: (name, args) async => name == 'get_order_history'
                  ? {'code': 200, 'data': {'order': {
                      'id': 4, 'occasion': 7, 'order_symbol': 'TEST123',
                      'state': state, 'email_payment_version': 1,
                      'email_payment_fingerprint': 'facts',
                      'data': {'name': 'Jana', 'surname': 'Nováková', 'email': storedEmail},
                    }}}
                  : {'current_issues': issues},
            )), child: const Text('Open'))))),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final view in [
    (name: 'desktop-light', size: const Size(900, 850), dark: false, scale: 1.0),
    (name: 'desktop-dark', size: const Size(900, 850), dark: true, scale: 1.0),
    (name: 'mobile-large-text', size: const Size(320, 800), dark: true, scale: 2.0),
  ]) {
    testWidgets('${view.name}: focus on correcting the address, details collapsed', (tester) async {
      tester.view.physicalSize = view.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await open(tester, [
        delivery('obsolete', 'order_confirmation', 'bounce', obsolete: true),
        delivery('tickets', 'order_tickets', 'suppressed', suppression: 'hard_bounce'),
      ], captureKey: key, dark: view.dark, scale: view.scale, source: 'obsolete');
      expect(find.text('Opravit e-mail'), findsOneWidget);
      expect(find.textContaining('Na tuto adresu nelze doručovat.'), findsOneWidget);
      expect(find.textContaining('Poskytovatel oznámil'), findsNothing);
      expect(find.text('Vyřešit doručení'), findsNothing);
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
      expect(find.text('Uložit a odeslat vstupenky').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['FESTAPP_DIALOG_CAPTURE_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(directory).createSync(recursive: true);
          File('$directory/${view.name}.png').writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  testWidgets('correcting an address sends the current tickets leaf, never an obsolete confirmation', (tester) async {
    Map<String, dynamic>? sent;
    final commands = SupabaseOrderCommands.withTransport(ClientCommandTransport((name, args) async {
      sent = args;
      return commandResponseFixture(args['p_command_id']);
    }, maxAttempts: 1));
    await open(tester, [
      delivery('old', 'order_confirmation', 'bounce', obsolete: true),
      delivery('current-leaf', 'order_tickets', 'suppressed', suppression: 'hard_bounce'),
    ], source: 'old', commands: commands);
    await tester.enterText(find.byType(TextField), 'customer@example.cz');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uložit a odeslat vstupenky'));
    await tester.pumpAndSettle();
    expect(sent?['p_source_message'], 'current-leaf');
    expect(sent?['p_resend'], true);
    expect(sent?['p_email'], 'customer@example.cz');
  });

  for (final state in ['unknown', 'post_action_failed', 'pending']) {
    testWidgets('$state: changing the address cannot bypass the send guard', (tester) async {
      await open(tester, [delivery('current', 'order_tickets', state,
          suppression: state == 'post_action_failed' ? 'hard_bounce' : null)]);
      await tester.enterText(find.byType(TextField), 'customer@example.cz');
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Pouze uložit')).onPressed, isNotNull);
      if (state == 'post_action_failed') {
        expect(find.textContaining('Před dalším odesláním zkontrolujte stav zprávy'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an old failure must not label an already corrected address as wrong', (tester) async {
    await open(tester, [delivery('current', 'order_tickets', 'bounce')],
        storedEmail: 'correct@example.cz');
    expect(find.text('Opravit e-mail'), findsNothing);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNotNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Pouze uložit')).onPressed, isNull);
  });

  testWidgets('competing current messages require a choice instead of dropping source guards', (tester) async {
    await open(tester, [
      delivery('a', 'order_tickets', 'bounce'),
      delivery('b', 'order_tickets', 'post_action_failed'),
    ]);
    await tester.enterText(find.byType(TextField), 'customer@example.cz');
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    expect(find.textContaining('Vyberte zprávu'), findsOneWidget);
  });
}

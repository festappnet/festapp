import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/dialog_helper_progress.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

void main() {
  for (final futureDialog in [false, true]) {
    testWidgets(
        '${futureDialog ? "future" : "basic"} progress closes its root dialog without popping the nested editor',
        (tester) async {
      late BuildContext editorContext;
      await tester.pumpWidget(MaterialApp(
        home: Navigator(
          initialRoute: '/editor',
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (context) {
              if (settings.name == '/editor') {
                editorContext = context;
                return const Scaffold(body: Text('Editor'));
              }
              return const Scaffold(body: Text('Nested home'));
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final write = Completer<void>();
      final Future<Object?> pending = futureDialog
          ? ProgressDialogs.showFutureProgressDialog<bool>(
              context: editorContext,
              title: 'Save',
              futureCallback: () async {
                await write.future;
                return true;
              },
            )
          : ProgressDialogs.showProgressDialogAsync(editorContext, 'Save', 1,
              isBasic: true, futures: [() => write.future]);
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      write.complete();
      await tester.pumpAndSettle();
      expect(await pending, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Editor'), findsOneWidget);
      expect(find.text('Nested home'), findsNothing);
    });
  }

  testWidgets('completed summary can be acknowledged without completing twice',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const Scaffold(body: Text('Editor'));
    })));
    final pending = ProgressDialogs.showProgressDialogAsync(context, 'Save', 1,
        futures: [() async {}]);
    await tester.pumpAndSettle();
    expect(await pending, isTrue);
    await tester.tap(find.text(CommonStrings.ok));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Editor'), findsOneWidget);
  });

  testWidgets(
      'basic progress displays a failed write and returns false after closing its dialog',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
        home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (value) {
                  context = value;
                  return const Scaffold();
                }))));
    final write = Completer<void>();
    final calls = <MethodCall>[];
    const channel = MethodChannel('PonnamKarthik/fluttertoast');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final failure = PostgrestException(
        message:
            '{"code": "delete_failed", "message": "Order delete rejected"}');
    final pending = ProgressDialogs.showProgressDialogAsync(context, 'Save', 1,
        isBasic: true, futures: [() => write.future]);
    final assertion = expectLater(pending, completion(isFalse));
    await tester.pumpAndSettle();
    write.completeError(failure);
    await tester.pumpAndSettle();
    await assertion;
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        calls
            .where((call) => call.method == 'showToast')
            .single
            .arguments['msg'],
        'Order delete rejected');
    await tester.pump(const Duration(seconds: 3));
  });
}

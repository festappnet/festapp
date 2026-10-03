import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/dialog_helper_progress.dart';

void main() {
  testWidgets(
      'basic progress displays a failed write and returns false after closing its dialog',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const Scaffold();
    })));
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

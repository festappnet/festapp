import 'widget_environment_fixture.dart';
import 'localization_log_cases.dart' as localization;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'root_supabase_fixture.dart';
import 'package:fstapp/components/bank_accounts/db_bank_accounts.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/bank_accounts/supabase_bank_accounts.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:http/http.dart' as http;
import 'local_app_storage_fixture.dart';
import 'supabase_client_fixture.dart';

void main() {
  group('localization_logs', localization.main);
  WidgetEnvironmentFixture.register();
  TestWidgetsFlutterBinding.ensureInitialized();
  test('client scopes A-B-A keep request logs and pending intents independent',
      () async {
    final intents = <String>[];
    for (final context in ['A', 'B', 'A']) {
      final fixture = SupabaseClientFixture((request) {
        final body = jsonDecode(request.body) as Map;
        expect(body['context'], context);
        intents.add(body['operation_id'] as String);
        return http.Response('{"error":"bank_sync_retry_required"}', 200,
            headers: {'content-type': 'application/json'});
      });
      try {
        expect(fixture.requests, isEmpty);
        final commands = SupabaseBankAccounts(fixture.client);
        await expectLater(
            commands.manage(1, 'test', values: {'context': context}),
            throwsException);
        await expectLater(
            commands.manage(1, 'test', values: {'context': context}),
            throwsException);
        expect(fixture.requests, hasLength(2));
        expect(intents[intents.length - 2], intents.last);
      } finally {
        await fixture.dispose();
      }
    }
    expect({intents[0], intents[2], intents[4]}, hasLength(3));
  });
  test('storage scopes A-B-A close databases and remove owned files', () async {
    for (final context in ['A', 'B', 'A']) {
      final fixture = await LocalAppStorageFixture.open();
      try {
        expect(await StorageHelper.get('context'), isNull);
        await StorageHelper.set('context', context);
        expect(await StorageHelper.get('context'), context);
      } finally {
        await fixture.dispose();
      }
      expect(await fixture.directory.exists(), isFalse);
    }
  });
  test(
      'production bank composition owns intents per root client in A-B-A order',
      () async {
    final ids = <String>[];
    SupabaseBankAccounts? previous;
    for (final context in ['A', 'B', 'A']) {
      final fixture = await RootSupabaseFixture.open((request) {
        final body = jsonDecode(request.body) as Map;
        expect(body['context'], context);
        ids.add(body['operation_id'] as String);
        return http.Response('{"error":"bank_sync_retry_required"}', 200,
            headers: {'content-type': 'application/json'});
      });
      try {
        final commands = DbBankAccounts.current;
        expect(commands, same(DbBankAccounts.current));
        if (previous != null) expect(commands, isNot(same(previous)));
        await expectLater(
            commands.manage(1, 'test', values: {'context': context}),
            throwsException);
        previous = commands;
      } finally {
        await fixture.dispose();
      }
    }
    expect(ids.toSet(), hasLength(3));
  });
  testWidgets('public widget environments A-B-A load fresh scoped translations',
      (tester) async {
    for (final value in ['A', 'B', 'A']) {
      final environment =
          WidgetEnvironmentFixture(locale: const Locale('cs'), translations: {
        'fixture': {'value': value}
      });
      await environment.pumpWidget(
          tester,
          MaterialApp(
              home: Builder(builder: (_) => Text('fixture.value'.tr()))));
      expect(find.text(value), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/companion/companion_admin_dialog.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/database_tables/tb.dart';

OccasionUserModel user(
  String id,
  String name,
  String email, {
  String? group,
  String? owner,
}) =>
    OccasionUserModel(
      occasion: 9,
      user: id,
      groupTitle: group,
      companionOwnerId: owner,
      data: {
        Tb.occasion_users.data_name: name,
        Tb.occasion_users.data_email: email,
      },
    );

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('admin dialog identifies users, groups and blocked candidates',
      (tester) async {
    final owner = user('owner', 'Michael Bujnovský', 'owner@example.test',
        group: '0DISK');
    final existing = user('existing', 'Michael B', 'existing@example.test',
        owner: 'someone-else');

    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: CompanionAdminDialog(
        owner: owner,
        users: [owner, existing],
        maxCompanions: 1,
        onChanged: () async {},
      ),
    ));

    expect(find.text('Michael Bujnovský'), findsOneWidget);
    expect(find.textContaining('owner@example.test'), findsOneWidget);
    expect(find.textContaining('0DISK'), findsOneWidget);
    expect(find.text('Michael B'), findsOneWidget);
    expect(find.textContaining('existing@example.test'), findsOneWidget);
    final assign = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(assign.onPressed, isNull,
        reason: 'a candidate with another owner must be visibly disabled');
  });

  testWidgets('successful assignment shows a positive toast', (tester) async {
    String? toastMessage;
    const toastChannel = MethodChannel('PonnamKarthik/fluttertoast');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      toastChannel,
      (call) async {
        if (call.method == 'showToast') {
          toastMessage = (call.arguments as Map)['msg'] as String?;
        }
        return true;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(toastChannel, null));

    final owner = user('owner', 'Michael Bujnovský', 'owner@example.test',
        group: '0DISK');
    final candidate = user('candidate', 'Michael B', 'candidate@example.test');
    var assigned = false;
    var refreshed = false;

    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: CompanionAdminDialog(
        owner: owner,
        users: [owner, candidate],
        maxCompanions: 1,
        changeCompanion: (ownerId, companionId, detach) async {
          expect(ownerId, 'owner');
          expect(companionId, 'candidate');
          expect(detach, isFalse);
          assigned = true;
        },
        onChanged: () async => refreshed = true,
      ),
    ));

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton).last);
    await tester.pumpAndSettle();

    expect(assigned, isTrue);
    expect(refreshed, isTrue);
    expect(toastMessage, 'FeatureUser.companionAssigned');
    await tester.pump(const Duration(seconds: 4));
  });
}

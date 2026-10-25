import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_invitations.dart';
import '../../support/fixtures/localization_log_fixture.dart';

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });

  test(
      'recipient identity is normalized without sending or accepting bad emails',
      () {
    expect(
        occasionSetupInviteEmails({
          'teamInviteEmails': [' A@example.org ', 'a@example.org', '']
        }),
        ['a@example.org']);
    expect(validTeamInviteEmail(''), isFalse);
    expect(validTeamInviteEmail('invalid'), isFalse);
    expect(validTeamInviteEmail('a@example.org'), isTrue);
    expect(occasionSetupInviteRole({}, 'a@example.org'), 'editor');
  });

  testWidgets('role choice and list changes revoke send confirmation',
      (tester) async {
    final data = <String, dynamic>{
      'teamInviteEmails': ['one@example.org'],
      'sendTeamInvitations': true
    };
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
        home: Scaffold(
            body: SingleChildScrollView(
                child: StatefulBuilder(
                    builder: (context, setState) => OccasionSetupInvitations(
                        draftId: 'draft',
                        data: data,
                        onChanged: (patch) =>
                            setState(() => data.addAll(patch)),
                        preview: (emails) async => {
                              'canManage': true,
                              'recipients': [
                                for (final email in emails)
                                  {
                                    'email': email,
                                    'kind': 'member',
                                    'role': 'editor'
                                  }
                              ]
                            }))))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OccasionTeamInvitation.roleReadOnly').last);
    await tester.pumpAndSettle();
    expect(occasionSetupInviteRole(data, 'one@example.org'), 'read_only');
    expect(data['sendTeamInvitations'], isFalse);
    data['sendTeamInvitations'] = true;
    await tester.enterText(find.byType(TextField), ' NEW@example.org ');
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(data['teamInviteEmails'], ['one@example.org', 'new@example.org']);
    expect(data['sendTeamInvitations'], isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary editor cannot look up recipients or add invitations',
      (tester) async {
    final patches = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
        home: Scaffold(
            body: OccasionSetupInvitations(
                draftId: 'draft',
                data: const {},
                onChanged: patches.add,
                preview: (_) async =>
                    {'canManage': false, 'recipients': []}))));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('OccasionTeamInvitation.managerRequired'), findsOneWidget);
    expect(patches, isEmpty);
  });

  testWidgets('review shows each selected role and does not opt into sending',
      (tester) async {
    bool? choice;
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
        home: Scaffold(
            body: OccasionSetupInvitationsSummary(data: {
      'teamInviteEmails': ['read@example.org'],
      'teamInviteRoles': {'read@example.org': 'read_only'}
    }, onSendChanged: (value) => choice = value))));
    expect(find.text('read@example.org - OccasionTeamInvitation.roleReadOnly'),
        findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    expect(choice, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    expect(choice, isTrue);
  });
}

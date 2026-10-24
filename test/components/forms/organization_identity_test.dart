import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/models/form_bundle.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/models/verified_organization_identity.dart';
import 'package:fstapp/components/forms/widgets_view/organization_identity_footer.dart';
import 'package:fstapp/components/unit/verification/db_unit_verification.dart';
import 'package:fstapp/components/unit/verification/unit_legal_profile.dart';
import 'package:fstapp/components/unit/verification/unit_legal_profile_section.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

const identity = <String, dynamic>{
  'unitId': 1,
  'revision': 3,
  'legalName': 'Kulturní spolek',
  'countryCode': 'CZ',
  'registrationNumber': '01234567',
  'address': {'street': 'Ulice 1', 'city': 'Praha', 'postalCode': '11000'},
  'contactEmail': 'info@example.test'
};
void main() {
  WidgetEnvironmentFixture.register();
  final translations = {
    'OrganizationVerification': {
      for (final k in [
        'title',
        'publicNotice',
        'verified',
        'organizer',
        'showDetails',
        'close',
        'explanation',
        'address',
        'legalName',
        'countryCode',
        'registrationNumber',
        'vatId',
        'street',
        'city',
        'postalCode',
        'contactEmail',
        'phone',
        'website',
        'revision',
        'unverified',
        'pending',
        'save',
        'submit',
        'preview',
        'reload',
        'saveFirst',
        'conflict',
        'saved',
        'loading',
        'saving',
        'completeFirst',
        'noPermission'
      ])
        k: k
    },
    'Common': {'close': 'Close'}
  };
  WidgetEnvironmentFixture env() => WidgetEnvironmentFixture(
      locale: const Locale('en'), translations: translations);
  test(
      'strict projection remains read only across bundle and editor operations',
      () {
    expect(VerifiedOrganizationIdentity.tryParse(null), isNull);
    expect(VerifiedOrganizationIdentity.tryParse(identity)?.verifiedAt, isNull);
    const verifiedAt = '2026-10-18T10:30:00+00:00';
    expect(
        VerifiedOrganizationIdentity.tryParse(
            {...identity, 'verifiedAt': verifiedAt})?.verifiedAt,
        verifiedAt);
    for (final invalid in [false, 123, 'invalid date']) {
      expect(
          VerifiedOrganizationIdentity.tryParse(
              {...identity, 'verifiedAt': invalid}),
          isNull);
    }
    expect(VerifiedOrganizationIdentity.tryParse({...identity, 'revision': 0}),
        isNull);
    expect(VerifiedOrganizationIdentity.tryParse({...identity, 'address': {}}),
        isNull);
    final bundle = FormBundle.fromJson(
        {'id': 5, 'title': 'Form', 'organizationIdentity': identity});
    expect(bundle.organizationIdentity?.legalName, 'Kulturní spolek');
    expect(
        bundle
            .withDefinition(
                FormDefinition.fromJson({'id': 5, 'title': 'Changed'}))
            .organizationIdentity,
        same(bundle.organizationIdentity));
    expect(bundle.toJson().containsKey('organizationIdentity'), isFalse);
    expect(
        FormEditorDraft.fromBundle(bundle)
            .toEditedJson()
            .containsKey('organizationIdentity'),
        isFalse);
  });
  test('service sends exact revisions and identity whitelist without retry',
      () async {
    final calls = <Map<String, dynamic>>[];
    final db = DbUnitVerification(rpc: (name, params) async {
      calls.add({'name': name, ...params});
      return {
        'code': 409,
        'profile': {...identity, 'status': 'pending'}
      };
    });
    final p = UnitLegalProfile.fromJson({...identity, 'status': 'unverified'});
    final result = await db
        .save(p, {...identity, 'status': 'verified', 'reviewNote': 'spoof'});
    expect(result.code, 409);
    expect(calls, hasLength(1));
    expect(calls.single['p_expected_revision'], 3);
    expect((calls.single['p_profile'] as Map).keys,
        unorderedEquals(UnitLegalProfile.fields));
    await db.review(p, 'approve', source: 'Checked registry and authority');
    expect(calls.last['p_expected_revision'], 3);
    expect(calls.last['p_decision'], 'approve');
  });
  testWidgets('unbroken legal name fits a 320px viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await env().pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: OrganizationIdentityFooter(
                    identity: VerifiedOrganizationIdentity.tryParse(
                        {...identity, 'legalName': 'W' * 200})))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
        tester.getRect(find.byType(TextButton)).right, lessThanOrEqualTo(320));
  });

  testWidgets('footer detail preserves draft and null projection hides it',
      (tester) async {
    final fixture = env();
    final controller = TextEditingController(text: 'Draft');
    addTearDown(controller.dispose);
    await fixture.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: Column(children: [
          TextField(controller: controller),
          OrganizationIdentityFooter(
              identity: VerifiedOrganizationIdentity.tryParse(identity))
        ]))));
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.text('info@example.test'), findsOneWidget);
    expect(controller.text, 'Draft');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(controller.text, 'Draft');
    await fixture.pumpWidget(tester,
        const MaterialApp(home: OrganizationIdentityFooter(identity: null)));
    expect(find.byType(TextButton), findsNothing);
  });
  testWidgets(
      'revision conflict keeps local draft and never submits it automatically',
      (tester) async {
    final calls = <String>[];
    final db = DbUnitVerification(rpc: (name, params) async {
      calls.add(name);
      return {
        'code': name == 'save_unit_legal_profile' ? 409 : 200,
        'profile': {
          ...identity,
          'revision': name == 'save_unit_legal_profile' ? 4 : 3,
          'status': 'unverified'
        }
      };
    });
    await env().pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: UnitLegalProfileSection(
                        unitId: 1, canEdit: true, service: db)))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Local draft');
    await tester.ensureVisible(find.text('save'));
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    expect(find.text('Local draft'), findsOneWidget);
    expect(find.text('conflict'), findsOneWidget);
    expect(calls.where((v) => v == 'save_unit_legal_profile'), hasLength(1));
    expect(calls, isNot(contains('submit_unit_verification')));
  });
}

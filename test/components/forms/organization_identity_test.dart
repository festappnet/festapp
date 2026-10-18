import 'dart:async';
import 'package:fstapp/components/unit/verification/ares_lookup_service.dart';
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

class _AresLookup extends AresLookupService {
  _AresLookup(this.callback);
  final Future<AresCompany> Function(String) callback;
  @override
  Future<AresCompany> lookup(String ico) => callback(ico);
}

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
        'organizationDetails',
        'contactDetails',
        'countryHelp',
        'aresLookup',
        'aresLoading',
        'aresHelp',
        'aresLoaded',
        'aresReplaceTitle',
        'aresReplaceDescription',
        'aresReplace',
        'aresInvalidIco',
        'aresNotFound',
        'aresUnavailable',
        'aresInvalidResponse',
        'discardTitle',
        'discardDescription',
        'discard',
        'cancel',
        'countryLabel',
        'countryCzechia',
        'countrySlovakia',
        'countryOther',
        'publicNotice',
        'verified',
        'organizer',
        'verifiedDescription',
        'pendingDescription',
        'verifiedOn',
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
    await tester.enterText(
        find.byKey(const ValueKey('legal-profile-legalName')), 'Local draft');
    await tester.pump();
    await tester.ensureVisible(find.text('save'));
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    expect(find.text('Local draft'), findsOneWidget);
    expect(find.text('conflict'), findsOneWidget);
    expect(calls.where((v) => v == 'save_unit_legal_profile'), hasLength(1));
    expect(calls, isNot(contains('submit_unit_verification')));
  });
  for (final status in ['pending', 'verified']) {
    testWidgets(
        '$status legal profile shows a prominent status on mobile in dark mode',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = DbUnitVerification(
          rpc: (_, __) async => {
                'code': 200,
                'profile': {
                  ...identity,
                  'status': status,
                  if (status == 'verified') 'verifiedAt': '2026-10-18T12:00:00Z'
                },
              });
      await WidgetEnvironmentFixture(
              locale: const Locale('en'), translations: translations)
          .pumpWidget(
        tester,
        MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
                body: SingleChildScrollView(
              child: UnitLegalProfileSection(
                  unitId: 1, canEdit: true, service: db),
            ))),
      );
      await tester.pumpAndSettle();
      final banner =
          find.byKey(const ValueKey('legal-profile-verification-status'));
      expect(banner.hitTestable(), findsOneWidget);
      expect(find.descendant(of: banner, matching: find.text(status)),
          findsOneWidget);
      expect(
          find.descendant(
              of: banner, matching: find.text('${status}Description')),
          findsOneWidget);
      expect(
          find
              .descendant(of: banner, matching: find.text('reload'))
              .hitTestable(),
          findsOneWidget);
      expect(
          find.byIcon(
              status == 'verified' ? Icons.verified_outlined : Icons.schedule),
          findsOneWidget);
      if (status == 'verified') {
        expect(find.textContaining('verifiedOn:'), findsOneWidget);
        expect(find.text('publicNotice'), findsNothing);
        expect(find.text('pending'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final dirty in [false, true]) {
    testWidgets(
        'returning to legal profile refreshes approval while preserving unsaved drafts ($dirty)',
        (tester) async {
      var status = 'pending';
      var reads = 0;
      final db = DbUnitVerification(rpc: (_, __) async {
        reads++;
        return {
          'code': 200,
          'profile': {...identity, 'status': status}
        };
      });
      await WidgetEnvironmentFixture(
              locale: const Locale('en'), translations: translations)
          .pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
          child: UnitLegalProfileSection(unitId: 1, canEdit: true, service: db),
        ))),
      );
      await tester.pumpAndSettle();
      if (dirty) {
        final name = find.byKey(const ValueKey('legal-profile-legalName'));
        await tester.ensureVisible(name);
        await tester.enterText(name, 'Unsaved organizer');
        await tester.pump();
      }
      status = 'verified';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(reads, dirty ? 1 : 2);
      if (dirty) {
        expect(
            tester
                .widget<TextFormField>(
                    find.byKey(const ValueKey('legal-profile-legalName')))
                .controller!
                .text,
            'Unsaved organizer');
      } else {
        expect(find.text('verifiedDescription'), findsOneWidget);
        expect(find.text('pending'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  Finder field(String name) => find.byKey(ValueKey('legal-profile-$name'));
  String value(WidgetTester tester, String name) =>
      tester.widget<TextFormField>(field(name)).controller!.text;

  testWidgets(
      'ARES fills an editable draft and preserves contacts changed during lookup',
      (tester) async {
    final calls = <String>[];
    final reply = Completer<AresCompany>();
    final db = DbUnitVerification(rpc: (name, params) async {
      calls.add(name);
      return {
        'code': 200,
        'profile': {
          ...identity,
          'revision': 0,
          'status': 'unverified',
          'legalName': '',
          'countryCode': '',
          'registrationNumber': '',
          'address': {'street': '', 'city': '', 'postalCode': ''},
        }
      };
    });
    await env().pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
          child: UnitLegalProfileSection(
              unitId: 1,
              canEdit: true,
              service: db,
              aresService: _AresLookup((ico) {
                expect(ico, '00006947');
                return reply.future;
              })),
        ))));
    await tester.pumpAndSettle();
    expect(find.text('aresLookup'), findsOneWidget,
        reason: 'new Czech profiles expose lookup immediately');
    expect(find.textContaining('revision'), findsNothing);
    await tester.enterText(field('registrationNumber'), '00006947');
    await tester.tap(find.text('aresLookup'));
    await tester.pump();
    expect(tester.widget<TextFormField>(field('legalName')).enabled, false);
    expect(tester.widget<TextFormField>(field('contactEmail')).enabled, true);
    await tester.enterText(field('contactEmail'), 'changed@example.test');
    reply.complete(const AresCompany(
        legalName: 'Ministerstvo financí',
        countryCode: 'CZ',
        registrationNumber: '00006947',
        vatId: 'CZ00006947',
        street: 'Letenská 525/15',
        city: 'Praha',
        postalCode: '11800'));
    await tester.pumpAndSettle();
    expect(value(tester, 'legalName'), 'Ministerstvo financí');
    expect(value(tester, 'street'), 'Letenská 525/15');
    expect(value(tester, 'contactEmail'), 'changed@example.test');
    expect(find.text('aresLoaded'), findsOneWidget);
    expect(calls, ['get_unit_legal_profile'],
        reason: 'registry facts are never saved or verified automatically');
    expect(find.text('unverified'), findsOneWidget);
  });

  testWidgets(
      'ARES replacement requires consent and reload protects the local draft',
      (tester) async {
    var loads = 0;
    final db = DbUnitVerification(rpc: (name, params) async {
      expect(name, 'get_unit_legal_profile');
      loads++;
      return {
        'code': 200,
        'profile': {...identity, 'status': 'unverified'}
      };
    });
    await env().pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
          child: UnitLegalProfileSection(
              unitId: 1,
              canEdit: true,
              service: db,
              aresService: _AresLookup((_) async => const AresCompany(
                  legalName: 'Registry name',
                  countryCode: 'CZ',
                  registrationNumber: '00006947',
                  street: 'Street 1',
                  city: 'Praha',
                  postalCode: '11000'))),
        ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('aresLookup'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('aresReplaceTitle'), findsOneWidget);
    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();
    expect(value(tester, 'legalName'), 'Kulturní spolek');
    await tester.enterText(field('legalName'), 'Local draft');
    await tester.ensureVisible(find.text('reload'));
    await tester.tap(find.text('reload'));
    await tester.pumpAndSettle();
    expect(find.text('discardTitle'), findsOneWidget);
    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();
    expect(value(tester, 'legalName'), 'Local draft');
    expect(loads, 1);
  });

  testWidgets('back protects a draft until discard is confirmed',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final db = DbUnitVerification(
        rpc: (_, __) async => {
              'code': 200,
              'profile': {...identity, 'status': 'unverified'}
            });
    await env().pumpWidget(tester,
        MaterialApp(navigatorKey: navigator, home: const Text('Settings')));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
            body: SingleChildScrollView(
                child: UnitLegalProfileSection(
                    unitId: 1, canEdit: true, service: db))))));
    await tester.pumpAndSettle();
    await tester.enterText(field('legalName'), 'Local draft');
    await tester.pump();
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('discardTitle'), findsOneWidget);
    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();
    expect(value(tester, 'legalName'), 'Local draft');
    await navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('discard'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(UnitLegalProfileSection), findsNothing);
  });

  for (final width in [320.0, 1000.0]) {
    testWidgets('legal profile fits $width pixels with enlarged dark text',
        (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = DbUnitVerification(
          rpc: (_, __) async => {
                'code': 200,
                'profile': {...identity, 'status': 'unverified'}
              });
      await env().pumpWidget(
          tester,
          MaterialApp(
              theme: ThemeData(brightness: Brightness.dark),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!),
              home: Scaffold(
                  body: Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: UnitLegalProfileSection(
                                  unitId: 1, canEdit: true, service: db)))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(field('registrationNumber')).right,
          lessThanOrEqualTo(width));
      expect(
          tester.getRect(field('legalName')).right, lessThanOrEqualTo(width));
    });
  }
}

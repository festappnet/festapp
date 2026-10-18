import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/unit/verification/db_unit_verification.dart';
import 'package:fstapp/components/unit/verification/verification_queue.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

const profile = <String, dynamic>{
  'unitId': 8,
  'revision': 2,
  'status': 'pending',
  'legalName': 'Example organizer',
  'countryCode': 'CZ',
  'registrationNumber': '06455361',
  'address': {'street': 'Street 1', 'city': 'Praha', 'postalCode': '11000'},
  'contactEmail': 'public@example.invalid',
};

void main() {
  WidgetEnvironmentFixture.register();
  final translations = {
    'OrganizationVerification': {
      for (final key in [
        'queue',
        'pending',
        'revision',
        'registrationNumber',
        'address',
        'contactEmail',
        'reviewNotice',
        'feedback',
        'note',
        'source',
        'approve',
        'reject',
        'revoke',
        'retry',
        'failed',
        'required',
        'invalid',
        'saving',
        'conflict',
        'uncertain',
        'countryCode',
        'legalName',
        'sourceRequiredLabel',
        'sourceHelp',
        'sourceRequired',
        'feedbackRequiredLabel',
        'feedbackHelp',
        'feedbackRequired',
        'noteOptionalLabel',
        'sourceTooLong',
        'reviewTextTooLong',
      ])
        key: key,
    },
    'Common': {'close': 'Close'},
  };
  Finder field(String key) => find.byKey(ValueKey('verification-review-$key'));
  Future<void> open(WidgetTester tester, DbUnitVerification db,
      {double textScale = 1}) async {
    final navigator = GlobalKey<NavigatorState>();
    await WidgetEnvironmentFixture(
            locale: const Locale('en'), translations: translations)
        .pumpWidget(
            tester,
            MaterialApp(
              navigatorKey: navigator,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!),
              home: const Scaffold(body: Text('Review queue')),
            ));
    showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => UnitVerificationReviewDialog(unitId: 8, db: db));
    await tester.pumpAndSettle();
  }

  Future<void> click(WidgetTester tester, String action) async {
    await tester.ensureVisible(find.text(action));
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'approval identifies and focuses the missing evidence field without RPC',
      (tester) async {
    final calls = <String>[];
    await open(tester, DbUnitVerification(rpc: (name, params) async {
      calls.add(name);
      return {'code': 200, 'profile': profile};
    }));
    await click(tester, 'approve');
    final source = tester.widget<TextField>(field('source'));
    expect(source.decoration!.errorText, 'sourceRequired');
    expect(source.focusNode!.hasFocus, true);
    expect(find.text('retry'), findsNothing);
    expect(calls, ['get_unit_legal_profile']);
    expect(tester.widget<TextField>(field('feedback')).decoration!.errorText,
        isNull);
    await tester.enterText(
        field('source'), 'Registry entry and representative authority checked');
    await tester.pump();
    expect(tester.widget<TextField>(field('source')).decoration!.errorText,
        isNull);
  });

  testWidgets(
      'approval sends evidence with the displayed revision and optional empty feedback',
      (tester) async {
    Map<String, dynamic>? submitted;
    await open(tester, DbUnitVerification(rpc: (name, params) async {
      if (name == 'get_unit_legal_profile')
        return {'code': 200, 'profile': profile};
      expect(name, 'review_unit_verification');
      submitted = params;
      return {'code': 200};
    }));
    await tester.enterText(
        field('source'), 'Registry and representative authority checked');
    await click(tester, 'approve');
    expect(submitted?['p_decision'], 'approve');
    expect(submitted?['p_expected_revision'], 2);
    expect(submitted?['p_source'],
        'Registry and representative authority checked');
    expect(submitted?['p_feedback'], '');
    expect(find.byType(UnitVerificationReviewDialog), findsNothing);
    expect(find.text('Review queue'), findsOneWidget);
  });

  testWidgets(
      'rejection asks for applicant feedback and does not require approval evidence',
      (tester) async {
    Map<String, dynamic>? submitted;
    await open(tester, DbUnitVerification(rpc: (name, params) async {
      if (name == 'get_unit_legal_profile')
        return {'code': 200, 'profile': profile};
      submitted = params;
      return {'code': 200};
    }));
    await click(tester, 'reject');
    final feedback = tester.widget<TextField>(field('feedback'));
    expect(feedback.decoration!.errorText, 'feedbackRequired');
    expect(feedback.focusNode!.hasFocus, true);
    expect(tester.widget<TextField>(field('source')).decoration!.errorText,
        isNull);
    await tester.enterText(
        field('feedback'), 'Please provide representative authority');
    await click(tester, 'reject');
    expect(submitted?['p_decision'], 'reject');
    expect(submitted?['p_source'], '');
  });

  testWidgets(
      'server source validation is attached to the field and preserves the draft',
      (tester) async {
    await open(
        tester,
        DbUnitVerification(
            rpc: (name, params) async => name == 'get_unit_legal_profile'
                ? {'code': 200, 'profile': profile}
                : {
                    'code': 422,
                    'fieldErrors': {'reviewSource': 'REQUIRED'}
                  }));
    await tester.enterText(field('source'), 'Evidence draft');
    await tester.enterText(field('note'), 'Private note draft');
    await click(tester, 'approve');
    expect(tester.widget<TextField>(field('source')).decoration!.errorText,
        'sourceRequired');
    expect(tester.widget<TextField>(field('source')).focusNode!.hasFocus, true);
    expect(tester.widget<TextField>(field('note')).controller!.text,
        'Private note draft');
    expect(find.text('retry'), findsNothing);
  });

  testWidgets('incomplete profile is not blamed on a valid evidence field',
      (tester) async {
    await open(
        tester,
        DbUnitVerification(
            rpc: (name, params) async => name == 'get_unit_legal_profile'
                ? {'code': 200, 'profile': profile}
                : {
                    'code': 422,
                    'fieldErrors': {'profile': 'INCOMPLETE_PROFILE'}
                  }));
    await tester.enterText(field('source'), 'Evidence checked');
    await click(tester, 'approve');
    expect(find.text('invalid'), findsOneWidget);
    expect(find.text('retry'), findsNothing);
    expect(tester.widget<TextField>(field('source')).decoration!.errorText,
        isNull);
    expect(tester.widget<TextField>(field('source')).controller!.text,
        'Evidence checked');
  });

  testWidgets('oversized private note is identified before sending',
      (tester) async {
    final calls = <String>[];
    await open(tester, DbUnitVerification(rpc: (name, params) async {
      calls.add(name);
      return {'code': 200, 'profile': profile};
    }));
    await tester.enterText(field('source'), 'Registry and authority checked');
    await tester.enterText(field('note'), 'x' * 4001);
    await click(tester, 'approve');
    expect(tester.widget<TextField>(field('note')).decoration!.errorText,
        'reviewTextTooLong');
    expect(calls, ['get_unit_legal_profile']);
  });

  testWidgets('review error fits a narrow viewport with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(
        tester,
        DbUnitVerification(
            rpc: (_, __) async => {'code': 200, 'profile': profile}),
        textScale: 1.5);
    await click(tester, 'approve');
    expect(tester.takeException(), isNull);
    expect(tester.getRect(field('source')).right, lessThanOrEqualTo(320));
    expect(tester.widget<TextField>(field('source')).focusNode!.hasFocus, true);
  });
}

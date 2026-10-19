import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/users/views/occasion_team_invitation_page.dart';

import '../../support/fixtures/localization_log_fixture.dart';

void main() {
  String key(String value) => 'OccasionTeamInvitation.$value';
  Map<String, dynamic> invitation({bool existing = false}) => {
        'email': 'editor@example.test',
        'title': 'Example event',
        'unitTitle': 'Example organizer',
        'organization': AppConfig.organization,
        'link': 'example-event',
        'existingAccount': existing,
        'accepted': false,
        'role': 'editor',
      };

  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });

  Future<void> show(
    WidgetTester tester,
    OccasionTeamInvitationPage page,
  ) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  testWidgets('empty token does not call read or acceptance', (tester) async {
    var reads = 0;
    var accepts = 0;
    await show(
      tester,
      OccasionTeamInvitationPage(
        token: '',
        loader: (_) async {
          reads++;
          return invitation();
        },
        acceptor: (_, {password}) async {
          accepts++;
          return {'accepted': true};
        },
        isLoggedIn: () => false,
      ),
    );
    expect(reads, 0);
    expect(accepts, 0);
    expect(find.text(key('invalid')), findsOneWidget);
  });

  testWidgets('rejects a capability for another tenant', (tester) async {
    await show(
      tester,
      OccasionTeamInvitationPage(
        token: 'capability',
        loader: (_) async => {...invitation(), 'organization': -1},
        isLoggedIn: () => false,
      ),
    );
    expect(find.text(key('invalid')), findsOneWidget);
    expect(find.text('editor@example.test'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('existing account requires login and never accepts on read', (
    tester,
  ) async {
    var accepts = 0;
    await show(
      tester,
      OccasionTeamInvitationPage(
        token: 'capability',
        loader: (_) async => invitation(existing: true),
        acceptor: (_, {password}) async {
          accepts++;
          return {'accepted': true};
        },
        isLoggedIn: () => false,
      ),
    );
    expect(accepts, 0);
    expect(find.text(key('login')), findsOneWidget);
    expect(find.text(key('accept')), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('new account requires own password and matching confirmation', (
    tester,
  ) async {
    var accepts = 0;
    String? chosenPassword;
    await show(
      tester,
      OccasionTeamInvitationPage(
        token: 'capability',
        loader: (_) async => invitation(),
        acceptor: (_, {password}) async {
          accepts++;
          chosenPassword = password;
          return {'accepted': true, 'newAccount': true};
        },
        isLoggedIn: () => false,
      ),
    );
    expect(accepts, 0);
    await tester.tap(find.text(key('createAndAccept')));
    await tester.pumpAndSettle();
    expect(accepts, 0);
    expect(find.text(key('passwordShort')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('invitation-password')),
      'chosen-by-user',
    );
    await tester.enterText(
      find.byKey(const ValueKey('invitation-confirmation')),
      'another-password',
    );
    await tester.tap(find.text(key('createAndAccept')));
    await tester.pumpAndSettle();
    expect(accepts, 0);
    expect(find.text(key('passwordMismatch')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('invitation-confirmation')),
      'chosen-by-user',
    );
    await tester.tap(find.text(key('createAndAccept')));
    await tester.pumpAndSettle();
    expect(accepts, 1);
    expect(chosenPassword, 'chosen-by-user');
    expect(find.text(key('accountCreated')), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets(
    'failed acceptance preserves values and offers a deliberate retry',
    (tester) async {
      var accepts = 0;
      await show(
        tester,
        OccasionTeamInvitationPage(
          token: 'capability',
          loader: (_) async => invitation(),
          acceptor: (_, {password}) async {
            accepts++;
            throw StateError('Unavailable');
          },
          isLoggedIn: () => false,
        ),
      );
      final password = find.byKey(const ValueKey('invitation-password'));
      final confirmation = find.byKey(
        const ValueKey('invitation-confirmation'),
      );
      await tester.enterText(password, 'chosen-by-user');
      await tester.enterText(confirmation, 'chosen-by-user');
      await tester.tap(find.text(key('createAndAccept')));
      await tester.pumpAndSettle();
      expect(accepts, 1);
      expect(find.text(key('acceptFailed')), findsOneWidget);
      expect(
        tester.widget<TextFormField>(password).controller!.text,
        'chosen-by-user',
      );
      expect(
        tester.widget<TextFormField>(confirmation).controller!.text,
        'chosen-by-user',
      );
    },
  );

  testWidgets('read-only permission is visible before accepting',
      (tester) async {
    await show(
        tester,
        OccasionTeamInvitationPage(
          token: 'capability',
          loader: (_) async =>
              {...invitation(existing: true), 'role': 'read_only'},
          isLoggedIn: () => false,
        ));
    expect(find.textContaining(key('roleReadOnly')), findsOneWidget);
    expect(find.textContaining(key('roleEditor')), findsNothing);
  });

  testWidgets(
    'signed-in existing account explicitly accepts without password',
    (tester) async {
      var accepts = 0;
      String? received = 'not-called';
      await show(
        tester,
        OccasionTeamInvitationPage(
          token: 'capability',
          loader: (_) async => invitation(existing: true),
          acceptor: (_, {password}) async {
            accepts++;
            received = password;
            return {'accepted': true, 'newAccount': false};
          },
          isLoggedIn: () => true,
        ),
      );
      expect(accepts, 0);
      expect(find.text(key('switchAccount')), findsOneWidget);
      await tester.tap(find.text(key('accept')));
      await tester.pumpAndSettle();
      expect(accepts, 1);
      expect(received, isNull);
      expect(find.text(key('accepted')), findsOneWidget);
    },
  );
}

import '../../support/fixtures/localization_log_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/widgets/profile_legal_link.dart';
import 'package:url_launcher/link.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  test('localhost debug links resolve to static legal documents', () {
    expect(
      resolveProfileLegalUri(
        Uri.parse('https://csmostrava.festapp.net/privacy/'),
        appUri: Uri.parse('http://localhost:8081/csmostrava2026/user'),
        useLocalStaticDocument: true,
      ),
      Uri.parse('http://localhost:8081/privacy/index.html'),
    );
  });

  testWidgets('profile legal item exposes a real same-window link',
      (tester) async {
    final uri = Uri.parse('https://csmostrava.festapp.net/privacy/');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileLegalLink(label: 'Privacy', uri: uri),
        ),
      ),
    );

    final link = tester.widget<Link>(find.byType(Link));
    expect(link.uri, uri);
    expect(link.target, LinkTarget.self);
    expect(find.text('Privacy'), findsOneWidget);
  });

  testWidgets('legal links stay lightweight and expose all public documents',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppLegalLinks(
            overrideUris: <Uri>[
              Uri.parse('https://example.festapp.net/privacy/'),
              Uri.parse('https://example.festapp.net/privacy/choices/'),
              Uri.parse('https://example.festapp.net/terms/'),
              Uri.parse('https://example.festapp.net/support/'),
            ],
          ),
        ),
      ),
    );

    final uris = tester
        .widgetList<Link>(find.byType(Link))
        .map((link) => link.uri)
        .toList();

    expect(uris, <Uri>[
      Uri.parse('https://example.festapp.net/privacy/'),
      Uri.parse('https://example.festapp.net/privacy/choices/'),
      Uri.parse('https://example.festapp.net/terms/'),
      Uri.parse('https://example.festapp.net/support/'),
    ]);
    expect(find.byType(Wrap), findsOneWidget);
    expect(find.byType(TextButton), findsNWidgets(4));
    expect(find.byType(Card), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });

  test('web legal links preserve a safe return path to the app', () {
    expect(
      resolveProfileLegalUri(
        Uri.parse('https://csmostrava.festapp.net/privacy/'),
        appUri: Uri.parse(
          'https://csmostrava.festapp.net/csmostrava2026/user?tab=profile',
        ),
        includeReturnTo: true,
      ),
      Uri.parse(
        'https://csmostrava.festapp.net/privacy/?returnTo=%2Fcsmostrava2026%2Fuser%3Ftab%3Dprofile',
      ),
    );
  });
}

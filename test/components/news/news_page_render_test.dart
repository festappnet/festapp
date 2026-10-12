import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/components/news/news_page.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  testWidgets('renders news before live view counts arrive', (tester) async {
    final messages = ClientSyncProjection.projectNews(content: {
      'news': [
        {
          'id': 1,
          'message': '<p>News must remain visible</p>',
          'createdAt': '2026-10-09T08:00:00Z',
          'aggregateVersion': 1,
        },
      ],
    });
    expect(messages.single.views, isNull);

    // Exercise the page's actual loaded-state build, without starting network
    // synchronization or tab listeners. The public content can arrive before
    // the separate live projection that supplies view counts.
    final dynamic pageState = NewsPage().createState();
    pageState.newsMessages = messages;
    // Avoid a localization dependency: the timestamp is optional in the UI.
    messages.single.createdAt = null;
    final router = AppRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp(
      home: StackRouterScope(
        controller: router,
        stateHash: 0,
        child: Builder(builder: (context) => pageState.build(context) as Widget),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(EditableHtmlField), findsOneWidget);
    expect(find.text('News must remain visible', findRichText: true),
        findsOneWidget);
    expect(find.byIcon(Icons.remove_red_eye), findsNothing);
  });
}

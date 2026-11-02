import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:festapp_core/time.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/occasion/occasion_creation_notice.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/unit_occasion_dashboard.dart';
import 'package:fstapp/components/unit/views/occasion_created_highlight.dart';
import 'package:fstapp/components/unit/views/occasion_edit_card.dart';
import 'package:fstapp/components/unit/views/occasions_screen.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/theme_config.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fixtures/client_command_response_fixture.dart';
import '../../support/fixtures/local_app_storage_fixture.dart';
import '../../support/fixtures/root_supabase_fixture.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late RootSupabaseFixture backend;
  late LocalAppStorageFixture storage;
  late WidgetEnvironmentFixture environment;
  late FutureOr<http.Response> Function(http.Request) respond;
  final previewBoundary = GlobalKey();

  Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
    for (var frame = 0; frame < 30 && !ready(); frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(ready(), isTrue);
  }

  Map<String, dynamic> event(int id, String title, {int year = 2030}) => {
    'id': id,
    'unit': 7,
    'title': title,
    'start_time': DateTime.utc(year, 6, 1).toIso8601String(),
    'end_time': DateTime.utc(year, 6, 2).toIso8601String(),
    'data': {'timezone': 'Europe/Prague'},
  };
  Map<String, dynamic> dashboard(List<Map<String, dynamic>> events) => {
    'unit_id': 7,
    'occasions': events,
    'drafts': [],
    'app_landing': null,
    'demo_catalog': {'items': [], 'hasOwnWork': true},
  };
  http.Response reply(http.Request request, Object body, {int status = 200}) =>
      http.Response(
        jsonEncode(body),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );

  Future<void> showList(
    WidgetTester tester,
    List<Map<String, dynamic>> events, {
    bool reducedMotion = false,
  }) async {
    await environment.pumpWidget(
      tester,
      MaterialApp(
        theme: const bool.fromEnvironment('OCCASION_LIST_PREVIEW')
            ? ThemeConfig.theme()
            : null,
        builder: (context, child) => DependencyMaterialBridge.builder(
          context,
          MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reducedMotion),
            child: child!,
          ),
        ),
        home: RepaintBoundary(
          key: previewBoundary,
          child: OccasionsScreen(
            unit: UnitModel(id: 7),
            initialDashboard: UnitOccasionDashboard.fromJson(dashboard(events)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUpAll(() async {
    OccasionTimeContext.initializeTimeZones();
    await initializeDateFormatting('cs');
    if (const bool.fromEnvironment('OCCASION_LIST_PREVIEW')) {
      final font = FontLoader(ThemeConfig.fontFamily);
      font.addFont(rootBundle.load('fonts/Futura PT Book.ttf'));
      font.addFont(rootBundle.load('fonts/Futura PT Medium.ttf'));
      await font.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
    environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    storage = await LocalAppStorageFixture.open();
    backend = await RootSupabaseFixture.open((request) => respond(request));
  });
  setUp(() {
    OccasionCreationNotice.take(7);
    respond = (request) => throw StateError('Unexpected ${request.url.path}');
  });
  tearDownAll(() async {
    await backend.dispose();
    await storage.dispose();
  });

  test('copy adapter keeps committed ID when media completion fails', () async {
    respond = (request) {
      expectSync(request.url.path, '/rest/v1/rpc/start_occasion_lifecycle');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expectSync(body['p_action'], 'copy');
      return reply(
        request,
        commandResponseFixture(body['p_command_id'], data: {'occasionId': 42}),
      );
    };
    // No signed-in media token: DB copy exists, media completion is recoverable.
    final result = await DbOccasions.duplicateOccasion(1, targetUnitId: 7);
    expect(result.occasionId, 42);
    expect(result.mediaCopied, isFalse);
  });

  testWidgets(
    'refresh failure retains cards and pending creation until retry',
    (tester) async {
      final pending = Completer<http.Response>();
      late http.Request request;
      respond = (incoming) {
        request = incoming;
        return pending.future;
      };
      await showList(tester, [event(1, 'Original')]);
      OccasionCreationNotice.record(7, 42);
      final refresh = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      final loading = refresh.onRefresh();
      await tester.pump();
      expect(find.text('Original'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      pending.complete(reply(request, {'message': 'Unavailable'}, status: 400));
      await loading;
      await tester.pumpAndSettle();
      expect(find.text('Original'), findsOneWidget);
      expect(OccasionCreationNotice.peek(7), 42);
      expect(find.byType(OccasionCreatedHighlight), findsNothing);

      respond = (incoming) => reply(
        incoming,
        dashboard([event(1, 'Original'), event(42, 'Confirmed copy')]),
      );
      await tester.tap(find.textContaining(CommonStrings.retry));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Confirmed copy'), findsOneWidget);
      expect(find.byType(OccasionCreatedHighlight), findsOneWidget);
      expect(OccasionCreationNotice.peek(7), isNull);
      await tester.pump(const Duration(seconds: 4));
    },
  );

  for (final reducedMotion in [false, true]) {
    testWidgets('copy clears filter and reveals its actual past-year card '
        '(reduced motion: $reducedMotion)', (tester) async {
      final existing = [
        for (var id = 1; id <= 24; id++) event(id, 'Upcoming $id'),
      ];
      await showList(tester, existing, reducedMotion: reducedMotion);
      final search = tester.widget<TextField>(find.byType(TextField)).controller!;
      await tester.enterText(find.byType(TextField), 'Upcoming 1');
      OccasionCreationNotice.record(7, 42);
      respond = (request) => reply(
        request,
        dashboard([...existing, event(42, 'Older copy', year: 2020)]),
      );
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      // Let the post-frame scroll start its ticker before advancing its time.
      // The header may leave the lazy viewport once the actual card is revealed.
      await pumpUntil(tester,
          () => find.text('Older copy').hitTestable().evaluate().isNotEmpty);
      expect(search.text, isEmpty);
      expect(find.text('Older copy').hitTestable(), findsOneWidget);
      expect(find.byType(OccasionCreatedHighlight), findsOneWidget);
      expect(OccasionCreationNotice.peek(7), isNull);
      if (reducedMotion &&
          const bool.fromEnvironment('OCCASION_LIST_PREVIEW')) {
        await tester.runAsync(() async {
          final image = await (previewBoundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('/tmp/occasion-list-copy-preview.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pump(const Duration(seconds: 4));
    });
  }

  testWidgets(
    'copy is guarded during destination lookup and cancel unlocks it',
    (tester) async {
      final pending = Completer<http.Response>();
      late http.Request request;
      var requests = 0;
      respond = (incoming) {
        expectSync(incoming.url.path, '/rest/v1/rpc/get_occasion_copy_units');
        requests++;
        request = incoming;
        return pending.future;
      };
      await showList(tester, [event(1, 'Original')]);
      final copy = tester
          .widget<OccasionEditCard>(find.byType(OccasionEditCard))
          .onCreateCopy!;
      copy();
      copy();
      await pumpUntil(tester, () => requests == 1);
      expect(requests, 1);
      expect(
        tester
            .widget<OccasionEditCard>(find.byType(OccasionEditCard))
            .isCopying,
        isTrue,
      );
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .enabled,
        isFalse,
      );
      pending.complete(
        reply(request, [
          {'id': 7, 'title': 'Destination'},
        ]),
      );
      await pumpUntil(tester,
          () => find.text(CommonStrings.storno).hitTestable().evaluate().isNotEmpty);
      await tester.tap(find.text(CommonStrings.storno));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OccasionEditCard>(find.byType(OccasionEditCard))
            .isCopying,
        isFalse,
      );
      expect(find.text('Original'), findsOneWidget);
      expect(requests, 1);
    },
  );
}

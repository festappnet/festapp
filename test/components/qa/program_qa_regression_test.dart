import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/program.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/_shared/admin_strings.dart';
import 'package:fstapp/components/_shared/app_panel_helper.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/features/editors/schedule_feature_editor.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/components/features/schedule_feature.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/schedule/event_grid_record.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/speakers/admin/speaker_editor_dialog.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/fixtures/root_supabase_fixture.dart';
import '../../support/fixtures/rights_context_fixture.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late RootSupabaseFixture backend;
  late WidgetEnvironmentFixture environment;
  late RightsContextFixture rights;
  final preferences = SharedPreferencesAsyncPlatform.instance;
  final saves = <Map<String, dynamic>>[];
  setUpAll(() async {
    tzdata.initializeTimeZones();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync()));
    backend = await RootSupabaseFixture.open((request) {
      if (request.url.path.endsWith('/save_speaker_client_sync_v1')) {
        saves.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
            jsonEncode({'code': '42501', 'message': 'Save rejected'}), 403,
            headers: {'content-type': 'application/json'});
      }
      // Existing speakers load a place catalog on dialog open.
      return http.Response('[]', 200,
          headers: {'content-type': 'application/json'});
    });
  });
  tearDownAll(() async {
    await backend.dispose();
    SharedPreferencesAsyncPlatform.instance = preferences;
  });
  setUp(() {
    rights = RightsContextFixture();
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasion: OccasionModel(
            id: 1,
            title: 'QA',
            isOpen: true,
            isHidden: false,
            isPromoted: false),
        unit: UnitModel(id: 1, title: 'Unit'),
        occasionUser:
            OccasionUserModel(isEditorView: true, isEditorOrderView: true),
        isAdmin: true);
    saves.clear();
  });
  tearDown(() => rights.dispose());

  test('a new program row can render and decode an absent optional place', () {
    expect(DataGridHelper.getValueFromFormatted(null), '');
    expect(DataGridHelper.getValueFromFormatted('12:Hall: A'), 'Hall: A');
    for (final place in [null, '', '---', '12:Hall']) {
      final event = EventGridRecord.decode({
        EventGridRecord.startDateColumn: '2026-10-23',
        EventGridRecord.endDateColumn: '2026-10-23',
        EventModel.startTimeColumn: '10:00',
        EventModel.endTimeColumn: '11:00',
        EventModel.placeColumn: place,
      }, timeContext: OccasionTimeContext(tz.UTC));
      expect(event.place?.id, place == '12:Hall' ? 12 : null);
    }
  });

  testWidgets('remove and add keeps codes and visible row identities unique',
      (tester) async {
    final feature = ScheduleFeature();
    final form = GlobalKey<FormState>();
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: Form(
                        key: form,
                        child: Builder(
                            builder: (context) =>
                                feature.buildSettingsEditor(context)))))));
    await tester.tap(find.text(FeaturesStrings.titleEventTypes));
    await tester.pumpAndSettle();
    Future<void> add() async {
      final button = find.text(FeaturesStrings.buttonAddEventType);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Finder codes() => find.ancestor(
        of: find.text(FeaturesStrings.labelEventTypeCode),
        matching: find.byType(TextFormField));
    await add();
    await add();
    final remove = find.byTooltip(FeaturesStrings.tooltipRemoveEventType).first;
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await add();
    expect(form.currentState!.validate(), isTrue);
    form.currentState!.save();
    expect(feature.eventTypes.map((type) => type.code).toSet().length, 2);
    expect(
        tester.widget<TextFormField>(codes().first).initialValue, 'new_type_2');

    await tester.ensureVisible(codes().last);
    await tester.enterText(codes().last, 'new_type_2');
    await tester.pump();
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text(FeaturesStrings.eventTypeCodeAlreadyUsed), findsWidgets);
    await tester.ensureVisible(find.text(FeaturesStrings.titleEventTypes));
    await tester.tap(find.text(FeaturesStrings.titleEventTypes));
    await tester.pumpAndSettle();
    expect(form.currentState!.validate(), isFalse);
    await tester.tap(find.text(FeaturesStrings.titleEventTypes));
    await tester.pumpAndSettle();
    await tester.enterText(codes().last, '  ');
    await tester.pump();
    expect(form.currentState!.validate(), isFalse);
    await tester.enterText(codes().last, '  workshop  ');
    await tester.pump();
    expect(form.currentState!.validate(), isTrue);
    form.currentState!.save();
    expect(feature.eventTypes.map((type) => type.code),
        ['new_type_2', 'workshop']);
  });

  testWidgets('failed speaker save and cancel leave the shared model intact',
      (tester) async {
    final speaker = SpeakerModel(
        id: 8,
        title: 'Eva QA',
        aggregateVersion: 4,
        data: {'custom': true},
        topics: [2]);
    await environment.pumpWidget(
        tester,
        MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showDialog<Object>(
                            context: context,
                            builder: (_) => SpeakerEditorDialog(
                                speaker: speaker, topics: const [])),
                        child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Eva - draft');
    await tester.tap(find.text(CommonStrings.save));
    await tester.pumpAndSettle();
    expect(saves, hasLength(1));
    expect((saves.single['p_speaker'] as Map)['title'], 'Eva - draft');
    expect(saves.single['p_expected_version'], 4);
    expect(speaker.title, 'Eva QA');
    expect(speaker.data, {'custom': true});
    expect(speaker.topics, [2]);
    await tester.tap(find.text(CommonStrings.storno));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Eva QA'), findsOneWidget);
    expect(find.text('Eva - draft'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final shell in [AdminRoute.name, ReservationsRoute.name]) {
    for (final section in ['schedule', 'info']) {
      testWidgets(
          'context picker recognizes $shell/$section from a nested page',
          (tester) async {
        final router = _PanelRouter(shell, section);
        addTearDown(router.dispose);
        await tester.binding.setSurfaceSize(const Size(1440, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await environment.pumpWidget(
            tester,
            MaterialApp.router(
                routerConfig: router.config(
                    deepLinkBuilder: (_) =>
                        DeepLink.path('/event/shell/$section'))));
        await tester.pumpAndSettle();
        final label = shell == AdminRoute.name
            ? CommonStrings.eventManagement
            : AdministrationStrings.reservations;
        expect(find.text(label), findsOneWidget);
        expect(find.text(AdministrationStrings.viewApp), findsNothing);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text(AdministrationStrings.viewApp), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

class _PanelRouter extends RootStackRouter {
  _PanelRouter(this.shell, this.section);
  final String shell;
  final String section;
  @override
  List<AutoRoute> get routes => [
        AutoRoute(
            page: PageInfo(shell, builder: (_) => const AutoRouter()),
            path: '/event/shell',
            children: [
              AutoRoute(
                  page: PageInfo('NestedPage',
                      builder: (_) => Builder(
                          builder: (context) => Scaffold(
                              appBar: AppPanelHelper.buildDesktopAdminAppBar(
                                  context, null, null)))),
                  path: section)
            ])
      ];
}

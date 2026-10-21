import '../../support/fixtures/widget_environment_fixture.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'dart:convert';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/views/form_capacity_settings.dart';
import 'package:fstapp/components/forms/views/waitlist_offers_dialog.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/theme_config.dart';

late WidgetEnvironmentFixture _environment;

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Futura')
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    _environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
  });
  Future<void> open(WidgetTester tester, FormEditorDraft form,
      {double width = 800, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _environment.pumpWidget(
        tester,
        RepaintBoundary(
            key: const ValueKey('preview'),
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeConfig.theme(brightness: Brightness.dark),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: Scaffold(
                    body: FormCapacitySettings(
                        form: form, canEdit: true, onChanged: () {})))));
    await tester.tap(find.text(WaitlistStrings.settings));
    await tester.pumpAndSettle();
  }

  for (final tickets in [false, true]) {
    testWidgetsWithEnvironment(
        () => _environment, 'capacity labels match ticket feature $tickets',
        (tester) async {
      final previous = RightsService.occasionLinkModelNotifier.value;
      addTearDown(
          () => RightsService.occasionLinkModelNotifier.value = previous);
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasion: OccasionModel(
            isOpen: true,
            isHidden: false,
            isPromoted: false,
            features: [TicketFeature(code: 'ticket', isEnabled: tickets)]),
      );
      await open(tester, FormEditorDraft(participantCapacity: 10));
      expect(
          find.text(tickets
              ? WaitlistStrings.limitTickets
              : WaitlistStrings.limitCapacity),
          findsOneWidget);
      expect(
          find.text(WaitlistStrings.text(
              tickets ? 'capacityTickets' : 'capacityRegistrations')),
          findsOneWidget);
    });
  }

  for (final enabled in [false, true]) {
    testWidgetsWithEnvironment(
        () => _environment, 'stored blueprint uses enabled feature $enabled', (
      tester,
    ) async {
      final previous = RightsService.occasionLinkModelNotifier.value;
      addTearDown(
        () => RightsService.occasionLinkModelNotifier.value = previous,
      );
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasion: OccasionModel(
          isOpen: true,
          isHidden: false,
          isPromoted: false,
          features: [SimpleFeature(code: 'blueprint', isEnabled: enabled)],
        ),
      );
      final form = FormEditorDraft(blueprint: 42);
      await open(tester, form);
      expect(
        find.byType(FormCapacityDialog),
        enabled ? findsNothing : findsOneWidget,
      );
      expect(
        find.text(WaitlistStrings.blueprintCapacity),
        enabled ? findsOneWidget : findsNothing,
      );
      if (!enabled) {
        await tester.tap(find.byType(SwitchListTile).first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, '50');
        await tester.tap(find.text(WaitlistStrings.applySettings));
        await tester.pumpAndSettle();
        expect(form.definition.participantCapacity, 50);
        expect(form.definition.blueprint, 42);
      }
    });
  }

  testWidgetsWithEnvironment(() => _environment,
      'cancel leaves draft untouched; apply updates serialized draft',
      (tester) async {
    final form = FormEditorDraft(participantCapacity: 100, data: {});
    final before = jsonEncode(form.toEditedJson());
    await open(tester, form);
    await tester.enterText(find.byType(TextFormField).first, '120');
    await tester.tap(find.text(CommonStrings.storno));
    await tester.pumpAndSettle();
    expect(jsonEncode(form.toEditedJson()), before);
    await tester.tap(find.text(WaitlistStrings.settings));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '120');
    await tester.tap(find.text(WaitlistStrings.enabled));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '1,5');
    await tester.tap(find.text(WaitlistStrings.applySettings));
    await tester.pumpAndSettle();
    expect(form.definition.participantCapacity, 120);
    expect(form.definition.waitlistEnabled, isTrue);
    expect(form.definition.waitlistOfferDurationSeconds, 5400);
    expect(jsonEncode(form.toEditedJson()), isNot(before));
  });

  testWidgetsWithEnvironment(() => _environment,
      'active entries lock destructive changes and committed capacity validates',
      (tester) async {
    final form = FormEditorDraft(
        participantCapacity: 100,
        waitlistEnabled: true,
        capacity: FormCapacityModel.fromJson(
            {'waitingPeople': 2, 'occupiedPeople': 70, 'offeredPlaces': 10}));
    await open(tester, form);
    final switches =
        tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    expect(switches.first.onChanged, isNull);
    expect(switches.last.onChanged, isNull);
    await tester.enterText(find.byType(TextFormField).first, '79');
    await tester.tap(find.text(WaitlistStrings.applySettings));
    await tester.pumpAndSettle();
    expect(find.text(WaitlistStrings.text('CAPACITY_BELOW_COMMITTED')),
        findsOneWidget);
    expect(form.definition.participantCapacity, 100);
  });

  testWidgetsWithEnvironment(() => _environment,
      'waiting priority reservations count toward occupancy and minimum capacity',
      (tester) async {
    final form = FormEditorDraft(
        participantCapacity: 11,
        waitlistEnabled: true,
        capacity: FormCapacityModel.fromJson({
          'limit': 11,
          'occupiedPeople': 9,
          'offeredPlaces': 0,
          'waitingPeople': 1,
          'heldForWaiting': 1
        }));
    expect(form.definition.capacity!.occupiedPlaces, 10);
    await open(tester, form);
    await tester.enterText(find.byType(TextFormField).first, '9');
    await tester.tap(find.text(WaitlistStrings.applySettings));
    await tester.pumpAndSettle();
    expect(find.text(WaitlistStrings.text('CAPACITY_BELOW_COMMITTED')),
        findsOneWidget);
    expect(form.definition.participantCapacity, 11);
  });

  testWidgetsWithEnvironment(() => _environment,
      'occupancy includes all waiting registrations above capacity without inflating its minimum',
      (tester) async {
    final capacity = FormCapacityModel.fromJson({
      'limit': 10,
      'occupiedPeople': 9,
      'offeredPlaces': 1,
      'waitingPeople': 1,
      'heldForWaiting': 0
    });
    expect(capacity.occupiedPlaces, 11);
    expect(capacity.minimumCapacity, 10);
    final form = FormEditorDraft(
        participantCapacity: 10, waitlistEnabled: true, capacity: capacity);
    await open(tester, form);
    await tester.tap(find.text(WaitlistStrings.applySettings));
    await tester.pumpAndSettle();
    expect(find.text(WaitlistStrings.text('CAPACITY_BELOW_COMMITTED')),
        findsNothing);
    expect(form.definition.participantCapacity, 10);
    await _environment.pumpWidget(
        tester,
        MaterialApp(
            home: Scaffold(
                body: FormCapacitySettings(
                    form: form, canEdit: false, onChanged: () {}))));
    expect(find.textContaining('Obsazenost: 11 z 10'), findsOneWidget);
  });

  testWidgetsWithEnvironment(() => _environment,
      'unlimited switch removes capacity and waitlist together',
      (tester) async {
    final form =
        FormEditorDraft(participantCapacity: 100, waitlistEnabled: true);
    await open(tester, form);
    await tester.tap(find.text(WaitlistStrings.limitCapacity));
    await tester.pumpAndSettle();
    await tester.tap(find.text(WaitlistStrings.applySettings));
    await tester.pumpAndSettle();
    expect(form.definition.participantCapacity, isNull);
    expect(form.definition.waitlistEnabled, isFalse);
  });

  for (final width in [320.0, 800.0]) {
    testWidgetsWithEnvironment(
        () => _environment, 'dialog is scrollable at $width with large text',
        (tester) async {
      await open(tester,
          FormEditorDraft(participantCapacity: 150, waitlistEnabled: true),
          width: width, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(WaitlistStrings.durationHours));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final tickets in [false, true]) {
    testWidgetsWithEnvironment(() => _environment,
        'readonly capacity shows server counts with ticket mode $tickets',
        (tester) async {
      final previous = RightsService.occasionLinkModelNotifier.value;
      addTearDown(
          () => RightsService.occasionLinkModelNotifier.value = previous);
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          occasion: OccasionModel(
              isOpen: true,
              isHidden: false,
              isPromoted: false,
              features: [TicketFeature(code: 'ticket', isEnabled: tickets)]));
      final form = FormEditorDraft(
          participantCapacity: 11,
          waitlistEnabled: true,
          stats: FormStatsModel(total: 80),
          capacity: FormCapacityModel.fromJson(
              {'occupiedPeople': 10, 'offeredPlaces': 1, 'limit': 11}));
      await _environment.pumpWidget(
          tester,
          MaterialApp(
              home: Scaffold(
                  body: FormCapacitySettings(
                      form: form,
                      canEdit: false,
                      onChanged: () => fail('readonly draft changed')))));
      expect(find.textContaining('Obsazenost: 11 z 11'), findsOneWidget);
      expect(
          find.textContaining('${WaitlistStrings.capacity}: 12'), findsNothing);
      expect(
          find.textContaining(
              '${tickets ? 'Platné vstupenky' : 'Platné přihlášky'}:'),
          findsNothing);
      expect(form.definition.capacity!.occupiedPeople, 10);
      expect(
          find.byWidgetPredicate(
              (widget) => widget is Text && widget.semanticsLabel != null),
          findsNothing);
      expect(
          find.textContaining('Místa v platných nabídkách: 1'), findsOneWidget);
      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
    });
  }

  for (final mode in ['blueprint', 'disabled', 'enabled']) {
    testWidgetsWithEnvironment(
        () => _environment, 'zero offer counts stay hidden ($mode)',
        (tester) async {
      final blueprint = mode == 'blueprint';
      final previous = RightsService.occasionLinkModelNotifier.value;
      addTearDown(
          () => RightsService.occasionLinkModelNotifier.value = previous);
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          occasion: OccasionModel(
              isOpen: true,
              isHidden: false,
              isPromoted: false,
              features: [
            SimpleFeature(code: 'blueprint', isEnabled: blueprint)
          ]));
      final form = FormEditorDraft(
          blueprint: blueprint ? 5 : null,
          participantCapacity: blueprint ? null : 12,
          waitlistEnabled: mode == 'enabled',
          capacity: FormCapacityModel.fromJson(
              {'occupiedPeople': 11, 'offeredPlaces': 0}));
      await _environment.pumpWidget(
          tester,
          MaterialApp(
              home: Scaffold(
                  body: FormCapacitySettings(
                      form: form, canEdit: true, onChanged: () {}))));
      expect(find.textContaining(': 11'), findsOneWidget);
      expect(find.textContaining(WaitlistStrings.offeredPlacesCount),
          findsNothing);
      expect(
          tester.widget<ListTile>(find.byType(ListTile)).enabled, !blueprint);
      if (!blueprint) {
        await tester.tap(find.text(WaitlistStrings.settings));
        await tester.pumpAndSettle();
        expect(find.textContaining(WaitlistStrings.offeredPlacesCount),
            findsNothing);
      }
    });
  }

  testWidgetsWithEnvironment(() => _environment,
      'admin occupancy includes server offer holds and their release',
      (tester) async {
    for (final offered in [1, 0]) {
      final capacity = FormCapacityModel.fromJson({
        'enabled': true,
        'occupiedPeople': 10,
        'offeredPlaces': offered,
        'limit': 11,
        'remainingPublic': 0,
      });
      final form = FormEditorDraft(
          participantCapacity: 11, waitlistEnabled: true, capacity: capacity);
      await _environment.pumpWidget(
          tester,
          MaterialApp(
              home: Scaffold(
                  body: Column(children: [
            FormCapacitySettings(form: form, canEdit: false, onChanged: () {}),
            WaitlistCapacitySummary(capacity: capacity),
          ]))));
      expect(find.textContaining('Obsazenost: ${10 + offered} z 11'),
          findsNWidgets(2));
      expect(capacity.occupiedPeople, 10);
      expect(capacity.remainingPublic, 0);
    }
  });

  testWidgetsWithEnvironment(() => _environment, 'visual review artifact',
      (tester) async {
    await open(tester,
        FormEditorDraft(participantCapacity: 150, waitlistEnabled: true),
        width: 600);
    if (Platform.environment['CAPACITY_UI_ARTIFACT'] case final path?) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('preview')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}

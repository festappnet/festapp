import 'dart:convert';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/models/form_capacity_model.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/views/form_capacity_settings.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/theme_config.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Futura')
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    Localization.load(const Locale('cs'),
        translations: Translations(
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>));
  });
  Future<void> open(WidgetTester tester, FormModel form,
      {double width = 800, double scale = 1}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
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

  testWidgets('cancel leaves draft untouched; apply updates serialized draft',
      (tester) async {
    final form = FormModel(participantCapacity: 100, data: {});
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
    expect(form.participantCapacity, 120);
    expect(form.waitlistEnabled, isTrue);
    expect(form.waitlistOfferDurationSeconds, 5400);
    expect(jsonEncode(form.toEditedJson()), isNot(before));
  });

  testWidgets(
      'active entries lock destructive changes and committed capacity validates',
      (tester) async {
    final form = FormModel(
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
    expect(form.participantCapacity, 100);
  });

  testWidgets('unlimited switch removes capacity and waitlist together',
      (tester) async {
    final form = FormModel(participantCapacity: 100, waitlistEnabled: true);
    await open(tester, form);
    await tester.tap(find.text(WaitlistStrings.limitCapacity));
    await tester.pumpAndSettle();
    await tester.tap(find.text(WaitlistStrings.applySettings));
    await tester.pumpAndSettle();
    expect(form.participantCapacity, isNull);
    expect(form.waitlistEnabled, isFalse);
  });

  for (final width in [320.0, 800.0]) {
    testWidgets('dialog is scrollable at $width with large text',
        (tester) async {
      await open(
          tester, FormModel(participantCapacity: 150, waitlistEnabled: true),
          width: width, scale: 2);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(WaitlistStrings.durationHours));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final tickets in [false, true]) {
    testWidgets(
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
      final form = FormModel(
          participantCapacity: 12,
          waitlistEnabled: true,
          stats: FormStatsModel(total: 80),
          capacity: FormCapacityModel.fromJson(
              {'occupiedPeople': 11, 'offeredPlaces': 1}));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: FormCapacitySettings(
                  form: form,
                  canEdit: false,
                  onChanged: () => fail('readonly draft changed')))));
      expect(
          find.textContaining(
              '${tickets ? 'Platné vstupenky' : 'Platné přihlášky'}: 11'),
          findsOneWidget);
      expect(
          find.textContaining('Místa v platných nabídkách: 1'), findsOneWidget);
      expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
    });
  }

  for (final mode in ['blueprint', 'disabled', 'enabled']) {
    testWidgets('zero offer counts stay hidden ($mode)',
        (tester) async {
      final blueprint = mode == 'blueprint';
      final form = FormModel(
          blueprint: blueprint ? 5 : null,
          participantCapacity: blueprint ? null : 12,
          waitlistEnabled: mode == 'enabled',
          capacity: FormCapacityModel.fromJson(
              {'occupiedPeople': 11, 'offeredPlaces': 0}));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: FormCapacitySettings(
                  form: form, canEdit: true, onChanged: () {}))));
      expect(find.textContaining(': 11'), findsOneWidget);
      expect(find.textContaining(WaitlistStrings.offeredPlacesCount), findsNothing);
      expect(tester.widget<ListTile>(find.byType(ListTile)).enabled, !blueprint);
      if (!blueprint) {
        await tester.tap(find.text(WaitlistStrings.settings));
        await tester.pumpAndSettle();
        expect(find.textContaining(WaitlistStrings.offeredPlacesCount), findsNothing);
      }
    });
  }

  testWidgets('visual review artifact', (tester) async {
    await open(
        tester, FormModel(participantCapacity: 150, waitlistEnabled: true),
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

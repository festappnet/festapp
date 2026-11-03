import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:fstapp/components/fonts/font_family_picker.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance_panel.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_blueprint_preview.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_communication.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_completed.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_invitations.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_result.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_sales.dart';
import 'package:fstapp/components/occasion/setup/blueprint_setup_layout_draft.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() async {
    await (FontLoader(
      'Futura',
    )..addFont(rootBundle.load('fonts/Futura PT Book.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ),
    );
  });
  Future<void> pump(WidgetTester tester, Widget child) =>
      environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Futura'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      );

  test('sale dates allow an explicit end after the event and preserve publication intent', () {
    final data = <String, dynamic>{
      'formEnabled': true,
      'saleMode': 'immediate',
      'end': '2030-01-01T20:00:00Z',
      'saleEnd': '2030-01-02T20:00:00Z',
    };
    expect(OccasionSetupSales.valid(data, DateTime.utc(2029)), isTrue);
    expect(OccasionSetupSales.publishesToCatalog(data), isTrue);
    data['listPubliclyOnPublish'] = false;
    expect(OccasionSetupSales.publishesToCatalog(data), isFalse);
    data['saleMode'] = 'scheduled';
    data['saleStart'] = '2030-01-03T20:00:00Z';
    expect(OccasionSetupSales.valid(data, DateTime.utc(2029)), isFalse);
  });

  test('completion preserves independent canonical occasion flags', () {
    const result = OccasionSetupResult(
      occasionId: 1,
      unit: 1,
      link: 'ples',
      title: 'Ples',
      isOpen: true,
      isHidden: true,
      isPromoted: true,
    );
    expect(result.isPublished, isFalse);
    expect(result.occasion.isOpen, isTrue);
    expect(result.occasion.isHidden, isTrue);
    expect(result.occasion.isPromoted, isTrue);
  });

  test('seating summary excludes decorations and stale seat bindings at the configuration owner', () {
    final configuration = SetupBlueprintConfiguration({
      'blueprintLayoutDraft': {
        'layout': {
          'nodes': [
            {'id': 'hall', 'kind': 'section', 'label': 'Sál'},
            {'id': 'table10', 'kind': 'table', 'label': 'Stůl 10'},
            {'id': 'table2', 'kind': 'table', 'label': 'Stůl 2'},
            {'id': 'empty', 'kind': 'table', 'label': '3'},
            {'id': 'seat1', 'kind': 'seat'},
            {'id': 'seat2', 'kind': 'seat'},
          ],
        },
        'seatBindings': [
          {'nodeId': 'seat1', 'groupNodeId': 'table10'},
          {'nodeId': 'seat2', 'groupNodeId': 'table2'},
          {'nodeId': 'deleted', 'groupNodeId': 'hall'},
        ],
      },
    });
    expect(configuration.groupTitles, ['Stůl 2', 'Stůl 10']);
  });

  testWidgetsWithEnvironment(
    () => environment,
    'pending collaborator is committed once before continuing and invalid input blocks navigation',
    (tester) async {
      final key = GlobalKey<OccasionSetupInvitationsState>();
      final data = <String, dynamic>{
        'teamInviteEmails': <String>[],
        'sendTeamInvitations': true,
      };
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, update) => OccasionSetupInvitations(
            key: key,
            draftId: 'draft',
            data: data,
            onChanged: (patch) => update(() => data.addAll(patch)),
            preview: (emails) async => {
              'canManage': true,
              'recipients': <dynamic>[],
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        ' Spoluorganizator@example.org ',
      );
      expect(key.currentState!.commitPending(), isTrue);
      await tester.pumpAndSettle();
      expect(data['teamInviteEmails'], ['spoluorganizator@example.org']);
      expect(data['sendTeamInvitations'], isFalse);
      expect(key.currentState!.commitPending(), isTrue);
      expect(data['teamInviteEmails'], hasLength(1));
      await tester.enterText(find.byType(TextField), 'neplatna-adresa');
      expect(key.currentState!.commitPending(), isFalse);
      await tester.pump();
      expect(data['teamInviteEmails'], hasLength(1));
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'tone explicitly distinguishes inheritance from both overrides',
    (tester) async {
      final data = <String, dynamic>{
        'communicationTone': 'inherit',
        'replyToMode': 'inherit',
        'formEnabled': false,
      };
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, update) => OccasionSetupCommunication(
            draftId: 'draft',
            data: data,
            onChanged: (patch) => update(() => data.addAll(patch)),
            loader: () async => {
              'defaults': {
                'replyTo': 'poradatel@example.org',
                'tone': 'informal',
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      var chips = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .toList();
      expect(chips.map((c) => c.selected), [true, false, false]);
      expect(
        (chips.first.label as Text).data,
        contains(FormStrings.toneInformal),
      );
      await tester.tap(find.text(FormStrings.toneFormal));
      await tester.pumpAndSettle();
      expect(data['communicationTone'], 'formal');
      await tester.tap(find.byType(ChoiceChip).first);
      await tester.pumpAndSettle();
      expect(data['communicationTone'], 'inherit');
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'canonical font search selects a Google family beyond the preset list',
    (tester) async {
      String selected = 'Roboto';
      await pump(
        tester,
        OccasionSetupAppearancePanel(
          onPresetSelected: (_) {},
          fontFamily: selected,
          fontFamilies: const ['Roboto', 'Manrope'],
          previewFontStyle: (family) async =>
              const TextStyle(fontFamily: 'Futura'),
          onFontChanged: (family) => selected = family,
          primaryColor: const Color(0xff4465a6),
          secondaryColor: const Color(0xff4465a6),
          gradient: false,
          onPrimaryChanged: (_) {},
          onSecondaryChanged: (_) {},
          onGradientChanged: (_) {},
          formPreview: const SizedBox(),
        ),
      );
      expect(find.byType(FontFamilyPicker), findsOneWidget);
      await tester.tap(find.text(FormStrings.moreFonts));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Manrope');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manrope').last);
      await tester.pumpAndSettle();
      expect(selected, 'Manrope');
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'embedded plan uses canonical geometry and retains loaded resources across rebuilds',
    (tester) async {
      var calls = 0;
      final document = VenueLayoutTemplates.byId('blank').create();
      late StateSetter update;
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return OccasionSetupBlueprintPreview(
              document: document,
              loadResources: () async {
                calls++;
                return {};
              },
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<VenueLayoutViewer>(find.byType(VenueLayoutViewer))
            .document,
        same(document),
      );
      update(() {});
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  testWidgetsWithEnvironment(
    () => environment,
    'completion has one main action and shows saved publication truth',
    (tester) async {
      final capture = GlobalKey();
      await environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Futura'),
          home: RepaintBoundary(
            key: capture,
            child: const OccasionSetupCompleted(
              result: OccasionSetupResult(
                occasionId: 1,
                unit: 1,
                link: 'myslivecky-ples',
                title: 'Myslivecký ples',
                formLink: 'myslivecky-ples-2030',
                saleMode: 'immediate',
                isOpen: true,
                isHidden: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Spravovat akci'), findsOneWidget);
      expect(find.text('Zveřejnit akci podle nastavení'), findsNothing);
      expect(find.text('Zveřejnění akce bylo uloženo.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final frame =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/festapp-wizard-completed.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        frame.dispose();
      });
    },
  );
}

import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/images/image_area.dart';
import 'package:fstapp/theme_config.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:super_editor/super_editor.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_email_templates.dart';
import 'package:fstapp/components/email_templates/views/email_template_card.dart';
import 'package:fstapp/components/email_templates/email_templates_strings.dart';
import 'package:fstapp/components/email_templates/views/email_templates_settings_page.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import '../../support/fixtures/root_supabase_fixture.dart';

const codes = [
  'TICKET_ORDER_CONFIRMATION',
  'TICKET_ORDER_PAYMENT_DONE',
  'TICKET_ORDER_REMINDER',
  'TICKET_ORDER_STORNO',
  'TICKET_ORDER_UPDATE'
];
Map<String, dynamic> catalog(Map<String, dynamic> draft) => {
      'emailScope': {
        'unit': {'id': 1, 'title': 'Unit'},
        'organization': {'id': 3, 'title': 'Org'}
      },
      'authoringContext': {'senderAddress': 'sender@example.invalid'},
      'previewContext': {'title': 'My event', 'products': []},
      'emailTemplates': [
        for (final code in codes)
          {
            'code': code,
            'customized':
                (draft['emailTemplateOverrides'] as Map?)?.containsKey(code) ??
                    false,
            'template': {
              'code': code,
              'subject': 'Subject',
              'html': '<p>Body</p>',
              'unit': 1,
              ...?((draft['emailTemplateOverrides'] as Map?)?[code] as Map?)
            },
          }
      ],
    };
void main() {
  WidgetEnvironmentFixture.register();
  late RootSupabaseFixture backend;
  setUpAll(() async {
    await (FontLoader('Futura')
          ..addFont(rootBundle.load('fonts/Futura PT Book.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    backend = await RootSupabaseFixture.open(
        (request) => http.Response('{}', 200, request: request));
  });
  tearDownAll(() async => backend.dispose());
  for (final size in [const Size(320, 800), const Size(1200, 900)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all five email cards fit $size at scale $scale',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final translations =
            jsonDecode(File('assets/translations/cs.json').readAsStringSync());
        await WidgetEnvironmentFixture(
                locale: const Locale('cs'), translations: translations)
            .pumpWidget(
                tester,
                MaterialApp(builder: DependencyMaterialBridge.builder,
                    theme: ThemeConfig.theme(brightness: Brightness.dark),
                    home: MediaQuery(
                        data: MediaQueryData(
                            size: size, textScaler: TextScaler.linear(scale)),
                        child: Scaffold(
                            body: SingleChildScrollView(
                                child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: OccasionSetupEmailTemplates(
                                        unitId: 1,
                                        draft: {},
                                        loadPreview: (draft) async =>
                                            catalog(draft),
                                        onChanged: (_) {})))))));
        await tester.pumpAndSettle();
        expect(find.byType(EmailTemplateCard), findsNWidgets(5));
        expect(tester.takeException(), isNull);
        expect(
            find.byKey(const ValueKey('setup-email-banner')), findsOneWidget);
        if (size.width == 1200 && scale == 1) {
          expect(tester.getSize(find.byType(EmailTemplateCard).first).height,
              lessThan(200));
        }
        const screenshots =
            String.fromEnvironment('SETUP_EMAIL_SCREENSHOT_DIR');
        if (screenshots.isNotEmpty && scale == 1) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byType(RepaintBoundary).first);
          final image = (await tester.runAsync(() => boundary.toImage()))!;
          final bytes = (await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.png)))!;
          Directory(screenshots).createSync(recursive: true);
          File('$screenshots/emails-${size.width.toInt()}.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
          image.dispose();
        }
        for (final element in find.byType(EmailTemplateCard).evaluate()) {
          final box = element.renderObject! as RenderBox;
          final point = box.localToGlobal(Offset.zero);
          expect(point.dx + box.size.width, lessThanOrEqualTo(size.width));
        }
      });
    }
  }
  testWidgets('banner changes stay in the draft beneath compact email cards',
      (tester) async {
    final patches = <Map<String, dynamic>>[];
    await WidgetEnvironmentFixture(
            locale: const Locale('cs'),
            translations: jsonDecode(
                    File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>)
        .pumpWidget(
            tester,
            MaterialApp(builder: DependencyMaterialBridge.builder,
                home: Scaffold(
                    body: SingleChildScrollView(
                        child: OccasionSetupEmailTemplates(
                            unitId: 1,
                            draft: const {},
                            loadPreview: (draft) async => catalog(draft),
                            onChanged: patches.add)))));
    await tester.pumpAndSettle();
    final banner = find.byKey(const ValueKey('setup-email-banner'));
    expect(
        tester.getTopLeft(banner).dy,
        greaterThan(
            tester.getBottomLeft(find.byType(EmailTemplateCard).last).dy));
    tester.widget<ImageArea>(banner).onRemove();
    await tester.pumpAndSettle();
    expect(patches.single, {'emailBanner': null});
    expect(
        backend.requests
            .where((r) => r.url.path.contains('update_entity_email_banner')),
        isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'editing saves only a draft override and never updates the unit template',
      (tester) async {
    final translations =
        jsonDecode(File('assets/translations/cs.json').readAsStringSync());
    final draft = <String, dynamic>{};
    final patches = <Map<String, dynamic>>[];
    await WidgetEnvironmentFixture(
            locale: const Locale('cs'), translations: translations)
        .pumpWidget(
            tester,
            MaterialApp(builder: DependencyMaterialBridge.builder,
                home: Scaffold(
                    body: SingleChildScrollView(
                        child: OccasionSetupEmailTemplates(
                            draft: draft,
                            loadPreview: (value) async => catalog(draft),
                            onChanged: (patch) {
                              draft.addAll(patch);
                              patches.add(patch);
                            })))));
    await tester.pumpAndSettle();
    final card =
        tester.widget<EmailTemplateCard>(find.byType(EmailTemplateCard).first);
    card.onEdit();
    await tester.pumpAndSettle();
    expect(find.byType(EmailTemplateSettingsPage), findsOneWidget);
    expect(find.text(EmailTemplatesStrings.resetToDefault), findsNothing);
    final subject = tester
        .widgetList<RichHtmlEditor>(find.byType(RichHtmlEditor))
        .first
        .controller;
    final node = subject.editor.document.first as TextNode;
    subject.editor.execute([
      InsertTextRequest(
          documentPosition: DocumentPosition(
              nodeId: node.id, nodePosition: const TextNodePosition(offset: 0)),
          textToInsert: 'Edited ',
          attributions: {})
    ]);
    await tester.pump();
    await tester.tap(find.text('Uložit'));
    await tester.pumpAndSettle();
    expect(find.byType(EmailTemplateSettingsPage), findsNothing);
    expect(patches, hasLength(1));
    expect((draft['emailTemplateOverrides'] as Map)[codes.first]['subject'],
        'Edited Subject');
    expect(
        backend.requests.where((r) =>
            r.url.path.contains('update_email_template') ||
            r.url.path.contains('delete_entity_email_template')),
        isEmpty);
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/demo/demo_occasion_banner.dart';
import 'package:fstapp/components/occasion/demo/demo_occasion_strings.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/theme_config.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader(ThemeConfig.fontFamily)
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'));
    await loader.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    Localization.load(const Locale('cs'),
        translations: Translations(
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>));
  });
  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('mobile demo panel stays on one row: $dark/$width/$scale',
            (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 240);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
              demoReadOnly: true,
              occasion: OccasionModel(
                  id: 59,
                  isOpen: true,
                  isHidden: false,
                  isPromoted: false,
                  title: 'Ples pod hvězdami s dlouhým názvem ukázkové akce'));
          addTearDown(
              () => RightsService.occasionLinkModelNotifier.value = null);
          final frame = GlobalKey();
          await tester.pumpWidget(MaterialApp(
              theme: ThemeConfig.theme(
                  brightness: dark ? Brightness.dark : Brightness.light),
              home: MediaQuery(
                  data: MediaQueryData(
                      size: Size(width, 240),
                      textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(
                      key: frame,
                      child: DemoOccasionOverlay(
                          child: Scaffold(
                              body: Container(
                                  color: dark
                                      ? const Color(0xff111111)
                                      : const Color(0xffeeeeee)),
                              bottomNavigationBar:
                                  const SizedBox(height: 48)))))));
          await tester.pumpAndSettle();
          final back = find.widgetWithIcon(IconButton, Icons.arrow_back);
          final more = find.byType(PopupMenuButton<String>);
          final title = find.textContaining('Ples pod hvězdami');
          expect(tester.getCenter(back).dy, tester.getCenter(more).dy);
          expect(tester.getCenter(title).dy, tester.getCenter(back).dy);
          expect(tester.getSize(back).height, greaterThanOrEqualTo(48));
          expect(tester.getSize(more).height, greaterThanOrEqualTo(48));
          expect(tester.widget<Text>(title).maxLines, 1);
          expect(tester.widget<Text>(title).overflow, TextOverflow.ellipsis);
          expect(find.byType(FilledButton), findsNothing);
          if (width == 320 && scale == 1) {
            await tester.runAsync(() async {
              final image = await (frame.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await File(
                      '/tmp/demo-mobile-panel-${dark ? 'dark' : 'light'}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.tap(more);
          await tester.pumpAndSettle();
          expect(
              find.widgetWithText(
                  PopupMenuItem<String>, DemoOccasionStrings.copy),
              findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

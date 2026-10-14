import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/demo/demo_catalog.dart';
import 'package:fstapp/components/occasion/demo/demo_occasion_strings.dart';
import 'package:fstapp/components/occasion/demo/demo_occasions_section.dart';
import 'package:fstapp/components/unit/views/occasion_edit_card.dart';

void main() {
  setUpAll(() => Localization.load(const Locale('cs'),
      translations: Translations(
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>)));
  final catalog = DemoCatalog(hasOwnWork: true, items: [
    for (final entry in ['ball', 'concert', 'weekend'].indexed)
      DemoOccasion.fromJson({
        'id': entry.$1 + 1,
        'link': entry.$2,
        'demoKey': entry.$2,
        'title': 'Detailed ${entry.$2} title',
        'description': 'Description',
        'fixtureVersion': 'fixture',
        'data': <String, dynamic>{}
      }),
  ]);
  for (final own in [false, true]) {
    testWidgets(
        'demo cards follow current Unit occasions, not account-wide work ($own)',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      DemoOccasion? opened;
      DemoOccasion? copied;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: DemoOccasionsSection(
                  hasOwnOccasions: own,
                  load: () async => catalog,
                  onOpen: (item) async => opened = item,
                  onCreateCopy: (item) async => copied = item))));
      await tester.pumpAndSettle();
      expect(find.text(DemoOccasionStrings.heading), findsOneWidget);
      expect(
          find.byType(OccasionEditCard), own ? findsNothing : findsNWidgets(3));
      if (own) {
        await tester.tap(find.text(DemoOccasionStrings.heading));
        await tester.pumpAndSettle();
      }
      for (final title in [
        'Detailed ball title',
        'Detailed concert title',
        'Detailed weekend title'
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(
          find.text('Prohlédněte si hotovou akci a vytvořte si vlastní kopii.'),
          findsNothing);
      expect(find.text(DemoOccasionStrings.heading), findsOneWidget);
      await tester.tap(find.text('Detailed ball title'));
      await tester.pumpAndSettle();
      expect(opened?.key, 'ball');
      expect(opened?.title, 'Detailed ball title');
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      expect(find.text(DemoOccasionStrings.view), findsNothing);
      await tester.tap(find.text('Vytvořit kopii'));
      await tester.pumpAndSettle();
      expect(copied?.key, 'ball');
    });
  }
}

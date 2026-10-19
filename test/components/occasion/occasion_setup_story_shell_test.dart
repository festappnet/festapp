import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_story_shell.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Futura')
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'));
    await font.load();
  });
  for (final variant in [
    (name: 'mobile', size: const Size(375, 812), scale: 1.0, dark: false),
    (name: 'large-text', size: const Size(375, 812), scale: 2.0, dark: false),
    (name: 'landscape', size: const Size(812, 375), scale: 1.0, dark: false),
    (name: 'desktop', size: const Size(1440, 900), scale: 1.0, dark: true),
  ]) {
    testWidgets('story shell keeps navigation visible: ${variant.name}',
        (tester) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      var advances = 0;
      var leaves = 0;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            fontFamily: 'Futura',
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: variant.dark ? Brightness.dark : Brightness.light)),
        home: MediaQuery(
          data: MediaQueryData(
            size: variant.size,
            textScaler: TextScaler.linear(variant.scale),
            disableAnimations: true,
            padding: const EdgeInsets.only(top: 24, bottom: 24),
          ),
          child: RepaintBoundary(
            key: boundaryKey,
            child: Scaffold(
              body: OccasionSetupStoryShell(
                questionTitles: const [
                  'Jak chceš začít?',
                  'Jak se událost jmenuje?',
                  'Kdy začíná?',
                  'Kdy končí?',
                  'Jak má vypadat formulář?',
                  'Potřebuješ plánek?',
                  'Jak nastavíme platby?',
                  'Jak má vypadat vstupenka?',
                  'Chceš ověřit organizaci?',
                  'Je vše připravené?',
                ],
                currentIndex: 1,
                eventTitle: 'Koncept · Podzimní slavnost',
                status: 'Uloženo',
                readiness: 'Dokončené nastavení: 20 %',
                questionCount: 'Otázka 2 z 10',
                segmentStates: const ['Dokončeno', 'Právě teď', 'Následuje'],
                leaveLabel: 'Odejít',
                backLabel: 'Zpět',
                onLeave: () => leaves++,
                onBack: () {},
                primaryAction: FilledButton(
                  onPressed: () => advances++,
                  style:
                      FilledButton.styleFrom(minimumSize: const Size(160, 48)),
                  child: const Text('Pokračovat'),
                ),
                child: const TextField(
                  decoration: InputDecoration(labelText: 'Název události'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getBottomRight(find.byType(FilledButton)).dy,
          lessThan(variant.size.height - 24));
      await tester.tap(find.text('Pokračovat'));
      await tester.tap(find.byTooltip('Odejít'));
      expect(advances, 1);
      expect(leaves, 1);

      const screenshotDir = String.fromEnvironment('STORY_SCREENSHOT_DIR');
      if (screenshotDir.isNotEmpty) {
        await tester.pumpAndSettle();
        final boundary = boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = (await tester.runAsync(() => boundary.toImage()))!;
        final bytes = (await tester
            .runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
        Directory(screenshotDir).createSync(recursive: true);
        File('$screenshotDir/${variant.name}.png')
            .writeAsBytesSync(bytes.buffer.asUint8List());
        image.dispose();
      }
    });
  }

  testWidgets('segments expose current position and journey states',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OccasionSetupStoryShell(
          questionTitles: const ['Source', 'Name', 'Start'],
          currentIndex: 1,
          eventTitle: 'Draft',
          status: 'Saved',
          readiness: 'Required setup: 20 %',
          questionCount: 'Question 2 of 3',
          segmentStates: const ['Completed', 'Current', 'Upcoming'],
          leaveLabel: 'Leave',
          backLabel: 'Back',
          onLeave: () {},
          onBack: () {},
          child: const Text('Question content'),
        ),
      ),
    ));
    for (final pair in [
      ('Source', 'Completed'),
      ('Name', 'Current'),
      ('Start', 'Upcoming'),
    ]) {
      final segment = find.byWidgetPredicate((widget) =>
          widget is Semantics &&
          widget.properties.label == pair.$1 &&
          widget.properties.value == pair.$2);
      expect(segment, findsOneWidget);
    }
    expect(find.text('Required setup: 20 %'), findsOneWidget);
    semantics.dispose();
  });
}

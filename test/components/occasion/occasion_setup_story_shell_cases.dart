import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_story_shell.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Futura')
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'));
    await font.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
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
      await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
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
                onQuestionSelected: (_) {},
                completedKeys: const {'0', '3'},
                visitedKeys: const {'4'},
                eventTitle: 'Koncept · Podzimní slavnost',
                status: 'Uloženo',
                questionCount: 'Otázka 2 z 10',
                segmentStates: const ['Dokončeno', 'Právě teď', 'Následuje'],
                leaveLabel: 'Odejít',
                backLabel: 'Zpět',
                onLeave: () => leaves++,
                onBack: () {},
                onNext: () => advances++,
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
      await tester.tap(find.byKey(const ValueKey('story-next-arrow')));
      expect(advances, 2);
      expect(tester.getTopRight(find.byTooltip('Odejít')).dx,
          greaterThan(variant.size.width - 70));
      expect(tester.getTopLeft(find.text('Koncept · Podzimní slavnost')).dx,
          lessThan(40));
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

  testWidgets('navigation uses supplied states and supports click and keyboard',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final selected = <String>[];
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: Scaffold(
        body: OccasionSetupStoryShell(
          questionTitles: const ['Source', 'Name', 'Start'],
          questionKeys: const ['source', 'name', 'start'],
          questionLabels: const ['Source', 'Name', 'Start'],
          questionSections: const ['Basics', 'Basics', 'Finish'],
          completedKeys: const {'start'},
          visitedKeys: const {'source'},
          visitedLabel: 'In progress',
          onQuestionSelected: selected.add,
          currentIndex: 1,
          eventTitle: 'Draft',
          status: 'Saved',
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
      ('Source', 'In progress'),
      ('Name', 'Current'),
      ('Start', 'Completed'),
    ]) {
      final segment = find.byWidgetPredicate((widget) =>
          widget is Semantics &&
          widget.properties.label == pair.$1 &&
          widget.properties.value == pair.$2);
      expect(segment, findsOneWidget);
    }
    expect(find.textContaining('%'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('story-target-start')));
    expect(selected, ['start']);
    // Request the Material button's actual focus node, then activate by Space.
    final labelContext = tester.element(find
        .descendant(
            of: find.byKey(const ValueKey('story-target-source')),
            matching: find.byType(Icon))
        .first);
    Focus.of(labelContext).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(selected.last, 'source');
    expect(find.text('Otázky'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    semantics.dispose();
  });
  testWidgets('optional targets do not consume question numbers',
      (tester) async {
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
        home: Scaffold(
            body: OccasionSetupStoryShell(
      questionTitles: const [
        'Choose source',
        'Enter name',
        'Choose appearance',
        'Verify organization'
      ],
      questionKeys: const ['source', 'name', 'appearance', 'verification'],
      questionLabels: const ['Source', 'Name', 'Appearance', 'Verification'],
      questionNumbers: const [null, 1, 4, null],
      currentIndex: 1,
      eventTitle: 'Draft',
      status: 'Saved',
      questionCount: 'Question 1 of 4',
      segmentStates: const ['Completed', 'Current', 'Upcoming'],
      leaveLabel: 'Leave',
      backLabel: 'Back',
      onLeave: () {},
      onBack: () {},
      onQuestionSelected: (_) {},
      child: const Text('Question content'),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('1 Name'), findsOneWidget);
    for (final label in ['Source', '4 Appearance', 'Verification']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text('1 Source'), findsNothing);
    expect(find.text('4 Verification'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });
  for (final width in [320.0, 375.0, 812.0, 1440.0]) {
    testWidgets(
        '18 story targets fit width $width with only current label expanded',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final selected = <String>[];
      for (final active in [0, 8, 17]) {
        await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
            home: Scaffold(
                body: OccasionSetupStoryShell(
          questionTitles: List.generate(18, (i) => 'Full question $i'),
          questionLabels: List.generate(18, (i) => 'Step $i'),
          questionKeys: List.generate(18, (i) => 'key-$i'),
          currentIndex: active,
          completedKeys: const {'key-1'},
          visitedKeys: const {'key-4'},
          onQuestionSelected: selected.add,
          eventTitle: 'Draft',
          status: 'Saved',
          questionCount: 'Question ${active + 1} of 18',
          segmentStates: const ['Completed', 'Current', 'Upcoming'],
          leaveLabel: 'Leave',
          backLabel: 'Back',
          onLeave: () {},
          onBack: () {},
          child: const Text('Question content'),
        ))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final track =
            tester.getRect(find.byKey(const ValueKey('story-progress-track')));
        expect(track.left, greaterThanOrEqualTo(0));
        expect(track.right, lessThanOrEqualTo(width));
        expect(find.text('${active + 1} Step $active'), findsOneWidget);
        for (var i = 0; i < 18; i++) {
          if (i != active) expect(find.text('${i + 1} Step $i'), findsNothing);
          final marker = find.byKey(ValueKey('story-marker-key-$i'));
          if (marker.evaluate().isNotEmpty) {
            final rect = tester.getRect(marker);
            expect(rect.left, greaterThanOrEqualTo(track.left));
            expect(rect.right, lessThanOrEqualTo(track.right + .001));
          }
        }
        expect(
            find.byWidgetPredicate((w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal),
            findsNothing);
      }
      expect(find.text('Otázky'), findsNothing);
      expect(find.text('Basics'), findsNothing);
    });
  }
  testWidgets('narrow navigation exposes every question through the active pill',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = <String>[];
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
        home: Scaffold(body: OccasionSetupStoryShell(
      questionTitles: List.generate(18, (i) => 'Full question $i'),
      questionLabels: List.generate(18, (i) => i == 8 ? 'Verification' : 'Step $i'),
      questionKeys: List.generate(18, (i) => 'key-$i'),
      questionNumbers: List.generate(18, (i) => i == 8 ? null : i + 1),
      currentIndex: 0,
      onQuestionSelected: selected.add,
      eventTitle: 'Draft', status: 'Saved', questionCount: 'Question 1 of 17',
      segmentStates: const ['Completed', 'Current', 'Upcoming'],
      leaveLabel: 'Leave', backLabel: 'Back', onLeave: () {}, onBack: () {},
      child: const Text('Question content'),
    ))));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show menu'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('Show menu')).height, greaterThanOrEqualTo(48));
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Verification · Upcoming'));
    await tester.tap(find.text('Verification · Upcoming'));
    await tester.pumpAndSettle();
    expect(selected, ['key-8']);
    expect(tester.takeException(), isNull);
  });

}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/fonts/font_family_picker.dart';

void main() {
  testWidgets('font previews keep dark theme text readable in the menu',
      (tester) async {
    final theme = ThemeData.dark();
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: FontFamilyPicker(
          value: 'Inter',
          families: const ['Inter', 'Roboto'],
          selectedStyle: const TextStyle(fontFamily: 'Inter', color: Colors.black),
          onSelected: (_) async {},
        ),
      ),
    ));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    final menuText = tester.widget<RichText>(find.descendant(
      of: find.text('Roboto').last,
      matching: find.byType(RichText),
    ));
    expect(menuText.text.style!.color, theme.colorScheme.onSurface);
  });
  testWidgets(
      'popular, custom family and reset preserve previous selection on load failure',
      (tester) async {
    String? value;
    var fail = false;
    final calls = <String?>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => FontFamilyPicker(
                    value: value,
                    families: const ['Roboto', 'Russo One'],
                    onSelected: (font) async {
                      calls.add(font);
                      if (fail) throw StateError('offline');
                      setState(() => value = font);
                    })))));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roboto').last);
    await tester.pumpAndSettle();
    expect(value, 'Roboto');
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text(FormStrings.moreFonts));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Russo One');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(value, 'Russo One');
    fail = true;
    await tester.tap(find.text(FormStrings.moreFonts));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Roboto');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(value, 'Russo One');
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    fail = false;
    await tester.tap(find.byIcon(Icons.restore));
    await tester.pumpAndSettle();
    expect(value, isNull);
    expect(calls, ['Roboto', 'Russo One', 'Roboto', null]);
  });
  testWidgets('loading is visible and disposed response cannot update picker',
      (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: FontFamilyPicker(
                value: null,
                families: const ['Roboto'],
                onSelected: (_) => pending.future))));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roboto').last);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'compact picker and searchable sheet fit mobile with keyboard and large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!),
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(12),
                child: FontFamilyPicker(
                    value: 'Roboto',
                    families: const ['Roboto', 'Russo One'],
                    onSelected: (font) async => selected = font)))));
    expect(find.byType(TextField), findsNothing);
    expect(find.text(FormStrings.browseGoogleFonts), findsNothing);
    expect(tester.getSize(find.byType(FontFamilyPicker)).height, lessThan(160));
    await tester.tap(find.text(FormStrings.moreFonts));
    await tester.pumpAndSettle();
    expect(find.text(FormStrings.fontSearchHint), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'russo');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Russo One'));
    await tester.tap(find.widgetWithText(ListTile, 'Russo One'));
    await tester.pumpAndSettle();
    expect(selected, 'Russo One');
    expect(find.byType(TextField), findsNothing);
    tester.view.resetViewInsets();
  });
}

import '../../support/fixtures/localization_log_fixture.dart';
import 'package:trina_grid/trina_grid.dart';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:festapp_core/map.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';

void main() {
  testWidgets('HTML preview stays interactive until a link click completes',
      (tester) async {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
    const url = 'https://docs.google.com/spreadsheets/d/carpool/edit';
    final launched = <String>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'launch')
        launched.add(call.arguments['url'] as String);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Builder(
              builder: (context) => TrinaGrid(
                    columns: [
                      TrinaColumn(
                        title: 'Content',
                        field: 'content',
                        type: TrinaColumnType.text(),
                        width: 350,
                        renderer: (renderer) =>
                            DataGridHelper.buildHtmlEditorButton(
                          context: context,
                          field: 'content',
                          rendererContext: renderer,
                          title: 'Spolujízda',
                          loadContent: () async =>
                              '<p><a href="$url">Tabulka spolujízdy</a></p>',
                        ),
                      )
                    ],
                    rows: [
                      TrinaRow(cells: {'content': TrinaCell(value: '')})
                    ],
                  ))),
    ));
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(ElevatedButton)));
    await tester.pumpAndSettle();
    final link = find.text('Tabulka spolujízdy', findRichText: true);
    expect(link, findsOneWidget);
    await mouse.moveTo(tester.getCenter(link));
    await tester.pump(const Duration(milliseconds: 150));
    await mouse.down(tester.getCenter(link));
    await tester.pump(const Duration(milliseconds: 300));
    expect(link, findsOneWidget);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(launched, [url]);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(link, findsNothing);
  });

  testWidgets('incomplete icon records fall back without throwing',
      (tester) async {
    final cases = <(IconModel, String)>[
      (IconModel(id: 1, link: 'legacy-icon'), 'legacy-icon'),
      (
        IconModel(id: 2, data: '<svg viewBox="0 0 1 1"></svg>'),
        PlaceModel.WithoutValue,
      ),
    ];
    for (final (icon, expectedLabel) in cases) {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => DataGridHelper.iconToRow(
              context,
              icon.id,
              [icon],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(expectedLabel), findsOneWidget);
    }
  });

  testWidgets('malformed SVG records use the renderer fallback',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => DataGridHelper.iconToRow(
            context,
            3,
            [IconModel(id: 3, link: 'broken', data: '<svg><path')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.image_not_supported), findsOneWidget);
    expect(find.text('broken'), findsOneWidget);
  });
}

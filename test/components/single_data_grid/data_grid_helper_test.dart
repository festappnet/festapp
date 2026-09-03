import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';

void main() {
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

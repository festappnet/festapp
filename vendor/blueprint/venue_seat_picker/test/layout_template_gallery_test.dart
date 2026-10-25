import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_template_card.dart';

void main() {
  testWidgets(
    'public gallery supports host creation without private package imports',
    (tester) async {
      LayoutTemplate? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showVenueLayoutTemplateGallery(context);
                },
                child: const Text('Open public gallery'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open public gallery'));
      await tester.pumpAndSettle();
      final first = VenueLayoutTemplates.recommended.first;
      await tester.tap(find.byKey(ValueKey('layout-template-${first.id}')));
      await tester.pumpAndSettle();
      expect(selected?.id, first.id);
    },
  );

  testWidgets('template card stays rectangular and exposes details on focus', (
    tester,
  ) async {
    var picked = false;
    final template = LayoutTemplate(
      'test',
      'Small hall',
      'Full hall description.',
      24,
      0,
      VenueLayoutDocument.empty,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
          ),
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              height: 250,
              child: LayoutTemplateCard(
                template: template,
                preview: const ColoredBox(color: Colors.grey),
                onPressed: () => picked = true,
              ),
            ),
          ),
        ),
      ),
    );
    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    final shape = button.style!.shape!.resolve({})! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(8));
    expect(find.text('Small hall'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.byIcon(Icons.accessibility_new), findsNothing);
    expect(find.text(template.description), findsNothing);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      template.description,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.text(template.description), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(picked, isTrue);
  });

  testWidgets('template shows standing capacity only when present', (
    tester,
  ) async {
    final template = LayoutTemplate(
      'mixed',
      'Mixed hall',
      'Details',
      12,
      50,
      VenueLayoutDocument.empty,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 250,
            child: LayoutTemplateCard(
              template: template,
              preview: const SizedBox(),
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('12'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.byIcon(Icons.accessibility_new), findsOneWidget);
    expect(find.text('Details'), findsNothing);
  });
}

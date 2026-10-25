import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/canonical_appearance_panel.dart';

void main() {
  test(
    'canonical inspector and shared alignment captions have Czech translations',
    () {
      const locale = VenueLayoutLocalizations(Locale('cs'));
      for (final label in [
        'Seats',
        'Chair height',
        'Chair gap',
        'Chair spacing',
        'Edge padding',
        'Center',
        'Right',
        'Text style',
        'Advanced appearance',
        'Position and size',
        'Chair layout',
      ]) {
        expect(locale.text(label), isNot(label), reason: label);
      }
    },
  );
  testWidgets(
    'quick Czech families preserve geometry, palette and text; close button and Escape dismiss',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final d = tableLayout(
        shape: 'rect',
        count: 4,
        x: 600,
        y: 400,
        width: 300,
        height: 200,
      );
      final c = VenueLayoutController(d);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('cs'),
          supportedLocales: VenueLayoutLocalizations.supportedLocales,
          localizationsDelegates:
              VenueLayoutLocalizations.localizationsDelegates,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showCanonicalAppearanceDialog(context, c, global: true),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Stylová rodina'), findsOneWidget);
      expect(find.text('Barevná paleta'), findsOneWidget);
      expect(find.text('Směr textu'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('appearance-family-wood')));
      await tester.pumpAndSettle();
      expect(c.error, isNull);
      expect(c.document.styles['kinds']['seat']['seatStyle'], 'wood');
      expect(c.document.canvas, d.canvas);
      final card = find.byKey(const ValueKey('appearance-family-wood'));
      expect(tester.getSize(card).width, tester.getSize(card).height);
      expect(
        c.document.nodes.map((n) => n.toJson()),
        d.nodes.map((n) => n.toJson()),
      );
      expect(c.document.styles['label'], d.styles['label']);
      await tester.tap(find.byKey(const ValueKey('appearance-family-lounge')));
      await tester.pumpAndSettle();
      expect(c.document.styles['kinds']['seat']['seatStyle'], 'upholstered');
      await tester.tap(find.byTooltip('Zavřít'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('object appearance shows color swatches and Czech field labels', (
    tester,
  ) async {
    final d = tableLayout(shape: 'rect', count: 0);
    final c = VenueLayoutController(d);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('cs'),
        supportedLocales: VenueLayoutLocalizations.supportedLocales,
        localizationsDelegates: VenueLayoutLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: CanonicalAppearancePanel(
              controller: c,
              nodeId: d.nodes.first.id,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(EditorColorSwatch), findsNWidgets(2));
    expect(find.text('Barva výplně'), findsOneWidget);
    expect(find.text('Zarovnání'), findsOneWidget);
    expect(find.text('Směr textu'), findsNothing);
    final advanced = find.text('Podrobnosti vzhledu');
    await tester.ensureVisible(advanced);
    await tester.tap(advanced);
    await tester.pumpAndSettle();
    expect(find.text('Směr textu'), findsOneWidget);
    expect(find.byType(EditorColorSwatch), findsNWidgets(3));
    expect(find.textContaining('Default'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

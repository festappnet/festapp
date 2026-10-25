import 'dart:async';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/editor_ui.dart';

void main() {
  test(
    'RGB and RGBA conversion validate values without rounding stored opacity',
    () {
      final value = EditorColorValue(hex: '#ab12ef', opacity: .123456789);
      expect(value.hex, 'AB12EF');
      expect(value.opacity, .123456789);
      expect(value.rgba, '#AB12EF1F');
      expect(EditorColorValue.fromRgba('#ab12ef80').rgba, '#AB12EF80');
      expect(EditorColorValue.fromRgba('#00000000').opacity, 0);
      for (final invalid in ['12345', 'GGGGGG', '#12345678']) {
        expect(() => EditorColorValue(hex: invalid), throwsFormatException);
      }
      expect(() => EditorColorValue.fromRgba('#123456'), throwsFormatException);
      for (final invalid in [double.nan, double.infinity, -.1, 1.1]) {
        expect(
          () => EditorColorValue(hex: '123456', opacity: invalid),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'artwork palette ignores transparent pixels and preserves neutral artwork',
    () {
      final rgba = Uint8List.fromList([
        128,
        128,
        128,
        255,
        128,
        128,
        128,
        255,
        255,
        0,
        0,
        0,
      ]);
      expect(editorImagePalette(rgba), ['808080']);
      expect(editorArtworkSuggestions(rgba), ['808080']);
    },
  );

  Future<void> openColor(
    WidgetTester tester,
    EditorColorDialog dialog,
    void Function(EditorColorResult?) result,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result(
                await showDialog<EditorColorResult>(
                  context: context,
                  builder: (_) => dialog,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shared palette drafts preview, cancel does not commit, apply preserves opacity',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      EditorColorResult? result, preview;
      var returned = false;
      final dialog = EditorColorDialog(
        value: EditorColorValue(hex: '000000', opacity: .123456789),
        onPreview: (v) => preview = v,
      );
      await openColor(tester, dialog, (v) {
        result = v;
        returned = true;
      });
      await tester.tap(
        find.byKey(const ValueKey('editor-color-Basic colors-2563EB')),
      );
      await tester.pump();
      expect(preview!.primary.hex, '2563EB');
      expect(preview!.primary.opacity, .123456789);
      expect(returned, isFalse);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result, isNull);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editor-color-Basic colors-2563EB')),
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(result!.primary.hex, '2563EB');
      expect(result!.primary.opacity, .123456789);
    },
  );

  testWidgets(
    'paired colors enforce host validation and swap complete values',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      EditorColorResult? result;
      await openColor(
        tester,
        EditorColorDialog(
          value: EditorColorValue(hex: '000000', opacity: .25),
          secondaryValue: EditorColorValue(hex: '000000', opacity: .75),
          validator: (v) =>
              v.primary.hex == v.secondary!.hex ? 'Contrast too low' : null,
        ),
        (v) => result = v,
      );
      expect(find.text('Contrast too low'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Background'));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('editor-color-Basic colors-FFFFFF')),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Swap colors'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(result!.primary.hex, 'FFFFFF');
      expect(result!.primary.opacity, .75);
      expect(result!.secondary!.hex, '000000');
      expect(result!.secondary!.opacity, .25);
    },
  );

  testWidgets('font reset is unavailable when the host forbids it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorFontPicker(
            value: 'fixed',
            options: const [EditorFontOption(id: 'fixed', family: 'Roboto')],
            allowDefault: true,
            canReset: false,
            onSelected: (_) async {},
          ),
        ),
      ),
    );
    expect(find.byTooltip('Reset to default'), findsNothing);
    await tester.tap(find.text('Roboto'));
    await tester.pumpAndSettle();
    expect(find.text('Default font'), findsNothing);
    expect(find.byKey(const ValueKey('editor-font-fixed')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'font search displays families, preserves IDs and awaits failures before retry',
    (tester) async {
      final options = [
        const EditorFontOption(id: 'resource:one', family: 'Roboto'),
        const EditorFontOption(id: 'resource:two', family: 'Roboto Slab'),
      ];
      var pending = Completer<void>();
      String? requested;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorFontPicker(
              value: 'resource:one',
              options: options,
              onSelected: (id) {
                requested = id;
                return pending.future;
              },
            ),
          ),
        ),
      );
      expect(find.text('resource:one'), findsNothing);
      await tester.tap(find.text('Roboto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Slab');
      await tester.pump();
      expect(find.text('Roboto Slab'), findsOneWidget);
      await tester.tap(find.text('Roboto Slab'));
      await tester.pump();
      expect(requested, 'resource:two');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      pending.completeError(StateError('Offline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not load font'), findsOneWidget);
      expect(find.text('Roboto').first, findsOneWidget);
      pending = Completer<void>();
      await tester.tap(find.text('Roboto Slab'));
      await tester.pump();
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(requested, 'resource:two');
    },
  );
}

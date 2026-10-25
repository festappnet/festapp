import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  testWidgets(
    'archive background remains portable with transient raster resources',
    (tester) async {
      const encoded =
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC';
      final image = (await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(base64Decode(encoded));
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      }))!;
      addTearDown(image.dispose);
      final resources = (await tester.runAsync(loadLayoutFixtureResources))!;
      final document = VenueLayoutDocument(
        canvas: {
          'x': 0,
          'y': 0,
          'width': 64,
          'height': 64,
          'fill': '#ffffffff',
        },
        nodes: [
          LayoutNode(
            id: '00000000-0000-4000-8000-000000000001',
            kind: 'seat',
            x: 40,
            y: 40,
            width: 10,
            height: 10,
          ),
        ],
        background: {
          'assetRef':
              'image:7f2538a6e81af23e034f8ca2efc2cb5f1d7d709f502fa30bdccfebe774e4ecab',
          'hash':
              '7f2538a6e81af23e034f8ca2efc2cb5f1d7d709f502fa30bdccfebe774e4ecab',
          'x': 32,
          'y': 32,
          'width': 2,
          'height': 2,
          'rotation': 0,
          'scale': 32,
          'opacity': 1,
          'crop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
        },
      );
      final ref = document.background!['assetRef'] as String;
      final resolved = {
        ...resources,
        'images': {ref: image},
      };
      final reopened = VenueLayoutDocument.fromJson(document.toJson());
      final scene = compileScene(reopened, resources: resolved);
      expect(scene['issues'], isEmpty);
      expect((scene['items'] as List).first['kind'], 'image');
      final controller = VenueLayoutController(reopened, resources: resolved);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VenueLayoutEditor(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'archive public API resources and inventoried standalone galleries',
    (tester) async {
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      final resources = (await tester.runAsync(loadLayoutFixtureResources))!;
      expect(resources['protocol'], 2);
      expect(resources['fontFamilies'], isNotEmpty);
      expect(validateLayoutResources(resources), isEmpty);
      expect(VenueLayoutTemplates.all, isNotEmpty);
      expect(
        VenueLayoutTemplates.all.map((t) => t.id).toSet(),
        hasLength(VenueLayoutTemplates.all.length),
      );
      const output = String.fromEnvironment('QA_TEMPLATE_OUT');
      if (output.isNotEmpty) {
        File(output).writeAsStringSync(
          jsonEncode(
            VenueLayoutTemplates.all
                .map(
                  (t) => {
                    'id': t.id,
                    'seats': t.seatCount,
                    'document': t.create().toJson(),
                  },
                )
                .toList(),
          ),
        );
      }
      for (final template in VenueLayoutTemplates.all) {
        final document = template.create();
        expect(validateDocument(document), isEmpty, reason: template.id);
        expect(
          document.nodes.where((n) => n.kind == 'seat'),
          hasLength(template.seatCount),
        );
        expect(
          document.nodes
              .map((n) => n.id)
              .toSet()
              .intersection(template.create().nodes.map((n) => n.id).toSet()),
          isEmpty,
        );
        final roundtrip = VenueLayoutDocument.fromJson(
          jsonDecode(jsonEncode(document.toJson())),
        );
        // Serialization deliberately quantizes node transforms/dimensions to
        // 1/1024. Compare canonical persisted geometry with its second read,
        // rather than unquantized transient template coordinates.
        expect(roundtrip.toJson(), document.toJson());
        final reopened = VenueLayoutDocument.fromJson(roundtrip.toJson());
        expect(compileScene(reopened,resources:resources)['issues'],isEmpty,reason:template.id);
        expect(
          compileScene(reopened, resources: resources),
          compileScene(roundtrip, resources: resources),
        );
        if (!VenueLayoutTemplates.recommended.any((item) => item.id == template.id)) continue;
        final controller = VenueLayoutController(
          roundtrip,
          resources: resources,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: VenueLayoutEditor(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: template.id);
        // Blank documents already open the same public gallery automatically.
        if (find.byType(Dialog).evaluate().isEmpty) {
          await tester.tap(find.text('Choose template').hitTestable());
          await tester.pumpAndSettle();
        }
        final gallery = find.byType(Dialog).last;
        final grid = find.descendant(
          of: gallery,
          matching: find.byType(GridView),
        );
        final title = find.descendant(
          of: grid,
          matching: find.text(template.title),
        );
        final scrollable = find
            .descendant(of: grid, matching: find.byType(Scrollable))
            .first;
        final card = find.ancestor(
          of: title,
          matching: find.byType(OutlinedButton),
        );
        await tester.scrollUntilVisible(
          card.hitTestable(),
          200,
          scrollable: scrollable,
        );
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        expect(card.hitTestable(), findsOneWidget, reason: template.id);
        await tester.tap(card.hitTestable());
        await tester.pumpAndSettle();
        final replace = find.widgetWithText(FilledButton, 'Replace plan');
        if (replace.evaluate().isNotEmpty) {
          await tester.tap(replace);
          await tester.pumpAndSettle();
        }
        expect(find.byType(Dialog), findsNothing, reason: template.id);
        expect(
          controller.document.nodes.where((n) => n.kind == 'seat'),
          hasLength(template.seatCount),
        );
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    },
  );
  testWidgets(
    'archive host activation and presentation retain document and draft',
    (tester) async {
      final id = newLayoutId();
      final document = VenueLayoutDocument(
        nodes: [LayoutNode(id: id, kind: 'seat', x: 100, y: 100)],
      );
      final controller = VenueLayoutController(document)..select({id});
      final activations = <String>[];
      Widget editor(Map<String, dynamic> presentation) => MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(
            controller: controller,
            showGallery: false,
            interactionEnabled: false,
            seatPresentation: presentation,
            onNodeActivated: activations.add,
          ),
        ),
      );
      await tester.pumpWidget(
        editor({
          id: {'status': 'available'},
        }),
      );
      await tester.pumpAndSettle();
      final focus = tester
          .widgetList<Focus>(find.byType(Focus))
          .where((w) => w.focusNode != null && w.onKeyEvent != null)
          .last;
      focus.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(activations, [id]);
      await tester.pumpWidget(
        editor({
          id: {'status': 'occupied'},
        }),
      );
      await tester.pumpAndSettle();
      expect(identical(controller.document, document), true);
      expect(controller.dirty, false);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'archive pending picker survives presentation patch and fences replacement/dispose',
    (tester) async {
      final id = newLayoutId();
      var document = VenueLayoutDocument(
        nodes: [LayoutNode(id: id, kind: 'seat', x: 100, y: 100)],
      );
      final pending = Completer<LayoutSelectionResult>();
      late StateSetter update;
      var presentation = <String, dynamic>{};
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return Scaffold(
                body: VenueLayoutPicker(
                  document: document,
                  seatPresentation: presentation,
                  onSelectionRequested: (_, _) => pending.future,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Public accessible seat list uses the same activation as the canvas.
      await tester.tap(find.text('Accessible seat list'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('seat').last);
      await tester.pump();
      update(
        () => presentation = {
          id: {'status': 'available', 'selected': false},
        },
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      update(() => document = VenueLayoutDocument.fromJson(document.toJson()));
      await tester.pump();
      pending.complete(
        const LayoutSelectionResult(accepted: false, message: 'stale'),
      );
      await tester.pumpAndSettle();
      expect(find.text('stale'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

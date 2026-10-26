import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;
  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') {
            return clipboard == null ? null : {'text': clipboard};
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  test(
    'table clipboard regenerates the complete assembly and one undo per paste',
    () async {
      final original = tableLayout(shape: 'roundedRect', count: 6);
      final c = VenueLayoutController(original);
      addTearDown(c.dispose);
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      c.select({table.id});
      await c.copySelectionToClipboard();
      expect(c.canUndo, false);
      expect(jsonDecode(clipboard!)['format'], 'venue-layout-selection');
      await c.pasteFromClipboard();
      expect(c.error, isNull);
      expect(c.document.nodes, hasLength(14));
      final copied = c.selection.single;
      expect(copied, isNot(table.id));
      final newSeats = c.document.nodes
          .where((n) => n.parentId == copied)
          .toList();
      expect(newSeats, hasLength(6));
      expect(
        newSeats.any((n) => original.nodes.any((old) => old.id == n.id)),
        false,
      );
      expect(
        c.document.attachments.where((a) => a['targetId'] == copied),
        hasLength(6),
      );
      expect(validateDocument(c.document), isEmpty);
      await c.pasteFromClipboard();
      expect(c.document.nodes, hasLength(21));
      expect(c.selection.single, isNot(copied));
      c.undo();
      expect(c.document.nodes, hasLength(14));
      c.undo();
      expect(c.document.toJson(), original.toJson());
      c.redo();
      expect(c.document.nodes, hasLength(14));
    },
  );

  test(
    'paste is bounded and invalid/read-only clipboard cannot mutate the draft',
    () async {
      final original =
          tableLayout(shape: 'roundedRect', count: 6, x: 650, y: 450).copyWith(
            canvas: {
              'x': 0,
              'y': 0,
              'width': 850,
              'height': 600,
              'fill': '#FFFFFFFF',
            },
          );
      final c = VenueLayoutController(original);
      expect(
        c.placementIssues.where((i) => i.code == 'outside_canvas'),
        isEmpty,
      );
      addTearDown(c.dispose);
      c.select({original.nodes.firstWhere((n) => n.kind == 'table').id});
      await c.copySelectionToClipboard();
      await c.pasteFromClipboard();
      expect(c.error, isNull);
      expect(c.document.nodes, hasLength(14));
      expect(
        c.placementIssues.where((i) => i.code == 'outside_canvas'),
        isEmpty,
      );
      final pasted = jsonEncode(c.document.toJson());
      c.readOnly = true;
      await c.pasteFromClipboard();
      expect(jsonEncode(c.document.toJson()), pasted);
      c.readOnly = false;
      clipboard = 'ordinary text';
      await c.pasteFromClipboard();
      expect(c.error, contains('Clipboard'));
      expect(jsonEncode(c.document.toJson()), pasted);
    },
  );

  test(
    'individual chair drag stays attached, survives reflow and undoes atomically',
    () {
      final original = tableLayout(shape: 'roundedRect', count: 6);
      final c = VenueLayoutController(original);
      addTearDown(c.dispose);
      final chair = original.nodes.firstWhere((n) => n.kind == 'seat');
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      c.select({chair.id});
      c.beginGesture();
      c.preview(moveLayoutWithinCanvas(original, {chair.id}, dx: 22, dy: -15));
      c.commitGesture();
      var moved = c.document.nodes.firstWhere((n) => n.id == chair.id);
      expect(moved.parentId, table.id);
      expect(moved.x, closeTo(chair.x + 22, .002));
      expect(seatPlacementFree(c.document, moved), true);
      expect(
        c.document.attachments.firstWhere(
          (a) => a['seatId'] == chair.id,
        )['placement']['mode'],
        'free',
      );
      final localX = moved.x, localY = moved.y;
      c.select({table.id});
      c.moveSelection(100, 80);
      moved = c.document.nodes.firstWhere((n) => n.id == chair.id);
      expect(moved.x, localX);
      expect(moved.y, localY);
      expect(c.document.nodes, hasLength(original.nodes.length));
      c.undo();
      c.undo();
      expect(c.document.toJson(), original.toJson());
    },
  );
}

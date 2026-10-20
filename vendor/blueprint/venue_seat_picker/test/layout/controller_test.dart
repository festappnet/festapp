import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

class _Host implements LayoutHistoryParticipant {
  int value = 0;
  bool reject = false;
  @override
  Object capture() => value;
  @override
  void restore(Object? checkpoint) {
    value = checkpoint as int;
  }

  @override
  Object? prepare(
    VenueLayoutDocument before,
    VenueLayoutDocument after,
    Object? checkpoint, {
    required bool restoring,
    required LayoutEditIntent intent,
  }) {
    if (reject) throw StateError('live_guard');
    return restoring ? checkpoint : capture();
  }
}

void main() {
  test(
    'duplicating a chair outside its table retains the source child style and uses no legacy fields',
    () {
      var source = tableLayout(shape: 'roundedRect', count: 4);
      final table = source.nodes.firstWhere((node) => node.kind == 'table'),
          seat = source.nodes.firstWhere((node) => node.kind == 'seat');
      source = source.copyWith(
        nodes: [
          for (final node in source.nodes)
            node.id == table.id
                ? node.copyWith(
                    childStyles: {
                      'seat': {
                        'fill': '#123456FF',
                        'label': {'color': '#556677FF'},
                      },
                    },
                  )
                : node,
        ],
      );
      final appearance = resolveNodeAppearance(source, seat).values,
          c = VenueLayoutController(source)..select({seat.id});
      addTearDown(c.dispose);
      c.duplicateSelection();
      expect(c.error, isNull);
      expect(validateDocument(c.document), isEmpty);
      final copy = c.document.nodes.firstWhere(
        (node) => !source.nodes.any((old) => old.id == node.id),
      );
      expect(copy.kind, 'seat');
      expect(copy.parentId, isNull);
      expect(resolveNodeAppearance(c.document, copy).values, appearance);
      expect(c.document.toJson().containsKey('generators'), isFalse);
      c.undo();
      expect(c.document.toJson(), source.toJson());
      c.redo();
      expect(c.document.nodes.any((node) => node.id == copy.id), isTrue);
    },
  );

  test(
    'cross-document fragments retain resolved styles and physical assembly profiles',
    () {
      final source =
          busLayout(
            rows: 1,
            rear: 0,
            seating: const TableSeating(width: 48, height: 44),
          ).copyWith(
            styles: {
              'label': {'color': '#112233FF'},
              'kinds': {
                'seat': {'fill': '#123456FF'},
              },
            },
          );
      final originalSeat = source.nodes.firstWhere(
            (node) => node.kind == 'seat',
          ),
          appearance = resolveNodeAppearance(source, originalSeat).values;
      final c = VenueLayoutController(
        VenueLayoutDocument(
          schemaVersion: 2,
          canvas: {
            'x': 0,
            'y': 0,
            'width': 4000,
            'height': 4000,
            'fill': '#FFFFFFFF',
          },
          styles: {
            'kinds': {
              'seat': {'fill': '#FF0000FF'},
            },
          },
          seatingDefaults: {'width': 80, 'height': 80},
        ),
      );
      addTearDown(c.dispose);
      c.insert(source);
      expect(c.error, isNull);
      expect(validateDocument(c.document), isEmpty);
      final seat = c.document.nodes.firstWhere((node) => node.kind == 'seat'),
          root = c.document.nodes.firstWhere(
            (node) => node.assembly?['kind'] == 'bus',
          );
      expect(resolveNodeAppearance(c.document, seat).values, appearance);
      expect(root.seating['width'], 48);
      expect(root.seating['height'], 44);
      final changed = updateBusLayout(c.document, root.id, rows: 2);
      expect(
        changed.nodes
            .where((node) => node.kind == 'seat')
            .every((node) => node.width == 48 && node.height == 44),
        isTrue,
      );
      c.undo();
      expect(c.document.nodes, isEmpty);
      c.redo();
      expect(
        resolveNodeAppearance(
          c.document,
          c.document.nodes.firstWhere((node) => node.id == seat.id),
        ).values,
        appearance,
      );
    },
  );

  test(
    'prepared resources commit with geometry and restore with guarded history',
    () {
      final node = LayoutNode(id: newLayoutId(), kind: 'shape', x: 100, y: 100),
          c = VenueLayoutController(
            VenueLayoutDocument(schemaVersion: 2, nodes: [node]),
          ),
          host = _Host();
      addTearDown(c.dispose);
      c.addHistoryParticipant(host);
      final next = c.document.copyWith(nodes: [node.copyWith(x: 200)]),
          resources = {
            'protocol': 2,
            'fontFamilies': <String, dynamic>{},
            'textLayouts': <String, dynamic>{},
            'numberSymbols': <String, dynamic>{},
          };
      final publications = <List<Object?>>[];
      c.addListener(
        () => publications.add([
          c.document.nodes.single.x,
          c.resources['protocol'],
        ]),
      );
      host.reject = true;
      expect(c.apply(next, preparedResources: resources), isFalse);
      expect(c.document.nodes.single.x, 100);
      expect(c.resources, isEmpty);
      expect(c.canUndo, isFalse);
      host.reject = false;
      publications.clear();
      expect(c.apply(next, preparedResources: resources), isTrue);
      expect(publications, [
        [200.0, 2],
      ]);
      host.reject = true;
      c.undo();
      expect(c.document.nodes.single.x, 200);
      expect(c.resources['protocol'], 2);
      expect(c.canUndo, isTrue);
      host.reject = false;
      c.undo();
      expect(c.document.nodes.single.x, 100);
      expect(c.resources, isEmpty);
      c.redo();
      expect(c.document.nodes.single.x, 200);
      expect(c.resources['protocol'], 2);
      final accepted = c.document, currentResources = c.resources;
      expect(
        c.apply(
          accepted.copyWith(nodes: [node.copyWith(x: 300)]),
          preparedResources: {'protocol': 99},
        ),
        isFalse,
      );
      expect(identical(c.document, accepted), isTrue);
      expect(identical(c.resources, currentResources), isTrue);
    },
  );

  test(
    'inspector seat moves and rotations store independent typed placement intent',
    () {
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 500,
        y: 400,
        width: 300,
        height: 180,
        surface: {'type': 'rect'},
      );
      final c = VenueLayoutController(
        reflowTable(
          VenueLayoutDocument(schemaVersion: 2, nodes: [table]),
          table.id,
          4,
        ),
      );
      addTearDown(c.dispose);
      final seat = c.document.nodes.firstWhere((n) => n.kind == 'seat');
      c.updateNode(seat.copyWith(x: seat.x + 5));
      expect(c.error, isNull);
      expect(seatAttachment(c.document, seat.id)!['placement'], {
        'mode': 'free',
      });
      expect(seatAttachment(c.document, seat.id)!['rotationMode'], 'auto');
      final moved = c.document.nodes.firstWhere((n) => n.id == seat.id);
      c.updateNode(moved.copyWith(rotation: moved.rotation + 17));
      expect(c.error, isNull);
      expect(seatAttachment(c.document, seat.id)!['rotationMode'], 'manual');
      c.undo();
      expect(seatAttachment(c.document, seat.id)!['placement'], {
        'mode': 'free',
      });
      expect(seatAttachment(c.document, seat.id)!['rotationMode'], 'auto');
      c.undo();
      expect(seatAttachment(c.document, seat.id)!['placement'], {
        'mode': 'automatic',
      });
    },
  );

  test(
    'rejected command and history restore leave both participants and stacks unchanged',
    () {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 200,
        y: 200,
        width: 100,
        height: 100,
      );
      final c = VenueLayoutController(VenueLayoutDocument(nodes: [node]));
      final host = _Host();
      c.addHistoryParticipant(host);
      expect(
        c.apply(
          c.document.copyWith(nodes: [node.copyWith(x: 300)]),
          participantCheckpoints: [1],
        ),
        isTrue,
      );
      host.reject = true;
      final accepted = c.document;
      c.undo();
      expect(identical(c.document, accepted), isTrue);
      expect(host.value, 1);
      expect(c.canUndo, isTrue);
      expect(c.canRedo, isFalse);
      expect(
        c.apply(
          c.document.copyWith(nodes: [node.copyWith(x: 400)]),
          participantCheckpoints: [2],
        ),
        isFalse,
      );
      expect(identical(c.document, accepted), isTrue);
      expect(host.value, 1);
      host.reject = false;
      c.undo();
      expect(c.document.nodes.single.x, 200);
      expect(host.value, 0);
      expect(c.canRedo, isTrue);
      host.reject = true;
      c.redo();
      expect(c.document.nodes.single.x, 200);
      expect(host.value, 0);
      expect(c.canRedo, isTrue);
      host.reject = false;
      c.redo();
      expect(c.document.nodes.single.x, 300);
      expect(host.value, 1);
      c.dispose();
    },
  );

  test(
    'imported subunit canvas edges are valid while genuine overflow stays invalid',
    () {
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        surface: const {'type': 'rect'},
        x: 9.79,
        y: 50,
        width: 20,
        height: 20,
      );
      final outline = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 50,
        y: 50,
        width: 100.42,
        height: 100,
        properties: {'shape': 'rect'},
        style: {'fill': '#00000000'},
      );
      final doc = VenueLayoutDocument.empty().copyWith(
        canvas: {
          'x': 0,
          'y': 0,
          'width': 100,
          'height': 100,
          'fill': '#FFFFFFFF',
        },
        nodes: [outline, table],
      );
      final c = VenueLayoutController(doc);
      expect(c.placementIssues, isEmpty);
      c.updateNode(table.copyWith(x: 8));
      expect(c.error, contains('inside the canvas'));
      final outside = VenueLayoutController(
        doc.copyWith(nodes: [table.copyWith(x: 8)]),
      );
      expect(outside.placementIssues.single.code, 'outside_canvas');
      c.dispose();
      outside.dispose();
    },
  );

  test('gestures keep fixed canvas and cancel restores draft', () {
    final doc = tableLayout(shape: 'roundedRect', count: 6);
    final c = VenueLayoutController(doc);
    final root = doc.nodes.first;
    c.select({root.id});
    c.beginGesture();
    expect(
      c.preview(transformNodes(doc, {root.id}, dx: -900, dy: -700)),
      false,
    );
    expect(c.document.canvas, doc.canvas);
    expect(
      c.placementIssues.any((issue) => issue.code == 'outside_canvas'),
      false,
    );
    c.preview(doc);
    expect(c.document.canvas['x'], doc.canvas['x']);
    expect(c.preview(transformNodes(doc, {root.id}, dx: 3000)), false);
    c.cancelGesture();
    expect(c.document.toJson(), doc.toJson());
    expect(c.canUndo, false);
    c.dispose();
  });
  test('keyboard movement clamps and new oversize/outside changes reject', () {
    final seat = LayoutNode(
      id: newLayoutId(),
      kind: 'seat',
      x: 50,
      y: 50,
      width: 20,
      height: 20,
    );
    final doc = VenueLayoutDocument.empty().copyWith(
      canvas: {
        'x': 0,
        'y': 0,
        'width': 100,
        'height': 100,
        'fill': '#FFFFFFFF',
      },
      nodes: [seat],
    );
    final c = VenueLayoutController(doc)..select({seat.id});
    c.moveSelection(-1000, 1000);
    expect(c.document.nodes.single.x, closeTo(10, .02));
    expect(c.document.nodes.single.y, closeTo(90, .02));
    expect(c.placementIssues, isEmpty);
    final bounded = c.document;
    c.updateNode(c.document.nodes.single.copyWith(width: 200));
    expect(c.document.toJson(), bounded.toJson());
    expect(c.error, contains('inside the canvas'));
    c.insert(VenueLayoutDocument(nodes: [seat.copyWith(x: 500)]));
    expect(c.document.nodes, hasLength(1));
    c.undo();
    expect(c.document.toJson(), doc.toJson());
    c.dispose();
  });
  test(
    'rigid bounded movement and fixed canvas join the same undo transaction',
    () {
      final doc = tableLayout(shape: 'roundedRect', count: 6).copyWith(
        canvas: {
          'x': 0,
          'y': 0,
          'width': 800,
          'height': 600,
          'fill': '#FFFFFFFF',
        },
      );
      final table = doc.nodes.firstWhere((n) => n.kind == 'table');
      final seatIds = doc.nodes
          .where((n) => n.kind == 'seat')
          .map((n) => n.id)
          .toSet();
      final c = VenueLayoutController(doc)..select({table.id});
      c.beginGesture();
      expect(
        c.preview(moveLayoutWithinCanvas(doc, {table.id}, dx: -300)),
        true,
      );
      expect(c.document.canvas, doc.canvas);
      expect(
        c.document.nodes
            .where((n) => n.kind == 'seat')
            .map((n) => n.id)
            .toSet(),
        seatIds,
      );
      expect(
        c.placementIssues.where((issue) => issue.code == 'outside_canvas'),
        isEmpty,
      );
      c.commitGesture();
      c.undo();
      expect(c.document.toJson(), doc.toJson());
      expect(c.canUndo, false);
      c.dispose();
    },
  );
  test(
    'geometry and host draft share undo and baseline; selection is session only',
    () {
      final doc = tableLayout(shape: 'roundedRect', count: 6);
      final c = VenueLayoutController(doc), host = _Host();
      c.addHistoryParticipant(host);
      c.select({doc.nodes.first.id});
      expect(c.dirty, false);
      c.beginGesture();
      host.value = 500;
      c.moveSelection(32, 0);
      c.commitGesture();
      final moved = c.document.toJson();
      expect(c.dirty, true);
      c.undo();
      expect(host.value, 0);
      expect(c.document.toJson(), doc.toJson());
      c.redo();
      expect(host.value, 500);
      expect(c.document.toJson(), moved);
      c.markSaved();
      expect(c.dirty, false);
      expect(c.canUndo, false);
      c.beginGesture();
      host.value = 700;
      c.commitGesture();
      expect(c.dirty, true);
      c.undo();
      expect(host.value, 500);
      c.dispose();
    },
  );
  test(
    'locked descendant blocks whole table command and invalid draft stays intact',
    () {
      var doc = tableLayout(shape: 'roundedRect', count: 6);
      final seat = doc.nodes.firstWhere((n) => n.kind == 'seat');
      doc = doc.copyWith(
        nodes: doc.nodes
            .map((n) => n.id == seat.id ? n.copyWith(locked: true) : n)
            .toList(),
      );
      final c = VenueLayoutController(doc);
      c.select({doc.nodes.first.id});
      c.moveSelection(100, 0);
      expect(c.document.toJson(), doc.toJson());
      expect(c.error, isNotNull);
      expect(c.canUndo, false);
      c.dispose();
    },
  );
  test('all templates are standalone public API with fresh identities', () {
    expect(VenueLayoutTemplates.all.length, 14);
    for (final t in VenueLayoutTemplates.all) {
      final a = t.create(), b = t.create();
      expect(validateDocument(a), isEmpty, reason: t.id);
      expect(a.nodes.where((n) => n.kind == 'seat').length, t.seatCount);
      expect(
        a.nodes
            .map((n) => n.id)
            .toSet()
            .intersection(b.nodes.map((n) => n.id).toSet()),
        isEmpty,
      );
    }
  });
  test('partial deletion never dissolves an indivisible selection unit', () {
    final doc = VenueLayoutTemplates.create('lounge');
    final unit = doc.selectionUnits.first;
    final c = VenueLayoutController(doc);
    c.select({(unit['nodeIds'] as List).first as String});
    c.deleteSelection();
    expect(c.document.toJson(), doc.toJson());
    expect(c.error, contains('entire shared object'));
    c.select((unit['nodeIds'] as List).cast<String>().toSet());
    c.deleteSelection();
    expect(c.document.nodes.length, doc.nodes.length - 2);
    expect(c.document.selectionUnits.length, doc.selectionUnits.length - 1);
    c.undo();
    expect(c.document.toJson(), doc.toJson());
    c.dispose();
  });
  test('recovered autosave retains a separate confirmed baseline', () {
    final baseline = tableLayout(shape: 'roundedRect', count: 6);
    final draft = transformNodes(baseline, {baseline.nodes.first.id}, dx: 100);
    final host = _Host()..value = 500;
    final c = VenueLayoutController(draft)..addHistoryParticipant(host);
    c.setSavedBaseline(baseline, participantCheckpoints: [0]);
    expect(c.document.toJson(), draft.toJson());
    expect(c.dirty, true);
    c.markSaved();
    expect(c.dirty, false);
    c.dispose();
  });
  test(
    'layer rank normalization preserves locked content and logical order',
    () {
      final a = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        z: 0,
        x: 100,
        y: 100,
      );
      final locked = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        z: 40,
        x: 200,
        y: 100,
        locked: true,
      );
      final other = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        z: 80,
        x: 300,
        y: 100,
      );
      final doc = VenueLayoutDocument(nodes: [a, locked, other]);
      final c = VenueLayoutController(doc)..select({a.id});
      final applied = c.apply(reorderNodes(doc, {a.id}, 1));
      expect(applied, true, reason: c.error);
      expect(orderedNodes(c.document).map((n) => n.id), [
        locked.id,
        a.id,
        other.id,
      ]);
      final fixed = c.document.nodes.firstWhere((n) => n.id == locked.id);
      expect({...fixed.toJson(), 'z': 0}, {...locked.toJson(), 'z': 0});
      final before = c.document;
      c.updateNode(fixed.copyWith(z: 999));
      expect(c.document.toJson(), before.toJson());
      expect(c.error, contains('Locked object'));
      c.dispose();
    },
  );
  test(
    'overlapping drafts move continuously; invalid references still reject',
    () {
      final a = LayoutNode(id: newLayoutId(), kind: 'seat', x: 100, y: 100);
      final b = LayoutNode(id: newLayoutId(), kind: 'seat', x: 180, y: 100);
      final doc = VenueLayoutDocument(nodes: [a, b]);
      final c = VenueLayoutController(doc);
      c.select({a.id});
      c.moveSelection(60, 0);
      expect(c.document.nodes.first.x, 160);
      expect(c.error, isNull);
      expect(c.canUndo, true);
      final issues = c.showPlacementWarnings();
      expect(issues.any((issue) => issue.code == 'overlap'), true);
      expect(c.placementWarningIds, containsAll([a.id, b.id]));
      final overlapping = c.document;
      final invalid = doc.copyWith(
        nodes: [
          a.copyWith(parentId: newLayoutId()),
          b,
        ],
      );
      expect(c.apply(invalid), false);
      expect(c.document.toJson(), overlapping.toJson());
      c.undo();
      expect(c.document.toJson(), doc.toJson());
      expect(() => VenueLayoutController(invalid), throwsFormatException);
      c.dispose();
    },
  );
  test(
    'resource snapshots are immutable and failed replacement preserves valid data',
    () {
      final resource = Map<String, dynamic>.from(
        jsonDecode(
          File('assets/layout_fonts/fixtures.json').readAsStringSync(),
        ),
      );
      final id = (resource['textLayouts'] as Map).keys.first;
      final original = canonicalContractJson(resource['textLayouts'][id]);
      final c = VenueLayoutController(
        VenueLayoutDocument.empty(),
        resources: resource,
      );
      resource['textLayouts'][id]['path'].clear();
      expect(canonicalContractJson(c.resources['textLayouts'][id]), original);
      final before = c.resources;
      expect(c.setResources({'protocol': 99, 'fonts': {}}), false);
      expect(identical(c.resources, before), true);
      expect(c.error, isNotNull);
      c.dispose();
    },
  );
}

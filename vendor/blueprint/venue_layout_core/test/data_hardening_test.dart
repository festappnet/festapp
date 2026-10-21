import 'dart:convert';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

Map<String, dynamic> valid() => VenueLayoutDocument(
  nodes: [LayoutNode(id: newLayoutId(), kind: 'seat')],
).toJson();
Set<String> reasons(VenueLayoutDocument d) =>
    validateDocument(d).map((e) => e.reason).toSet();
void main() {
  test(
    'rectangular table fills every advertised slot without seat overlap',
    () {
      final initial = tableLayout(shape: 'rectangle');
      final table = initial.nodes.firstWhere((n) => n.kind == 'table');
      final originalIds = initial.nodes
          .where((n) => n.kind == 'seat')
          .map((n) => n.id)
          .toSet();
      for (var count = 0; count <= tableCapacity(table); count++) {
        final filled = reflowTable(initial, table.id, count);
        expect(validateDocument(filled), isEmpty, reason: 'count $count');
        expect(layoutCollisions(filled), isEmpty, reason: 'count $count');
        if (count >= originalIds.length) {
          expect(
            filled.nodes.map((n) => n.id).toSet().containsAll(originalIds),
            isTrue,
          );
        }
      }
    },
  );

  test(
    'decode rejects missing geometry unknown fields versions and unsafe numbers',
    () {
      final cases = <Map<String, dynamic>>[];
      var j = valid();
      (j['nodes'] as List).first.remove('transform');
      cases.add(j);
      j = valid();
      (j['nodes'] as List).first['kind'] = 'legacy-black';
      cases.add(j);
      j = valid();
      j['layoutFromHost'] = {};
      cases.add(j);
      j = valid();
      j['symbolSetVersion'] = 99;
      cases.add(j);
      j = valid();
      j['nodes'][0]['transform']['x'] = double.infinity;
      cases.add(j);
      j = valid();
      j['nodes'][0]['transform']['x'] = 1e308;
      cases.add(j);
      j = valid();
      j['nodes'][0]['transform']['x'] = 1000000001;
      cases.add(j);
      for (final bad in cases) {
        expect(
          () => VenueLayoutDocument.fromJson(bad),
          throwsA(isA<InvalidLayoutDocument>()),
        );
      }
    },
  );
  test(
    'nonfinite authoring returns issues and serialization typed failure',
    () {
      final d = VenueLayoutDocument(
        nodes: [LayoutNode(id: newLayoutId(), kind: 'seat', x: double.nan)],
      );
      expect(reasons(d), contains('invalid_geometry'));
      expect(() => d.toJson(), throwsA(isA<InvalidLayoutDocument>()));
    },
  );
  test('unknown schema original deeply immutable and unmodified', () {
    final source = <String, dynamic>{
      'schemaVersion': 90,
      'future': {
        'nested': [1, 2],
      },
    };
    try {
      VenueLayoutDocument.fromJson(source);
      fail('accepted');
    } on UnsupportedLayoutSchema catch (e) {
      expect(e.original, source);
      expect(
        () => e.original['future']['nested'].add(3),
        throwsUnsupportedError,
      );
    }
  });
  test('namespaces section IDs and titles do not alias spatial nodes', () {
    final root = LayoutNode(id: newLayoutId(), kind: 'group'),
        sectionId = newLayoutId(),
        d = VenueLayoutDocument(
          nodes: [root],
          sections: [
            {
              'id': sectionId,
              'rootId': root.id,
              'title': 'Balcony',
              'levelId': 'up',
              'outline': [
                [0, 0],
                [100, 0],
                [100, 100],
                [0, 100],
              ],
            },
          ],
        );
    expect(validateDocument(d), isEmpty);
    expect(
      VenueLayoutDocument.fromJson(d.toJson()).sections.single['title'],
      'Balcony',
    );
    expect(
      reasons(
        d.copyWith(
          sections: [
            {'id': root.id, 'rootId': root.id, 'title': 'Alias'},
          ],
        ),
      ),
      contains('duplicate_identity'),
    );
    expect(
      reasons(
        d.copyWith(
          sections: [
            {
              'id': sectionId,
              'rootId': root.id,
              'title': '',
              'outline': [
                [0, 0],
                [100, 100],
                [0, 100],
                [100, 0],
              ],
            },
          ],
        ),
      ),
      containsAll(['invalid_section_title', 'self_intersection']),
    );
  });
  test(
    'attachments generators and units reject duplicate orphan and illegal types',
    () {
      final d = tableLayout(shape: 'ellipse', count: 4),
          seat = d.nodes.firstWhere((n) => n.kind == 'seat'),
          a = d.attachments.first;
      expect(
        reasons(d.copyWith(attachments: [a, a])),
        contains('invalid_attachment'),
      );
      expect(
        reasons(
          d.copyWith(
            attachments: [
              {...a, 'targetId': seat.id, 'kind': 'magic', 't': double.nan},
            ],
          ),
        ),
        contains('invalid_attachment'),
      );

      expect(
        reasons(
          d.copyWith(
            selectionUnits: [
              {
                'id': newLayoutId(),
                'nodeIds': [seat.id, seat.id],
                'kind': 'partial',
              },
            ],
          ),
        ),
        containsAll(['duplicate_membership', 'invalid_selection_unit_kind']),
      );
    },
  );
  test(
    'background requires real reference hash and finite explicit similarity transform',
    () {
      final b = <String, dynamic>{
        'assetRef': 'image:${'a' * 64}',
        'width': 100,
        'height': 80,
        'x': 100,
        'y': 100,
        'rotation': 0,
        'scale': 1,
        'opacity': 1,
        'crop': {'x': .1, 'y': .2, 'width': .6, 'height': .4},
      };
      expect(validateDocument(VenueLayoutDocument(background: b)), isEmpty);
      for (final patch in [
        {'scale': 0},
        {'x': double.infinity},
        {'assetRef': '../private'},
        {'assetRef': 'opaque', 'hash': 'wrong'},
        {
          'crop': {'x': 0, 'y': 0},
        },
        {
          'crop': {'x': .7, 'y': 0, 'width': .6, 'height': 1},
        },
      ]) {
        expect(
          validateDocument(VenueLayoutDocument(background: {...b, ...patch})),
          isNotEmpty,
        );
      }
    },
  );
  test(
    'host and unknown geometry data rejected recursively including preset fragments',
    () {
      for (final key in [
        'price',
        'productId',
        'order_id',
        'secret',
        'status',
        'pending',
        'unknownFutureShape',
      ]) {
        final d = VenueLayoutDocument(
          nodes: [
            LayoutNode(
              id: newLayoutId(),
              kind: 'seat',
              properties: {key: 'sensitive'},
            ),
          ],
        );
        expect(validateDocument(d), isNotEmpty);
        expect(() => d.toJson(), throwsA(isA<InvalidLayoutDocument>()));
      }
      final base = VenueLayoutDocument.empty(), fragment = valid();
      fragment['nodes'][0]['secret'] = 'hidden';
      expect(
        reasons(
          base.copyWith(
            presets: [
              {'id': newLayoutId(), 'title': 'Unsafe', 'document': fragment},
            ],
          ),
        ),
        contains('host_data_forbidden'),
      );
    },
  );
  test(
    'JSON cycle non-JSON key and nesting rejected before immutable copy',
    () {
      final cycle = <String, dynamic>{};
      cycle['self'] = cycle;
      expect(
        () => LayoutNode(id: newLayoutId(), kind: 'seat', properties: cycle),
        throwsFormatException,
      );
      expect(
        () => LayoutNode(
          id: newLayoutId(),
          kind: 'seat',
          properties: {'bad': Object()},
        ),
        throwsFormatException,
      );
      dynamic deep = 0;
      for (var i = 0; i < 66; i++) {
        deep = [deep];
      }
      expect(
        () => LayoutNode(
          id: newLayoutId(),
          kind: 'seat',
          properties: {'deep': deep},
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'clone rewrites only relation identities and preserves UUID-looking text',
    () {
      final group = LayoutNode(id: newLayoutId(), kind: 'group'),
          seat = LayoutNode(
            id: newLayoutId(),
            kind: 'seat',
            parentId: group.id,
            label: group.id,
          ),
          text = LayoutNode(
            id: newLayoutId(),
            kind: 'text',
            properties: {'text': group.id},
          ),
          d = VenueLayoutDocument(
            nodes: [group, seat, text],
            selectionUnits: [
              {
                'id': newLayoutId(),
                'kind': 'atomic',
                'nodeIds': [seat.id],
              },
            ],
          );
      final cloned = cloneLayout(d);
      expect(validateDocument(cloned), isEmpty);
      expect(
        cloned.nodes.firstWhere((n) => n.kind == 'text').properties['text'],
        group.id,
      );
      expect(cloned.nodes.firstWhere((n) => n.kind == 'seat').label, group.id);
      expect(
        cloned.nodes.firstWhere((n) => n.kind == 'seat').parentId,
        isNot(group.id),
      );
    },
  );
  test(
    'preset refuses half atomic unit and complete snapshots clone independently',
    () {
      final d = tableLayout(shape: 'ellipse', count: 4),
          seats = d.nodes.where((n) => n.kind == 'seat').toList(),
          unit = d.copyWith(
            selectionUnits: [
              {
                'id': newLayoutId(),
                'kind': 'atomic',
                'nodeIds': [seats[0].id, seats[1].id],
              },
            ],
          );
      expect(() => savePreset(unit, {seats[0].id}, 'Half'), throwsStateError);
      final saved = savePreset(unit, {d.nodes.first.id}, 'Whole'),
          twice = instantiatePreset(
            instantiatePreset(saved, saved.presets.first['id']),
            saved.presets.first['id'],
          );
      expect(validateDocument(twice), isEmpty);
      expect(twice.selectionUnits.length, 3);
    },
  );
  test('canonical bytes independent record array and object map order', () {
    final a = LayoutNode(id: newLayoutId(), kind: 'group'),
        b = LayoutNode(id: newLayoutId(), kind: 'group'),
        u1 = {'id': newLayoutId(), 'rootId': a.id, 'title': 'A'},
        u2 = {'title': 'B', 'rootId': b.id, 'id': newLayoutId()},
        d = VenueLayoutDocument(nodes: [a, b], sections: [u1, u2]);
    expect(
      jsonEncode(d.toJson()),
      jsonEncode(d.copyWith(nodes: [b, a], sections: [u2, u1]).toJson()),
    );
  });
  test('payload bytes remain exact across Unicode, node reuse and edits', () {
    final text = LayoutNode(
      id: newLayoutId(),
      kind: 'text',
      properties: {'text': 'ž🙂\n"\\'},
    );
    final seat = LayoutNode(id: newLayoutId(), kind: 'seat');
    final base = VenueLayoutDocument(nodes: [text, seat]);
    final bytes = utf8.encode(jsonEncode(base.toJson())).length;
    final padding = 'x' * (layoutMaxBytes - bytes);
    final boundary = text.copyWith(
      properties: {'text': '${text.properties['text']}$padding'},
    );
    final exact = base.copyWith(nodes: [boundary, seat]);
    expect(reasons(exact), isNot(contains('payload_limit')));
    expect(
      reasons(exact.copyWith(nodes: [seat, boundary])),
      isNot(contains('payload_limit')),
    );
    expect(
      reasons(exact.copyWith(canvas: {...exact.canvas, 'width': 10000})),
      contains('payload_limit'),
    );
    final larger = boundary.copyWith(
      properties: {'text': '${boundary.properties['text']}x'},
    );
    expect(
      reasons(exact.copyWith(nodes: [larger, seat])),
      contains('payload_limit'),
    );
    expect(
      reasons(exact.copyWith(nodes: [text, seat])),
      isNot(contains('payload_limit')),
    );
  });
  test('node seat depth and byte budgets are enforced without truncation', () {
    final tooMany = VenueLayoutDocument(
      nodes: List.generate(
        20001,
        (_) => LayoutNode(id: newLayoutId(), kind: 'seat'),
      ),
    );
    expect(reasons(tooMany), contains('seat_limit'));
    final nodes = <LayoutNode>[];
    String? parent;
    for (var i = 0; i < 17; i++) {
      final n = LayoutNode(id: newLayoutId(), kind: 'group', parentId: parent);
      nodes.add(n);
      parent = n.id;
    }
    expect(reasons(VenueLayoutDocument(nodes: nodes)), contains('depth_limit'));
    final tooLarge = VenueLayoutDocument(
      nodes: [
        LayoutNode(
          id: newLayoutId(),
          kind: 'text',
          properties: {'text': 'x' * (8 * 1024 * 1024)},
        ),
      ],
    );
    expect(reasons(tooLarge), containsAll(['payload_limit', 'text_limit']));
  });
}

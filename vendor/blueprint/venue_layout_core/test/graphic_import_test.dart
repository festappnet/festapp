import 'package:test/test.dart';
import 'package:venue_layout_core/src/model.dart';
import 'package:venue_layout_core/src/scene.dart';
import 'package:venue_layout_core/src/graphic_import.dart';
import 'package:venue_layout_core/src/canonical_contract.dart';

void main() {
  test(
    'unsupported paint effects reject before whole-text preparation instead of disappearing',
    () async {
      for (final attributes in [
        'filter="blur(2px)"',
        'style="filter:blur(2px)"',
        'style="vector-effect:non-scaling-stroke"',
        'style="fill:var(--paint)"',
      ]) {
        var calls = 0;
        final source =
            '<svg width="100" height="50"><g $attributes><text y="20">Whole paragraph</text></g></svg>';
        await expectLater(
          importSvgGraphicWithText(
            source,
            prepareText: (_) async {
              calls++;
              throw StateError('must not prepare rejected input');
            },
          ),
          throwsA(
            isA<GraphicImportFailure>().having(
              (error) => error.reason,
              'reason',
              'svg_paint_attribute_unsupported',
            ),
          ),
        );
        expect(calls, 0);
      }
    },
  );

  test(
    'original SVG survives private document roundtrips and never enters the scene',
    () {
      const source =
          '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="60"><!-- original authoring comment --><path d="M0 0Q50 60 100 0Z" fill="red"/></svg>';
      final imported = importSvgGraphic(source);
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'vector',
        x: 400,
        y: 300,
        width: 200,
        height: 120,
        graphic: {'type': 'vector', ...imported.graphic.toJson()},
        originalSource: imported.originalSource,
      );
      final document = VenueLayoutDocument(schemaVersion: 2, nodes: [node]);
      expect(validateDocument(document), isEmpty);
      final reopened = VenueLayoutDocument.fromJson(document.toJson());
      expect(reopened.nodes.single.originalSource!['text'], source);
      expect(
        reopened.nodes.single.copyWith(rotation: 37).originalSource,
        imported.originalSource,
      );
      final scene = compileScene(reopened);
      expect(scene['issues'], isEmpty);
      expect(scene.toString().contains('originalSource'), isFalse);
      expect(scene.toString().contains(source), isFalse);
      expect(
        validateDocument(
          document.copyWith(
            nodes: [
              node.copyWith(
                originalSource: {...imported.originalSource, 'text': 'changed'},
              ),
            ],
          ),
        ),
        isNotEmpty,
      );
      expect(
        validateDocument(
          document.copyWith(
            nodes: [
              LayoutNode(
                id: node.id,
                kind: 'seat',
                originalSource: imported.originalSource,
              ),
            ],
          ),
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'SVG whole text preparation retains paint, baseline, anchor and original receipt',
    () async {
      var calls = 0;
      const source =
          '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100"><g fill="#ff0000"><text x="100" y="50" font-family="Roboto" font-size="20" text-anchor="middle">AV fi<tspan> Židle</tspan></text></g></svg>';
      final result = await importSvgGraphicWithText(
        source,
        prepareText: (request) async {
          calls++;
          expect(request.text, 'AV fi Židle');
          expect(request.family, 'Roboto');
          expect(request.size, 20);
          return SvgTextOutline(
            path: [
              ['M', 0, -10],
              ['L', 40, 0],
            ],
            advance: 40,
            dependency: {'fontFaceId': 'actual-face'},
          );
        },
      );
      expect(calls, 1);
      final command = result.graphic.commands.singleWhere(
        (c) => c['op'] == 'path',
      );
      expect(command['path'], [
        ['M', 80.0, 40.0],
        ['L', 120.0, 50.0],
      ]);
      expect(command['fill'], '#ff0000ff');
      expect(result.receipt['fontDependencies'], [
        {'fontFaceId': 'actual-face'},
      ]);
    },
  );

  test(
    'SVG whitespace normalization preserves authored Unicode spaces and rejects unparsed font shorthand',
    () async {
      const source =
          '<svg width="200" height="50"><text y="20"> \n\t&#160;A&#160; \n</text></svg>';
      final result = await importSvgGraphicWithText(
        source,
        prepareText: (request) async {
          expect(request.text, '\u00a0A\u00a0');
          return SvgTextOutline(
            path: [
              ['M', 0, 0],
              ['L', 10, 10],
            ],
            advance: 10,
            dependency: {},
          );
        },
      );
      expect(result.originalSource['text'], source);
      var calls = 0;
      await expectLater(
        importSvgGraphicWithText(
          '<svg width="100" height="50"><text y="20" style="font:italic 20px serif">A</text></svg>',
          prepareText: (_) async {
            calls++;
            throw StateError('must reject before preparing');
          },
        ),
        throwsA(
          isA<GraphicImportFailure>().having(
            (e) => e.reason,
            'reason',
            'svg_text_attribute_unsupported',
          ),
        ),
      );
      expect(calls, 0);
    },
  );

  test(
    'SVG curves, viewBox, group transforms and independent colors become canonical paths',
    () {
      const source =
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50"><g transform="translate(10 5)"><path fill="#f00" d="M0 0 C10 20 20 20 30 0 Q35 10 40 0 Z"/><rect x="40" y="5" width="20" height="10" fill="#00f"/></g></svg>';
      final imported = importSvgGraphic(source),
          paths = imported.graphic.commands
              .where((c) => c['op'] == 'path')
              .toList();
      expect(imported.graphic.width, 100);
      expect(imported.graphic.height, 50);
      expect(paths, hasLength(2));
      expect(paths.first['fill'], '#ff0000ff');
      expect(paths.last['fill'], '#0000ffff');
      expect((paths.first['path'] as List).first, ['M', 10.0, 5.0]);
      expect((paths.first['path'] as List).where((c) => c[0] == 'C').length, 2);
      expect(importSvgGraphic(source).receipt, imported.receipt);
      expect(
        LayoutVectorGraphic.fromJson(imported.graphic.toJson()).toJson(),
        imported.graphic.toJson(),
      );
    },
  );
  test('SVG opacity layers and clipping remain structural operations', () {
    final imported = importSvgGraphic(
      '<svg viewBox="0 0 100 100"><defs><clipPath id="c"><circle cx="40" cy="40" r="30"/></clipPath></defs><g opacity="0.5" clip-path="url(#c)"><rect width="60" height="60" fill="red"/><rect x="20" y="20" width="60" height="60" fill="blue"/></g></svg>',
    );
    final ops = imported.graphic.commands.map((c) => c['op']).toList();
    expect(ops, contains('clip'));
    expect(ops, contains('layer'));
    expect(
      ops.where((op) => op == 'restore').length,
      ops.where((op) => op == 'clip' || op == 'layer').length,
    );
  });
  test('SVG linear and radial gradient paints survive conversion', () {
    final imported = importSvgGraphic(
      '<svg viewBox="0 0 100 50"><defs><linearGradient id="g"><stop stop-color="red"/><stop offset="1" stop-color="blue"/></linearGradient><radialGradient id="r"><stop stop-color="white"/><stop offset="1" stop-color="black"/></radialGradient></defs><rect width="40" height="40" fill="url(#g)"/><circle cx="70" cy="20" r="15" fill="url(#r)"/></svg>',
    );
    final paths = imported.graphic.commands
        .where((c) => c['op'] == 'path')
        .toList();
    expect((paths.first['fillGradient'] as Map)['type'], 'linear');
    expect((paths.last['fillGradient'] as Map)['type'], 'radial');
  });
  test(
    'malformed, executable, external and unsupported SVG never returns a partial object',
    () {
      for (final source in [
        '<svg>',
        '<html/>',
        '<!DOCTYPE svg><svg/>',
        '<svg><script>alert(1)</script></svg>',
        '<svg onload="x"/>',
        '<svg><image href="https://example.test/image.png"/></svg>',
        '<svg><rect fill="url(https://example.test/g)"/></svg>',
      ]) {
        expect(
          () => importSvgGraphic(source),
          throwsA(isA<GraphicImportFailure>()),
          reason: source,
        );
      }
      expect(
        () => importSvgGraphic(
          '<svg width="100" height="50"><text x="0" y="20">Text</text></svg>',
        ),
        throwsA(
          isA<GraphicImportFailure>().having(
            (e) => e.reason,
            'reason',
            'svg_text_preparation_required',
          ),
        ),
      );
    },
  );
  test(
    'unbalanced vector stacks, malformed paths and unknown paint fields are rejected',
    () {
      for (final commands in [
        [
          {'op': 'restore'},
        ],
        [
          {'op': 'layer', 'opacity': .5},
        ],
        [
          {
            'op': 'path',
            'path': [
              ['C', 1, 2],
            ],
            'fillRule': 'nonzero',
          },
        ],
        [
          {'op': 'layer', 'opacity': .5, 'external': 'https://example.test'},
        ],
      ])
        expect(
          () => LayoutVectorGraphic.fromJson({
            'version': 1,
            'width': 100,
            'height': 100,
            'commands': commands,
          }),
          throwsA(isA<GraphicImportFailure>()),
        );
    },
  );
  test(
    'sparse style leaves preserve explicit false and reject null, unknown keys and invalid unions',
    () {
      expect(
        validateCanonicalStyle(
          {
            'label': {'weight': 700, 'italic': false},
            'opacity': 0,
          },
          'style',
          kind: 'table',
        ),
        isEmpty,
      );
      for (final style in [
        {'label': null},
        {
          'label': {'fontId': 'old'},
        },
        {
          'label': {'weight': 500},
        },
        {
          'strokePattern': {'type': 'solid', 'lengths': []},
        },
      ])
        expect(
          validateCanonicalStyle(style, 'style', kind: 'table'),
          isNotEmpty,
        );
      expect(
        validateCanonicalStyle({'fill': '#ff0000ff'}, 'style', kind: 'image'),
        isNotEmpty,
      );
    },
  );
}

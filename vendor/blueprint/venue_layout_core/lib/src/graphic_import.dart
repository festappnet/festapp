import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart' as svg;
import 'package:xml/xml.dart';
import 'canonical_contract.dart';
import 'model.dart' show frozenMap;

class GraphicImportFailure implements Exception {
  final String reason;
  final String? detail;
  const GraphicImportFailure(this.reason, [this.detail]);
  @override
  String toString() => detail == null ? reason : '$reason: $detail';
}

/// Portable vector display list. The input SVG never reaches a runtime DOM or
/// a separate SVG painter; all consumers receive these same curves and paints.
class LayoutVectorGraphic {
  LayoutVectorGraphic._(this.width, this.height, this.commands);
  final double width, height;
  final List<Map<String, dynamic>> commands;
  factory LayoutVectorGraphic.fromJson(Map<String, dynamic> value) {
    void fail() => throw const GraphicImportFailure('invalid_vector_graphic');
    if (value.keys.any(
          (k) => !const {'version', 'width', 'height', 'commands'}.contains(k),
        ) ||
        value['version'] != 1) {
      fail();
    }
    final width = value['width'],
        height = value['height'],
        commands = value['commands'];
    if (width is! num ||
        height is! num ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        width > 1000000 ||
        height > 1000000 ||
        commands is! List ||
        commands.length > 10000) {
      fail();
    }
    var depth = 0, segments = 0;
    for (final raw in commands as List) {
      if (raw is! Map) fail();
      final op = raw['op'];
      final allowed = switch (op) {
        'path' => const {
          'op',
          'path',
          'fillRule',
          'fill',
          'stroke',
          'strokeWidth',
          'strokeCap',
          'strokeJoin',
          'miterLimit',
          'fillGradient',
          'strokeGradient',
        },
        'clip' => const {'op', 'path', 'fillRule'},
        'layer' => const {'op', 'opacity'},
        'restore' => const {'op'},
        _ => <String>{},
      };
      if (allowed.isEmpty || raw.keys.any((k) => !allowed.contains(k))) fail();
      if (op == 'layer') {
        final alpha = raw['opacity'];
        if (alpha is! num || !alpha.isFinite || alpha < 0 || alpha > 1) fail();
        depth++;
      } else if (op == 'restore') {
        if (--depth < 0) fail();
      } else {
        if (op == 'clip') depth++;
        final path = raw['path'];
        if (path is! List || !['nonzero', 'evenodd'].contains(raw['fillRule'])) {
          fail();
        }
        for (final command in path as List) {
          if (command is! List || command.isEmpty) fail();
          final arity = canonicalPathArities[(command as List).first];
          if (arity == null ||
              command.length != arity + 1 ||
              command
                  .skip(1)
                  .any((v) => v is! num || !v.isFinite || v.abs() > 1000000000)) {
            fail();
          }
        }
        segments += path.length;
        if (segments > 200000) fail();
        if (op == 'path') {
          for (final key in ['fill', 'stroke']) {
            if (raw[key] != null &&
                (raw[key] is! String ||
                    !RegExp(r'^#[0-9a-fA-F]{8}$').hasMatch(raw[key] as String))) {
              fail();
          }
            }
          final stroke = raw['strokeWidth'];
          if (stroke is! num ||
              !stroke.isFinite ||
              stroke < 0 ||
              stroke > 1000000000) {
            fail();
          }
          if (!['butt', 'round', 'square'].contains(raw['strokeCap']) ||
              !['miter', 'round', 'bevel'].contains(raw['strokeJoin'])) {
            fail();
          }
          final miter = raw['miterLimit'];
          if (miter is! num || !miter.isFinite || miter < 1 || miter > 1000000) {
            fail();
          }
          for (final key in ['fillGradient', 'strokeGradient']) {
            if (raw[key] != null && !_validGradient(raw[key])) fail();
          }
        }
      }
      if (depth > 32) fail();
    }
    if (depth != 0 || utf8.encode(jsonEncode(value)).length > 8 * 1024 * 1024) {
      fail();
    }
    return LayoutVectorGraphic._(
      (width as num).toDouble(),
      (height as num).toDouble(),
      List.unmodifiable(
        commands.map(
          (c) => frozenMap(Map<String, dynamic>.from(c as Map)),
        ),
      ),
    );
  }
  Map<String, dynamic> toJson() => {
    'version': 1,
    'width': width,
    'height': height,
    'commands': commands,
  };
}

bool _validGradient(Object? raw) {
  if (raw is! Map || !['linear', 'radial'].contains(raw['type'])) return false;
  final radial = raw['type'] == 'radial';
  final keys = {
    'type',
    'colors',
    'stops',
    'spread',
    if (radial) ...[
      'center',
      'radius',
      'focal',
      'matrix',
    ] else ...[
      'from',
      'to',
    ],
  };
  if (raw.keys.any((k) => !keys.contains(k)) ||
      !['pad', 'reflect', 'repeat'].contains(raw['spread'])) {
    return false;
  }
  bool pair(Object? v) =>
      v is List &&
      v.length == 2 &&
      v.every((n) => n is num && n.isFinite && n.abs() <= 1000000000);
  final colors = raw['colors'], stops = raw['stops'];
  if (colors is! List ||
      stops is! List ||
      colors.length < 2 ||
      colors.length > 1024 ||
      colors.length != stops.length ||
      colors.any(
        (c) => c is! String || !RegExp(r'^#[0-9a-fA-F]{8}$').hasMatch(c),
      ) ||
      stops.any((v) => v is! num || !v.isFinite || v < 0 || v > 1)) {
    return false;
  }
  for (var i = 1; i < stops.length; i++) {
    if ((stops[i] as num) < (stops[i - 1] as num)) return false;
  }
  if (!radial) return pair(raw['from']) && pair(raw['to']);
  final radius = raw['radius'], matrix = raw['matrix'];
  return pair(raw['center']) &&
      (raw['focal'] == null || pair(raw['focal'])) &&
      radius is num &&
      radius.isFinite &&
      radius > 0 &&
      radius <= 1000000000 &&
      matrix is List &&
      matrix.length == 6 &&
      matrix.every((v) => v is num && v.isFinite && v.abs() <= 1000000000);
}

/// Original imported source is private authoring provenance, never a render input.
bool validOriginalSvgSource(Map<String, dynamic> value) =>
    value.length == 3 &&
    canonicalOriginalSourceFields.keys.every(value.containsKey) &&
    validateCanonicalLeaves(
      value,
      canonicalOriginalSourceFields,
      'originalSource',
    ).isEmpty &&
    utf8.encode(value['text'] as String).length <= 2097152 &&
    value['sha256'] ==
        sha256.convert(utf8.encode(value['text'] as String)).toString();

class SvgGraphicImport {
  SvgGraphicImport(this.graphic, this.receipt, {required String source})
    : originalSource = frozenMap({
        'format': 'svg',
        'text': source,
        'sha256': sha256.convert(utf8.encode(source)).toString(),
      });
  final Map<String, dynamic> originalSource;
  final LayoutVectorGraphic graphic;
  final Map<String, dynamic> receipt;
}

/// The Flutter-maintained parser resolves SVG geometry, styles, transforms,
/// gradients and clipping. Optional FFI optimizers are disabled: curves stay
/// curves and the identical pure Dart import runs on desktop and in the JS core.
SvgGraphicImport importSvgGraphic(String source) {
  if (utf8.encode(source).length > 2 * 1024 * 1024 ||
      RegExp('<').allMatches(source).length > 20000) {
    throw const GraphicImportFailure('svg_input_limit');
  }
  if (RegExp(r'<!\s*(DOCTYPE|ENTITY)', caseSensitive: false).hasMatch(source)) {
    throw const GraphicImportFailure('svg_document_type_unsupported');
  }
  XmlDocument xml;
  try {
    xml = XmlDocument.parse(source);
  } catch (_) {
    throw const GraphicImportFailure('svg_invalid_xml');
  }
  if (xml.rootElement.name.local != 'svg' ||
      (xml.rootElement.namespaceUri != null &&
          xml.rootElement.namespaceUri != 'http://www.w3.org/2000/svg')) {
    throw const GraphicImportFailure('svg_root_required');
  }
  void paintDeclaration(String name, String value) {
    final defaults = {
      'filter': 'none',
      'backdrop-filter': 'none',
      'mix-blend-mode': 'normal',
      'paint-order': 'normal',
      'vector-effect': 'none',
      'stroke-alignment': 'center',
      'color-interpolation': 'sRGB',
    };
    final normal = defaults[name.toLowerCase()];
    if (normal != null && value.trim().toLowerCase() != normal.toLowerCase()) {
      throw GraphicImportFailure('svg_paint_attribute_unsupported', name);
    }
    if (RegExp(r'\bvar\s*\(', caseSensitive: false).hasMatch(value)) {
      throw const GraphicImportFailure(
        'svg_paint_attribute_unsupported',
        'CSS variables',
      );
    }
  }

  void paintDeclarations(String css) {
    final plain = css.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    for (final declaration in RegExp(
      r'(?:^|[;{}])\s*([A-Za-z-]+)\s*:\s*([^;{}]+)',
    ).allMatches(plain)) {
      paintDeclaration(declaration[1]!, declaration[2]!);
    }
  }

  var elements = 0;
  for (final element in xml.descendants.whereType<XmlElement>()) {
    if (++elements > 10000) {
      throw const GraphicImportFailure('svg_element_limit');
    }
    if (element.ancestors.whereType<XmlElement>().length > 32) {
      throw const GraphicImportFailure('svg_depth_limit');
    }
    if (element.name.local == 'style') {
      paintDeclarations(element.innerText);
      if (RegExp(r'@import', caseSensitive: false).hasMatch(element.innerText)) {
        throw const GraphicImportFailure('svg_external_resource');
      }
      for (final match in RegExp(
        r'url\s*\(([^)]+)\)',
        caseSensitive: false,
      ).allMatches(element.innerText)) {
        final target = match[1]!.trim().replaceAll('"', '').replaceAll("'", '');
        if (!target.startsWith('#')) {
          throw const GraphicImportFailure('svg_external_resource');
        }
      }
    }
    if (const {
      'script',
      'foreignObject',
      'iframe',
      'audio',
      'video',
      'animate',
      'animateMotion',
      'animateTransform',
      'set',
    }.contains(element.name.local)) {
      throw GraphicImportFailure('svg_element_unsupported', element.name.local);
    }
    for (final attribute in element.attributes) {
      final name = attribute.name.local.toLowerCase(),
          value = attribute.value.trim();
      if (name == 'style') {
        paintDeclarations(value);
      } else {
        paintDeclaration(name, value);
      }
      if (name.startsWith('on')) {
        throw const GraphicImportFailure('svg_executable_content');
      }
      if ((name == 'href' || name == 'src') && !value.startsWith('#')) {
        throw const GraphicImportFailure('svg_external_resource');
      }
      for (final match in RegExp(
        r'url\s*\(([^)]+)\)',
        caseSensitive: false,
      ).allMatches(value)) {
        final target = match[1]!.trim().replaceAll(RegExp('[\'\"]'), '');
        if (!target.startsWith('#')) {
          throw const GraphicImportFailure('svg_external_resource');
        }
      }
    }
  }
  svg.VectorInstructions parsed;
  try {
    parsed = svg.parseWithoutOptimizers(source, warningsAsErrors: true);
  } catch (error) {
    throw GraphicImportFailure('svg_conversion_failed', error.toString());
  }
  if (parsed.text.isNotEmpty) {
    throw const GraphicImportFailure('svg_text_preparation_required');
  }
  if (parsed.images.isNotEmpty || parsed.drawImages.isNotEmpty) {
    throw const GraphicImportFailure('svg_embedded_image_unsupported');
  }
  String color(svg.Color c) =>
      '#${c.r.toRadixString(16).padLeft(2, '0')}${c.g.toRadixString(16).padLeft(2, '0')}${c.b.toRadixString(16).padLeft(2, '0')}${c.a.toRadixString(16).padLeft(2, '0')}';
  Map<String, dynamic>? gradient(svg.Gradient? g) {
    if (g == null) return null;
    final colors = g.colors, stops = g.offsets;
    if (colors == null || stops == null) {
      throw const GraphicImportFailure('svg_gradient_invalid');
    }
    final spread = switch (g.tileMode?.name) {
      'clamp' || null => 'pad',
      'mirror' => 'reflect',
      'repeated' => 'repeat',
      _ => throw const GraphicImportFailure('svg_gradient_unsupported'),
    };
    if (g is svg.LinearGradient) {
      return {
        'type': 'linear',
        'from': [g.from.x, g.from.y],
        'to': [g.to.x, g.to.y],
        'colors': colors.map(color).toList(),
        'stops': stops,
        'spread': spread,
      };
    }
    if (g is svg.RadialGradient) {
      final m = g.transform ?? svg.AffineMatrix.identity;
      return {
        'type': 'radial',
        'center': [g.center.x, g.center.y],
        'radius': g.radius,
        if (g.focalPoint != null) 'focal': [g.focalPoint!.x, g.focalPoint!.y],
        'matrix': [m.a, m.b, m.c, m.d, m.e, m.f],
        'colors': colors.map(color).toList(),
        'stops': stops,
        'spread': spread,
      };
    }
    throw const GraphicImportFailure('svg_gradient_unsupported');
  }

  List<List<Object>> path(svg.Path p) => [
    for (final c in p.commands)
      switch (c) {
        svg.MoveToCommand() => ['M', c.x, c.y],
        svg.LineToCommand() => ['L', c.x, c.y],
        svg.CubicToCommand() => ['C', c.x1, c.y1, c.x2, c.y2, c.x3, c.y3],
        svg.CloseCommand() => ['Z'],
        _ => throw const GraphicImportFailure('svg_path_unsupported'),
      },
  ];
  final commands = <Map<String, dynamic>>[];
  for (final command in parsed.commands) {
    switch (command.type) {
      case svg.DrawCommandType.path:
        final p = parsed.paths[command.objectId!],
            paint = parsed.paints[command.paintId!],
            stroke = paint.stroke,
            fill = paint.fill;
        if (paint.blendMode != svg.BlendMode.srcOver) {
          throw const GraphicImportFailure('svg_blend_unsupported');
        }
        commands.add({
          'op': 'path',
          'path': path(p),
          'fillRule': p.fillType == svg.PathFillType.nonZero
              ? 'nonzero'
              : 'evenodd',
          if (fill != null) 'fill': color(fill.color),
          if (stroke != null) 'stroke': color(stroke.color),
          'strokeWidth': stroke?.width ?? 0,
          'strokeCap': stroke?.cap?.name ?? 'butt',
          'strokeJoin': stroke?.join?.name ?? 'miter',
          'miterLimit': stroke?.miterLimit ?? 4,
          if (fill?.shader != null) 'fillGradient': gradient(fill!.shader),
          if (stroke?.shader != null)
            'strokeGradient': gradient(stroke!.shader),
        });
      case svg.DrawCommandType.clip:
        final p = parsed.paths[command.objectId!];
        commands.add({
          'op': 'clip',
          'path': path(p),
          'fillRule': p.fillType == svg.PathFillType.nonZero
              ? 'nonzero'
              : 'evenodd',
        });
      case svg.DrawCommandType.saveLayer:
        final paint = parsed.paints[command.paintId!];
        if (paint.blendMode != svg.BlendMode.srcOver ||
            paint.fill == null ||
            paint.fill!.shader != null) {
          throw const GraphicImportFailure('svg_layer_unsupported');
        }
        commands.add({'op': 'layer', 'opacity': paint.fill!.color.a / 255});
      case svg.DrawCommandType.restore:
        commands.add({'op': 'restore'});
      default:
        throw GraphicImportFailure(
          'svg_operation_unsupported',
          command.type.name,
        );
    }
  }
  final graphic = LayoutVectorGraphic.fromJson({
    'version': 1,
    'width': parsed.width,
    'height': parsed.height,
    'commands': commands,
  });
  return SvgGraphicImport(
    graphic,
    Map.unmodifiable({
      'sourceHash': sha256.convert(utf8.encode(source)).toString(),
      'targetHash': sha256
          .convert(utf8.encode(canonicalContractJson(graphic.toJson())))
          .toString(),
      'converter': 'vector_graphics_compiler@1.3.0',
      'optimizers': false,
    }),
    source: source,
  );
}

class SvgTextRequest {
  const SvgTextRequest({
    required this.text,
    required this.family,
    required this.size,
    required this.weight,
    required this.italic,
    required this.language,
    required this.direction,
  });
  final String text, family, language, direction;
  final double size;
  final int weight;
  final bool italic;
}

class SvgTextOutline {
  SvgTextOutline({
    required List<List<dynamic>> path,
    required this.advance,
    required Map<String, dynamic> dependency,
  }) : path = List.unmodifiable(path.map((c) => List<dynamic>.unmodifiable(c))),
       dependency = frozenMap(dependency);
  final List<List<dynamic>> path;
  final double advance;
  final Map<String, dynamic> dependency;
}

/// SVG text crosses the same authorized whole-text preparation boundary as an
/// ordinary text field. Curves then join the one canonical vector display list.
/// Unsupported per-character positioning and mixed typography fail explicitly.
Future<SvgGraphicImport> importSvgGraphicWithText(
  String source, {
  required Future<SvgTextOutline> Function(SvgTextRequest) prepareText,
}) async {
  try {
    return importSvgGraphic(source);
  } on GraphicImportFailure catch (error) {
    if (error.reason != 'svg_text_preparation_required') rethrow;
  }
  final document = XmlDocument.parse(source),
      dependencies = <Map<String, dynamic>>[];
  Map<String, String> declarations(XmlElement e) {
    final values = {for (final a in e.attributes) a.name.local: a.value};
    for (final rule in (e.getAttribute('style') ?? '').split(';')) {
      final at = rule.indexOf(':');
      if (at > 0) {
        values[rule.substring(0, at).trim()] = rule.substring(at + 1).trim();
      }
    }
    return values;
  }

  double number(String? value, {double fallback = 0}) {
    if (value == null) return fallback;
    final match = RegExp(
      r'^\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*(px|pt|pc|in|cm|mm)?\s*$',
    ).firstMatch(value);
    if (match == null) {
      throw const GraphicImportFailure('svg_text_position_unsupported');
    }
    final scale = switch (match[2]) {
      'pt' => 96 / 72,
      'pc' => 16.0,
      'in' => 96.0,
      'cm' => 96 / 2.54,
      'mm' => 96 / 25.4,
      _ => 1.0,
    };
    final v = double.parse(match[1]!) * scale;
    if (!v.isFinite || v.abs() > 1e9) {
      throw const GraphicImportFailure('svg_text_position_unsupported');
    }
    return v;
  }

  final texts = document.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'text')
      .toList();
  if (texts.length > 100) throw const GraphicImportFailure('svg_text_limit');
  for (final element in texts) {
    if (element.descendants.whereType<XmlElement>().any(
      (e) => e.name.local != 'tspan' || e.attributes.isNotEmpty,
    )) {
      throw const GraphicImportFailure('svg_mixed_text_unsupported');
    }
    final inherited = <String, String>{};
    for (final parent
        in element.ancestors.whereType<XmlElement>().toList().reversed) {
      inherited.addAll(declarations(parent));
    }
    inherited.addAll(declarations(element));
    if (inherited.containsKey('font')) {
      throw const GraphicImportFailure(
        'svg_text_attribute_unsupported',
        'font',
      );
    }
    if (inherited.containsKey('textLength') ||
        inherited.containsKey('lengthAdjust')) {
      throw const GraphicImportFailure('svg_text_length_unsupported');
    }
    for (final key in [
      'textLength',
      'lengthAdjust',
      'rotate',
      'writing-mode',
      'dominant-baseline',
      'alignment-baseline',
      'baseline-shift',
    ]) {
      if (inherited.containsKey(key) &&
          !{'baseline', 'auto', '0', 'horizontal-tb'}.contains(inherited[key])) {
        throw GraphicImportFailure('svg_text_attribute_unsupported', key);
    }
      }
    for (final key in ['letter-spacing', 'word-spacing']) {
      if (inherited.containsKey(key) &&
          !{'normal', '0', '0px'}.contains(inherited[key])) {
        throw const GraphicImportFailure('svg_text_spacing_unsupported');
    }
      }
    if (element.getAttribute('class') != null ||
        document.descendants.whereType<XmlElement>().any(
          (e) => e.name.local == 'style',
        )) {
      throw const GraphicImportFailure('svg_text_stylesheet_unsupported');
    }
    final preserve =
        inherited['space'] == 'preserve' || inherited['white-space'] == 'pre';
    final text = preserve
        ? element.innerText
        : element.innerText
              .replaceAll(RegExp(r'[\t\r\n ]+'), ' ')
              .replaceAll(RegExp(r'^ | $'), '');
    final weight = inherited['font-weight'],
        direction = inherited['direction'] ?? 'ltr',
        anchor = inherited['text-anchor'] ?? 'start';
    if (!{'ltr', 'rtl'}.contains(direction) ||
        !{'start', 'middle', 'end'}.contains(anchor)) {
      throw const GraphicImportFailure('svg_text_direction_unsupported');
    }
    final request = SvgTextRequest(
      text: text,
      family: inherited['font-family'] ?? 'sans-serif',
      size: number(inherited['font-size'], fallback: 16),
      weight:
          weight == 'bold' ||
              weight == 'bolder' ||
              (int.tryParse(weight ?? '') ?? 400) >= 600
          ? 700
          : 400,
      italic:
          inherited['font-style'] == 'italic' ||
          inherited['font-style'] == 'oblique',
      language: inherited['lang'] ?? 'und',
      direction: direction,
    );
    final outline = await prepareText(request);
    if (!outline.advance.isFinite || outline.advance < 0) {
      throw const GraphicImportFailure('svg_text_outline_invalid');
    }
    final offset = anchor == 'middle'
        ? -outline.advance / 2
        : (anchor == 'end') != (direction == 'rtl')
        ? -outline.advance
        : 0.0;
    final x =
            number(element.getAttribute('x')) +
            number(element.getAttribute('dx')) +
            offset,
        y =
            number(element.getAttribute('y')) +
            number(element.getAttribute('dy'));
    final path = <List<dynamic>>[];
    for (final command in outline.path) {
      final arity = command.isEmpty
          ? null
          : canonicalPathArities[command.first];
      if (arity == null ||
          command.length != arity + 1 ||
          command.skip(1).any((v) => v is! num || !v.isFinite || v.abs() > 1e9)) {
        throw const GraphicImportFailure('svg_text_outline_invalid');
      }
      path.add([
        command.first,
        for (var i = 1; i < command.length; i += 2) ...[
          (command[i] as num) + x,
          (command[i + 1] as num) + y,
        ],
      ]);
    }
    final attributes = [
      for (final a in element.attributes)
        if (!{
          'x',
          'y',
          'dx',
          'dy',
          'text-anchor',
          'font-family',
          'font-size',
          'font-weight',
          'font-style',
          'direction',
          'lang',
          'space',
        }.contains(a.name.local))
          a.copy(),
    ];
    final group = XmlElement(XmlName('g'), attributes, [
      XmlElement(XmlName('path'), [
        XmlAttribute(
          XmlName('d'),
          path.map((c) => '${c.first}${c.skip(1).join(' ')}').join(' '),
        ),
      ]),
    ]);
    final parent = element.parent!;
    parent.children[parent.children.indexOf(element)] = group;
    dependencies.add(outline.dependency);
  }
  final converted = importSvgGraphic(document.toXmlString());
  return SvgGraphicImport(
    converted.graphic,
    frozenMap({
      ...converted.receipt,
      'sourceHash': sha256.convert(utf8.encode(source)).toString(),
      'textPreparation': 'whole-paragraph-v1',
      'fontDependencies': dependencies,
    }),
    source: source,
  );
}

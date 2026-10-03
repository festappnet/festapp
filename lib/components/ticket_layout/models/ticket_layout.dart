import '../../fonts/ticket_font_ids.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

const ticketQrColors = [
  '000000',
  '2A2A2A',
  '17365D',
  '123B20',
  '401529',
  'FFFFFF'
];
bool ticketQrColorReadable(String color, [String background = 'FFFFFF']) {
  if (!RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(color)) return false;
  final channels = [0, 2, 4].map((i) {
    final c = int.parse(color.substring(i, i + 2), radix: 16) / 255;
    return c <= .04045
        ? c / 12.92
        : math.pow((c + .055) / 1.055, 2.4).toDouble();
  }).toList();
  final luminance =
      channels[0] * .2126 + channels[1] * .7152 + channels[2] * .0722;
  final bg = [0, 2, 4].map((i) {
    final c = int.parse(background.substring(i, i + 2), radix: 16) / 255;
    return c <= .04045
        ? c / 12.92
        : math.pow((c + .055) / 1.055, 2.4).toDouble();
  }).toList();
  final back = bg[0] * .2126 + bg[1] * .7152 + bg[2] * .0722;
  return (math.max(luminance, back) + .05) /
          (math.min(luminance, back) + .05) >=
      4.5;
}

const ticketBindings = [
  'qr',
  'ticketSymbol',
  'spotGroup',
  'food',
  'note',
  'price',
  'occasionTitle',
  'occasionDatePlace',
  'orderName',
  'logo',
  'footer'
];
Map<String, dynamic> copyTicketJson(Map value) =>
    (jsonDecode(jsonEncode(value)) as Map).cast<String, dynamic>();

class TicketElement {
  final String id, binding, color, align;
  final String? fontId;
  final Rect box;
  final bool visible, locked, bold, italic, underline;
  final double fontSize, minFontSize;
  final int maxLines;
  const TicketElement(
      {this.fontId,
      required this.id,
      required this.binding,
      required this.box,
      this.visible = true,
      this.locked = false,
      this.fontSize = 12,
      this.minFontSize = 6,
      this.maxLines = 3,
      this.color = '2A2A2A',
      this.align = 'left',
      this.bold = false,
      this.italic = false,
      this.underline = false});
  factory TicketElement.fromJson(Map j) {
    final b = j['box'] as Map, s = j['style'] as Map;
    return TicketElement(
        fontId: s['fontId'],
        id: j['id'],
        binding: j['binding'],
        box: Rect.fromLTWH(
            (b['x'] as num).toDouble(),
            (b['y'] as num).toDouble(),
            (b['width'] as num).toDouble(),
            (b['height'] as num).toDouble()),
        visible: j['visible'],
        locked: j['locked'],
        fontSize: (s['fontSize'] as num).toDouble(),
        minFontSize: (s['minFontSize'] as num).toDouble(),
        maxLines: s['maxLines'],
        color: s['color'],
        align: s['align'],
        bold: s['bold'] as bool? ?? false,
        italic: s['italic'] as bool? ?? false,
        underline: s['underline'] as bool? ?? false);
  }
  Map<String, dynamic> toJson() => {
        'id': id,
        'binding': binding,
        'box': boxJson(box),
        'visible': visible,
        'locked': locked,
        'style': {
          if (fontId != null) 'fontId': fontId,
          'fontSize': fontSize,
          'minFontSize': minFontSize,
          'maxLines': maxLines,
          'color': color,
          'align': align,
          if (bold) 'bold': true,
          if (italic) 'italic': true,
          if (underline) 'underline': true
        }
      };
  TicketElement copyWith(
          {String? fontId,
          bool resetFont = false,
          Rect? box,
          bool? visible,
          bool? locked,
          bool? bold,
          bool? italic,
          bool? underline,
          double? fontSize,
          String? color,
          String? align,
          int? maxLines}) =>
      TicketElement(
          fontId: resetFont ? null : fontId ?? this.fontId,
          id: id,
          binding: binding,
          box: box ?? this.box,
          visible: visible ?? this.visible,
          locked: locked ?? this.locked,
          fontSize: fontSize ?? this.fontSize,
          minFontSize: minFontSize,
          maxLines: maxLines ?? this.maxLines,
          color: color ?? this.color,
          align: align ?? this.align,
          bold: bold ?? this.bold,
          italic: italic ?? this.italic,
          underline: underline ?? this.underline);
}

Map<String, dynamic> boxJson(Rect b) =>
    {'x': b.left, 'y': b.top, 'width': b.width, 'height': b.height};

class TicketTemplate {
  final Map<String, dynamic> appearance;
  String? get fontId => appearance['fontId'] as String?;
  String get font => appearance['font'] as String? ?? 'futura';
  String get canvasColor => appearance['canvasColor'] as String? ?? 'E6E6E6';
  double get canvasOpacity => canvasColor == 'transparent'
      ? 0
      : (appearance['canvasOpacity'] as num?)?.toDouble() ?? 1;
  TicketTemplate withCanvasColor(String color, {double? opacity}) =>
      TicketTemplate(
          fitPageToTicket: fitPageToTicket,
          page: page,
          area: area,
          elements: elements,
          appearance: {
            ...appearance,
            'canvasColor': color,
            if (opacity != null) 'canvasOpacity': opacity
          });
  Map get qrAppearance => appearance['qrAppearance'] as Map? ?? const {};
  List<TicketElement> positionedElements(Map<String, String?> data) {
    final flow = (appearance['flow'] as List? ?? const [])
        .map((b) => elements.where((e) => e.binding == b).firstOrNull)
        .whereType<TicketElement>()
        .toList();
    final positions = <String, TicketElement>{};
    double shift = 0;
    for (var i = 0; i < flow.length; i++) {
      final e = flow[i];
      positions[e.id] = e.copyWith(box: e.box.shift(Offset(0, -shift)));
      if (!e.visible || (data[e.binding]?.isEmpty ?? true)) {
        shift += (appearance['flowStep'] as num?)?.toDouble() ?? e.box.height;
      }
    }
    return elements.map((e) => positions[e.id] ?? e).toList();
  }

  /// Explicit geometry edits take ownership of the currently displayed positions.
  TicketTemplate fixedPositions(Map<String, String?> data) {
    if (!(appearance['flow'] is List) || (appearance['flow'] as List).isEmpty)
      return this;
    return TicketTemplate(
        fitPageToTicket: fitPageToTicket,
        page: page,
        area: area,
        appearance: {
          for (final entry in appearance.entries)
            if (!['flow', 'flowStep'].contains(entry.key))
              entry.key: entry.value
        },
        elements: positionedElements(data));
  }

  final bool fitPageToTicket;
  final Size page;
  final Rect area;
  final List<TicketElement> elements;
  TicketTemplate(
      {this.fitPageToTicket = false,
      this.appearance = const {},
      required this.page,
      required this.area,
      required List<TicketElement> elements})
      : elements = List.unmodifiable(elements);
  factory TicketTemplate.fromJson(Map j) {
    if (j.containsKey('pageFit') && j['pageFit'] != 'ticket') {
      throw const FormatException('Invalid page fit');
    }
    final p = j['page'], a = j['ticketArea'];
    return TicketTemplate(
        fitPageToTicket: j['pageFit'] == 'ticket',
        appearance: {
          for (final key in [
            'fontId',
            'font',
            'flow',
            'flowStep',
            'qrAppearance',
            'backgroundTransform',
            'backgroundCrop',
            'canvasColor',
            'canvasOpacity',
            'pageMargin',
            'border'
          ])
            if (j.containsKey(key)) key: j[key]
        },
        page: Size(
            (p['width'] as num).toDouble(), (p['height'] as num).toDouble()),
        area: Rect.fromLTWH(
            (a['x'] as num).toDouble(),
            (a['y'] as num).toDouble(),
            (a['width'] as num).toDouble(),
            (a['height'] as num).toDouble()),
        elements: (j['elements'] as List)
            .map((e) => TicketElement.fromJson(e))
            .toList());
  }
  Map get backgroundTransform =>
      appearance['backgroundTransform'] as Map? ?? const {};
  double get backgroundScale =>
      (backgroundTransform['scale'] as num?)?.toDouble() ?? 1;
  Offset get backgroundOffset => Offset(
      (backgroundTransform['x'] as num?)?.toDouble() ?? 0,
      (backgroundTransform['y'] as num?)?.toDouble() ?? 0);
  Rect backgroundRect(Size image) {
    final scale =
        math.min(area.width / image.width, area.height / image.height) *
            backgroundScale;
    return Rect.fromCenter(
        center: Offset(area.width / 2 + backgroundOffset.dx * area.width,
            area.height / 2 + backgroundOffset.dy * area.height),
        width: image.width * scale,
        height: image.height * scale);
  }

  Rect get backgroundCrop {
    final crop = appearance['backgroundCrop'];
    if (crop is! Map) return const Rect.fromLTWH(0, 0, 1, 1);
    return Rect.fromLTWH(
        (crop['x'] as num).toDouble(),
        (crop['y'] as num).toDouble(),
        (crop['width'] as num).toDouble(),
        (crop['height'] as num).toDouble());
  }

  Rect croppedBackgroundRect(Size image) {
    final full = backgroundRect(image), crop = backgroundCrop;
    return Rect.fromLTWH(
        full.left + crop.left * full.width,
        full.top + crop.top * full.height,
        crop.width * full.width,
        crop.height * full.height);
  }

  TicketTemplate withBackgroundCrop(Rect crop) => TicketTemplate(
      fitPageToTicket: fitPageToTicket,
      page: page,
      area: area,
      elements: elements,
      appearance: {...appearance, 'backgroundCrop': boxJson(crop)});

  TicketTemplate withBackground(double scale, Offset offset) => TicketTemplate(
          fitPageToTicket: fitPageToTicket,
          page: page,
          area: area,
          elements: elements,
          appearance: {
            ...appearance,
            'backgroundTransform': {
              'scale': scale,
              'x': offset.dx,
              'y': offset.dy
            }
          });
  static const defaultPageMargin = 3 * 72 / 25.4;
  double get pageMargin => appearance['pageMargin'] is num
      ? (appearance['pageMargin'] as num).toDouble()
      : 0;
  TicketTemplate withPaper(bool ticket, {double margin = 0}) => TicketTemplate(
      fitPageToTicket: ticket,
      page: ticket
          ? Size(area.width + 2 * margin, area.height + 2 * margin)
          : const Size(595.28, 841.89),
      area: ticket
          ? Rect.fromLTWH(margin, margin, area.width, area.height)
          : Rect.fromLTWH(
              math.max(0, (595.28 - area.width) / 2),
              math.min(29.764, math.max(0, 841.89 - area.height)),
              area.width,
              area.height),
      appearance: {
        for (final entry in appearance.entries)
          if (entry.key != 'pageMargin') entry.key: entry.value,
        if (ticket) 'pageMargin': margin
      },
      elements: elements);
  TicketTemplate withQrColors(String foreground, String background) =>
      TicketTemplate(
          fitPageToTicket: fitPageToTicket,
          page: page,
          area: area,
          appearance: {
            ...appearance,
            'qrAppearance': {
              'margin': 4,
              'opacity': 1,
              ...qrAppearance,
              'background': background,
              if (background != (qrAppearance['background'] ?? 'FFFFFF'))
                'opacity': 1,
            }
          },
          elements: elements
              .map((e) => e.binding == 'qr' ? e.copyWith(color: foreground) : e)
              .toList());
  TicketTemplate withFont(String? value) => TicketTemplate(
      fitPageToTicket: fitPageToTicket,
      page: page,
      area: area,
      appearance: {
        for (final entry in appearance.entries)
          if (!['font', 'fontId'].contains(entry.key)) entry.key: entry.value,
        'fontId':
            legacyTicketFontIds[value] ?? value ?? legacyTicketFontIds['futura']
      },
      elements: elements);
  TicketTemplate replace(TicketElement e) => TicketTemplate(
      fitPageToTicket: fitPageToTicket,
      appearance: appearance,
      page: page,
      area: area,
      elements: elements.map((old) => old.id == e.id ? e : old).toList());

  /// Resize the surface, not its content. Hidden boxes stay contract-valid.
  TicketTemplate resizeCanvasArea(Size size,
      {Size? backgroundImage, Offset origin = Offset.zero}) {
    final bounds = origin & size;
    if (size == area.size && origin == Offset.zero &&
        elements.every((e) => e.box.left >= 0 && e.box.top >= 0 &&
            e.box.right <= size.width && e.box.bottom <= size.height)) return this;
    final required =
        elements.where((e) => ['qr', 'ticketSymbol'].contains(e.binding));
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width < 60 ||
        size.height < 60 ||
        required.any((e) =>
            e.box.left < bounds.left - .001 ||
            e.box.top < bounds.top - .001 ||
            e.box.right > bounds.right + .001 ||
            e.box.bottom > bounds.bottom + .001)) {
      throw const FormatException('Required ticket elements outside canvas');
    }
    var next = TicketTemplate(
        fitPageToTicket: fitPageToTicket,
        appearance: appearance,
        page: fitPageToTicket
            ? Size(size.width + 2 * pageMargin, size.height + 2 * pageMargin)
            : page,
        area: Rect.fromLTWH(area.left, area.top, size.width, size.height),
        elements: elements.map((original) {
          final e = original.copyWith(box: original.box.shift(-origin));
          if (e.box.left >= -.001 &&
              e.box.top >= -.001 &&
              e.box.right <= size.width + .001 &&
              e.box.bottom <= size.height + .001) return e;
          final w = math.min(e.box.width, size.width),
              h = math.min(e.box.height, size.height);
          return e.copyWith(
              visible: false,
              box: Rect.fromLTWH(e.box.left.clamp(0, size.width - w),
                  e.box.top.clamp(0, size.height - h), w, h));
        }).toList());
    if (backgroundImage != null) {
      final original = backgroundRect(backgroundImage).shift(-origin);
      final contain = math.min(size.width / backgroundImage.width,
          size.height / backgroundImage.height);
      next = next.withBackground(
          original.width / backgroundImage.width / contain,
          Offset((original.center.dx - size.width / 2) / size.width,
              (original.center.dy - size.height / 2) / size.height));
    }
    return next;
  }

  TicketTemplate resizeArea(Size size) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      throw const FormatException('Invalid ticket dimensions');
    }
    if (size == area.size) return this;
    final sx = size.width / area.width, sy = size.height / area.height;
    final qr = elements.where((e) => e.binding == 'qr').firstOrNull;
    final scale =
        math.max(math.min(sx, sy), qr == null ? 0.0 : 60 / qr.box.width);
    // Transform the design as one group: no new overlaps when aspect changes.
    // Keep QR printable, consuming surrounding whitespace before rejecting size.
    final bounds =
        elements.map((e) => e.box).reduce((a, b) => a.expandToInclude(b));
    double shift(double target, double original, double start, double end) {
      final preferred = (target - original * scale) / 2;
      final low = -start * scale, high = target - end * scale;
      return low <= high ? preferred.clamp(low, high) : low;
    }

    final dx = shift(size.width, area.width, bounds.left, bounds.right);
    final dy = shift(size.height, area.height, bounds.top, bounds.bottom);
    // Binary-exact coordinates keep Rect.width/height identical for square QR
    // after right-left subtraction and JSON serialization at arbitrary mm sizes.
    double coordinate(double value) => (value * 1024).round() / 1024;
    return TicketTemplate(
        fitPageToTicket: fitPageToTicket,
        appearance: {
          ...appearance,
          if (appearance['flowStep'] != null)
            'flowStep': (appearance['flowStep'] as num) * scale
        },
        page: fitPageToTicket
            ? Size(size.width + 2 * pageMargin, size.height + 2 * pageMargin)
            : page,
        area: Rect.fromLTWH(fitPageToTicket ? pageMargin : area.left,
            fitPageToTicket ? pageMargin : area.top, size.width, size.height),
        elements: elements
            .map((e) => e.copyWith(
                box: Rect.fromLTWH(
                    coordinate(e.box.left * scale + dx),
                    coordinate(e.box.top * scale + dy),
                    coordinate(e.box.width * scale),
                    coordinate(e.box.height * scale)),
                fontSize: (e.fontSize * scale).clamp(e.minFontSize, 72)))
            .toList());
  }

  Map<String, dynamic> toJson() => {
        ...appearance,
        if (fitPageToTicket) 'pageFit': 'ticket',
        'page': {'width': page.width, 'height': page.height},
        'ticketArea': boxJson(area),
        'elements': elements.map((e) => e.toJson()).toList()
      };
  List<String> validate(String type) {
    final errors = <String>[];
    if (appearance.containsKey('canvasOpacity') &&
        (appearance['canvasOpacity'] is! num ||
            !(appearance['canvasOpacity'] as num).isFinite ||
            (appearance['canvasOpacity'] as num) < 0 ||
            (appearance['canvasOpacity'] as num) > 1))
      errors.add('canvasOpacity');
    if (appearance.containsKey('canvasColor') &&
        (appearance['canvasColor'] is! String ||
            (canvasColor != 'transparent' &&
                !RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(canvasColor))))
      errors.add('canvasColor');
    bool validFont(String? id) =>
        id == null ||
        RegExp(r'^(gf:|builtin:[a-z0-9-]+:)[a-f0-9]{64}$').hasMatch(id);
    final transform = appearance['backgroundTransform'];
    if (appearance.containsKey('backgroundTransform') &&
        (transform is! Map ||
            !['scale', 'x', 'y'].every(
                (k) => transform[k] is num && (transform[k] as num).isFinite) ||
            (transform['scale'] as num) < .1 ||
            (transform['scale'] as num) > 10 ||
            (transform['x'] as num).abs() > 10 ||
            (transform['y'] as num).abs() > 10)) {
      errors.add('background');
    }
    final crop = appearance['backgroundCrop'];
    if (appearance.containsKey('backgroundCrop') &&
        (crop is! Map ||
            !['x', 'y', 'width', 'height']
                .every((k) => crop[k] is num && (crop[k] as num).isFinite) ||
            (crop['x'] as num) < 0 ||
            (crop['y'] as num) < 0 ||
            (crop['width'] as num) < .001 ||
            (crop['height'] as num) < .001 ||
            (crop['x'] as num) + (crop['width'] as num) > 1.000001 ||
            (crop['y'] as num) + (crop['height'] as num) > 1.000001)) {
      errors.add('background');
    }
    if (appearance.containsKey('pageMargin') &&
        (!fitPageToTicket ||
            appearance['pageMargin'] is! num ||
            !pageMargin.isFinite ||
            pageMargin < 0 ||
            pageMargin > 72)) errors.add('geometry');
    if (!validFont(fontId)) errors.add('font');
    bool inside(Rect b, Size size) =>
        [b.left, b.top, b.width, b.height].every((v) => v.isFinite) &&
        b.left >= 0 &&
        b.top >= 0 &&
        b.width >= 1 &&
        b.height >= 1 &&
        b.right <= size.width + .001 &&
        b.bottom <= size.height + .001;
    final pageValid = fitPageToTicket
        ? [page.width, page.height]
                .every((v) => v.isFinite && v >= 60 && v <= 842) &&
            area.topLeft == Offset(pageMargin, pageMargin) &&
            (area.width + 2 * pageMargin - page.width).abs() < .001 &&
            (area.height + 2 * pageMargin - page.height).abs() < .001
        : page == const Size(595.28, 841.89) ||
            page == const Size(212.5, 387.5);
    if (!pageValid ||
        !inside(area, page) ||
        elements.length < 2 ||
        elements.length > 11) {
      errors.add('geometry');
    }
    if (!['futura', 'robotoSlab', 'roboto', 'russoOne'].contains(font))
      errors.add('font');
    final ids = <String>{}, bindings = <String>{};
    TicketElement? qr;
    for (final e in elements) {
      if (!validFont(e.fontId) ||
          (e.fontId != null && ['qr', 'logo'].contains(e.binding)) ||
          !ids.add(e.id) ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,40}$').hasMatch(e.id) ||
          !bindings.add(e.binding) ||
          !ticketBindings.contains(e.binding) ||
          !inside(e.box, area.size) ||
          !e.fontSize.isFinite ||
          e.fontSize < 6 ||
          e.fontSize > 72 ||
          !e.minFontSize.isFinite ||
          e.minFontSize < 6 ||
          e.minFontSize > e.fontSize ||
          e.maxLines < 1 ||
          e.maxLines > 12 ||
          !RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(e.color) ||
          !['left', 'center', 'right'].contains(e.align)) {
        errors.add(e.id);
      }
      if (['qr', 'ticketSymbol'].contains(e.binding) && !e.visible) {
        errors.add(e.id);
      }
      if (e.binding == 'qr') {
        qr = e;
        if (e.box.width != e.box.height ||
            e.box.width < 60 ||
            !ticketQrColorReadable(
                e.color, qrAppearance['background'] as String? ?? 'FFFFFF')) {
          errors.add(e.id);
        }
      }
    }
    if (!bindings.containsAll(['qr', 'ticketSymbol'])) errors.add('required');
    if (qr != null) {
      for (final e in elements) {
        if (e.visible &&
            !['qr', 'logo'].contains(e.binding) &&
            e.box.overlaps(qr.box)) {
          errors.add(e.id);
        }
      }
    }
    return errors;
  }
}

void validateTicketLayout(Map<String, dynamic> layout,
    {Set<String>? allowedFontIds}) {
  if (utf8.encode(jsonEncode(layout)).length > 32768) {
    throw const FormatException('Layout too large');
  }
  final version = layout['schemaVersion'];
  if (version != 1 && version != 2) {
    throw const FormatException('Unsupported ticket layout');
  }
  final templates = layout['templates'] as Map;
  if (templates.isEmpty ||
      templates.keys.any((k) => !['wide', 'named'].contains(k))) {
    throw const FormatException('Invalid templates');
  }
  final ids = <String>{};
  for (final entry in templates.entries) {
    final raw = entry.value as Map;
    if (version == 2 && raw.containsKey('font')) {
      throw const FormatException('Legacy font field in schema 2');
    }
    final styles =
        (raw['elements'] as List).map((e) => (e as Map)['style'] as Map);
    if (version == 1 &&
        (raw.containsKey('fontId') ||
            styles.any((s) => s.containsKey('fontId')))) {
      throw const FormatException('Font fields require schema 2');
    }
    if ((raw.containsKey('fontId') && raw['fontId'] is! String) ||
        styles.any((s) => s.containsKey('fontId') && s['fontId'] is! String)) {
      throw const FormatException('Invalid font');
    }
    final t = TicketTemplate.fromJson(raw);
    if (t.validate(entry.key).isNotEmpty) {
      throw const FormatException('Invalid ticket template');
    }
    final fonts =
        [t.fontId, ...t.elements.map((e) => e.fontId)].whereType<String>();
    if (version == 1 && fonts.isNotEmpty) {
      throw const FormatException('Font fields require schema 2');
    }
    if (allowedFontIds != null &&
        fonts.any((id) => !allowedFontIds.contains(id))) {
      throw const FormatException('Unknown font');
    }
    ids.addAll(fonts);
  }
  if (ids.length > 12) throw const FormatException('Too many fonts');
}

Map<String, dynamic> upgradeTicketLayout(Map<String, dynamic> layout) {
  final result = copyTicketJson(layout);
  result['schemaVersion'] = 2;
  for (final value in (result['templates'] as Map).values) {
    final t = value as Map;
    t['fontId'] ??= legacyTicketFontIds[t['font'] ?? 'futura'];
    t.remove('font');
  }
  return result;
}

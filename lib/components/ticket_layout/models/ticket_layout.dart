import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

const ticketQrColors = ['000000', '2A2A2A', '17365D', '123B20', '401529'];
bool ticketQrColorReadable(String color, [String background = 'FFFFFF']) {
  if (!RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(color)) return false;
  final channels = [0, 2, 4].map((i) {
    final c = int.parse(color.substring(i, i + 2), radix: 16) / 255;
    return c <= .04045 ? c / 12.92 : math.pow((c + .055) / 1.055, 2.4).toDouble();
  }).toList();
  final luminance = channels[0] * .2126 + channels[1] * .7152 + channels[2] * .0722;
  final bg = [0, 2, 4].map((i) {
    final c = int.parse(background.substring(i, i + 2), radix: 16) / 255;
    return c <= .04045 ? c / 12.92 : math.pow((c + .055) / 1.055, 2.4).toDouble();
  }).toList();
  final back = bg[0] * .2126 + bg[1] * .7152 + bg[2] * .0722;
  return (math.max(luminance, back) + .05) / (math.min(luminance, back) + .05) >= 4.5;
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
  final Rect box;
  final bool visible, locked, bold, italic, underline;
  final double fontSize, minFontSize;
  final int maxLines;
  const TicketElement(
      {required this.id,
      required this.binding,
      required this.box,
      this.visible = true,
      this.locked = false,
      this.fontSize = 12,
      this.minFontSize = 6,
      this.maxLines = 3,
      this.color = '2A2A2A',
      this.align = 'left',
      this.bold = false, this.italic = false, this.underline = false});
  factory TicketElement.fromJson(Map j) {
    final b = j['box'] as Map, s = j['style'] as Map;
    return TicketElement(
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
          {Rect? box,
          bool? visible,
          bool? locked,
          bool? bold, bool? italic, bool? underline,
          double? fontSize,
          String? color,
          String? align,
          int? maxLines}) =>
      TicketElement(
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
          bold: bold ?? this.bold, italic: italic ?? this.italic,
          underline: underline ?? this.underline);
}

Map<String, dynamic> boxJson(Rect b) =>
    {'x': b.left, 'y': b.top, 'width': b.width, 'height': b.height};

class TicketTemplate {
  final Map<String, dynamic> appearance;
  String get font => appearance['font'] as String? ?? 'futura';
  Map get qrAppearance => appearance['qrAppearance'] as Map? ?? const {};
  List<TicketElement> positionedElements(Map<String, String?> data) {
    final flow = (appearance['flow'] as List? ?? const [])
        .map((b) => elements.where((e) => e.binding == b).firstOrNull)
        .whereType<TicketElement>().toList();
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
        appearance: {for (final key in ['font', 'flow', 'flowStep', 'qrAppearance', 'border']) if (j.containsKey(key)) key: j[key]},
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
  TicketTemplate withFont(String value) => TicketTemplate(
      fitPageToTicket: fitPageToTicket, page: page, area: area,
      appearance: {...appearance, 'font': value}, elements: elements);
  TicketTemplate replace(TicketElement e) => TicketTemplate(
      fitPageToTicket: fitPageToTicket,
        appearance: appearance,
      page: page,
      area: area,
      elements: elements.map((old) => old.id == e.id ? e : old).toList());
  TicketTemplate resizeArea(Size size) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      throw const FormatException('Invalid ticket dimensions');
    }
    if (size == area.size) return this;
    final sx = size.width / area.width, sy = size.height / area.height;
    final scale = sx < sy ? sx : sy;
    // Binary-exact coordinates keep Rect.width/height identical for square QR
    // after right-left subtraction and JSON serialization at arbitrary mm sizes.
    double coordinate(double value) => (value * 1024).round() / 1024;
    return TicketTemplate(
        fitPageToTicket: fitPageToTicket,
        appearance: {...appearance, if (appearance['flowStep'] != null) 'flowStep': (appearance['flowStep'] as num) * scale},
        page: fitPageToTicket ? size : page,
        area: Rect.fromLTWH(fitPageToTicket ? 0 : area.left,
            fitPageToTicket ? 0 : area.top, size.width, size.height),
        elements: elements
            .map((e) => e.copyWith(
                box: Rect.fromLTWH(
                    coordinate(e.box.left * sx),
                    coordinate(e.box.top * sy),
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
            area.topLeft == Offset.zero &&
            area.size == page
        : page == const Size(595.28, 841.89) ||
            page == const Size(212.5, 387.5);
    if (!pageValid ||
        !inside(area, page) ||
        elements.length < 2 ||
        elements.length > 11) {
      errors.add('geometry');
    }
    if (!['futura', 'robotoSlab', 'roboto', 'russoOne'].contains(font)) errors.add('font');
    final ids = <String>{}, bindings = <String>{};
    TicketElement? qr;
    for (final e in elements) {
      if (!ids.add(e.id) ||
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
            !ticketQrColorReadable(e.color, qrAppearance['background'] as String? ?? 'FFFFFF')) {
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

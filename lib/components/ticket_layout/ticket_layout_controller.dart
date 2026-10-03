import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'models/ticket_layout.dart';
import 'ticket_snapping.dart';

class TicketLayoutController extends ChangeNotifier {
  TicketLayoutController(this.document,
      {this.artworkKey, this.prepareDocument, this.geometryData})
      : initial = document,
        initialArtworkKey = artworkKey;
  final TicketTemplate Function(TicketTemplate)? prepareDocument;
  final Map<String, String?> Function()? geometryData;
  TicketTemplate positionedDocument(TicketTemplate value) =>
      geometryData == null ? value : value.fixedPositions(geometryData!());
  String? artworkKey;
  final String? initialArtworkKey;
  ({TicketTemplate document, String? artworkKey}) get _snapshot =>
      (document: document, artworkKey: artworkKey);
  final TicketTemplate initial;
  TicketTemplate document;
  final Set<String> selectedIds = {};
  String? get selected => selectedIds.length == 1 ? selectedIds.single : null;
  Rect? selectionRect;
  List<TicketElement> get selections =>
      document.elements.where((e) => selectedIds.contains(e.id)).toList();
  double? guideX, guideY;
  final Set<String> canvasBlockers = {}, canvasHidden = {};
  Offset canvasOrigin = Offset.zero;
  final List<({TicketTemplate document, String? artworkKey})> _undo = [],
      _redo = [];
  TicketTemplate? _gesture;
  Offset _dragOffset = Offset.zero;
  bool get dirty =>
      artworkKey != initialArtworkKey ||
      jsonEncode(initial.toJson()) != jsonEncode(document.toJson());
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  TicketElement? get selection =>
      document.elements.where((e) => e.id == selected).firstOrNull;
  void select(String? id, {bool additive = false}) {
    if (!additive) selectedIds.clear();
    if (id != null && !selectedIds.add(id)) selectedIds.remove(id);
    notifyListeners();
  }

  void selectAll(Iterable<String> ids) {
    selectedIds
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  void beginGesture() {
    if (_gesture == null) {
      _gesture = document;
      _dragOffset = Offset.zero;
      canvasOrigin = Offset.zero;
    }
  }

  void previewDocument(TicketTemplate next) {
    beginGesture();
    document = prepareDocument?.call(next) ?? next;
    notifyListeners();
  }

  void changeBackground(double scale, Offset offset) {
    final next = document.withBackground(scale.clamp(.1, 10),
        Offset(offset.dx.clamp(-10, 10), offset.dy.clamp(-10, 10)));
    if (_gesture == null) {
      replace(next);
    } else {
      previewDocument(next);
    }
  }

  void previewResize(Size size) {
    beginGesture();
    document = _gesture!.resizeArea(size);
    notifyListeners();
  }

  void resizeCanvas(Offset delta,
      {required int handle,
      double zoom = 1,
      bool snap = true,
      double? gridStep,
      Size? backgroundImage}) {
    final base = positionedDocument(_gesture ?? document);
    if (_gesture != null) _dragOffset += delta;
    final drag = _gesture == null ? delta : _dragOffset;
    final maxWidth = base.fitPageToTicket
        ? 842 - 2 * base.pageMargin
        : base.page.width - base.area.left;
    final maxHeight = base.fitPageToTicket
        ? 842 - 2 * base.pageMargin
        : base.page.height - base.area.top;
    final left = [3, 5, 7].contains(handle);
    final top = [4, 5, 6].contains(handle);
    final horizontal = ![1, 4].contains(handle);
    final vertical = ![0, 3].contains(handle);
    double clampX(double x) => left
        ? x.clamp(base.area.width - maxWidth, base.area.width - 60)
        : x.clamp(60, maxWidth);
    double clampY(double y) => top
        ? y.clamp(base.area.height - maxHeight, base.area.height - 60)
        : y.clamp(60, maxHeight);
    var point = Offset(
      horizontal
          ? clampX((left ? 0 : base.area.width) + drag.dx)
          : base.area.width,
      vertical
          ? clampY((top ? 0 : base.area.height) + drag.dy)
          : base.area.height,
    );
    guideX = guideY = null;
    if (snap) {
      final result = snapTicketBox(
          point & Size.zero,
          base.area.size,
          [
            ...base.elements.where((e) => e.visible).map((e) => e.box),
            if (backgroundImage != null)
              base.croppedBackgroundRect(backgroundImage),
          ],
          zoom: zoom,
          gridStep: gridStep);
      point = Offset(
        horizontal ? clampX(result.box.left) : point.dx,
        vertical ? clampY(result.box.top) : point.dy,
      );
      guideX = horizontal ? result.x : null;
      guideY = vertical ? result.y : null;
    }
    canvasBlockers.clear();
    canvasHidden.clear();
    final required =
        base.elements.where((e) => ['qr', 'ticketSymbol'].contains(e.binding));
    for (final e in required) {
      if ((horizontal &&
              (left
                  ? e.box.left < point.dx - .001
                  : e.box.right > point.dx + .001)) ||
          (vertical &&
              (top
                  ? e.box.top < point.dy - .001
                  : e.box.bottom > point.dy + .001))) {
        canvasBlockers.add(e.id);
      }
    }
    for (final e in required) {
      point = Offset(
        !horizontal
            ? point.dx
            : left
                ? math.min(point.dx, e.box.left)
                : math.max(point.dx, e.box.right),
        !vertical
            ? point.dy
            : top
                ? math.min(point.dy, e.box.top)
                : math.max(point.dy, e.box.bottom),
      );
    }
    // Binary-exact origin shifts preserve the square QR contract.
    double originCoordinate(double value, double min) => math.max(
        (value * 1024).floor() / 1024, (min * 1024).ceil() / 1024);
    final origin = Offset(
      left ? originCoordinate(point.dx, base.area.width - maxWidth) : 0,
      top ? originCoordinate(point.dy, base.area.height - maxHeight) : 0,
    );
    if (guideX != null && (point.dx - guideX!).abs() > .001) guideX = null;
    if (guideY != null && (point.dy - guideY!).abs() > .001) guideY = null;
    final next = base.resizeCanvasArea(Size(
        left ? base.area.width - origin.dx : point.dx,
        top ? base.area.height - origin.dy : point.dy),
      origin: origin,
      backgroundImage: backgroundImage,
    );
    if (guideX != null) guideX = guideX! - origin.dx;
    if (guideY != null) guideY = guideY! - origin.dy;
    canvasHidden.addAll(base.elements
        .where((e) =>
            e.visible && !next.elements.firstWhere((n) => n.id == e.id).visible)
        .map((e) => e.id));
    if (next.validate('wide').isNotEmpty) {
      guideX = guideY = null;
      notifyListeners();
      return;
    }
    canvasOrigin = origin;
    if (_gesture == null) {
      replace(next);
    } else {
      previewDocument(next);
    }
  }

  void endGesture() {
    guideX = guideY = null;
    final before = _gesture;
    _gesture = null;
    if (before != null &&
        jsonEncode(before.toJson()) != jsonEncode(document.toJson())) {
      _undo.add((document: before, artworkKey: artworkKey));
      _redo.clear();
    }
    notifyListeners();
  }

  void cancelGesture() {
    canvasBlockers.clear();
    canvasHidden.clear();
    guideX = guideY = null;
    if (_gesture != null) {
      document = _gesture!;
      _gesture = null;
      notifyListeners();
    }
  }

  void replace(TicketTemplate next, {String? artworkKey}) {
    _undo.add(_snapshot);
    _redo.clear();
    document = prepareDocument?.call(next) ?? next;
    this.artworkKey = artworkKey ?? this.artworkKey;
    guideX = guideY = null;
    selectedIds.removeWhere((id) => !document.elements.any((e) => e.id == id));
    notifyListeners();
  }

  void change(TicketElement e) => _changeOn(document, e);

  void _changeOn(TicketTemplate base, TicketElement e) {
    if (e.binding == 'qr' &&
        document.elements.where((item) => item.id == e.id).firstOrNull?.box !=
            e.box) {
      // Binary-exact coordinates keep Rect's right-left/bottom-top square after
      // touch drags and resizing, so Dart and the PDF/SQL contract agree.
      double fixed(double value) => (value * 1024).floor() / 1024;
      final b = e.box;
      final side = fixed(b.width);
      e = e.copyWith(
          box: Rect.fromLTWH(fixed(b.left), fixed(b.top), side, side));
    }
    if (_gesture == null) {
      _undo.add(_snapshot);
      _redo.clear();
    }
    final next = base.replace(e);
    document = prepareDocument?.call(next) ?? next;
    notifyListeners();
  }

  void move(Offset delta,
      {double zoom = 1, bool snap = true, double? gridStep}) {
    final base = positionedDocument(_gesture ?? document);
    final moving = base.elements
        .where((e) => selectedIds.contains(e.id) && !e.locked)
        .toList();
    if (moving.isEmpty) return;
    if (_gesture != null) _dragOffset += delta;
    final bounds =
        moving.map((e) => e.box).reduce((a, b) => a.expandToInclude(b));
    var b = bounds.shift(_gesture == null ? delta : _dragOffset);
    final area = document.area.size;
    guideX = guideY = null;
    if (snap) {
      final result = snapTicketBox(
          b,
          area,
          base.elements
              .where((e) => e.visible && !selectedIds.contains(e.id))
              .map((e) => e.box),
          zoom: zoom,
          gridStep: gridStep);
      b = result.box;
      guideX = result.x;
      guideY = result.y;
    }
    b = Rect.fromLTWH(b.left.clamp(0, area.width - b.width),
        b.top.clamp(0, area.height - b.height), b.width, b.height);
    final shift = Offset(((b.left - bounds.left) * 1024).round() / 1024,
        ((b.top - bounds.top) * 1024).round() / 1024);
    if (_gesture == null) {
      _undo.add(_snapshot);
      _redo.clear();
    }
    document = base;
    for (final element in moving) {
      document =
          document.replace(element.copyWith(box: element.box.shift(shift)));
    }
    notifyListeners();
  }

  void resize(Offset delta,
      {bool widthOnly = false,
      double zoom = 1,
      bool snap = false,
      double? gridStep}) {
    final selectedElement = selection;
    if (selectedElement == null || selectedElement.locked) return;
    final base = positionedDocument(_gesture ?? document);
    final e = base.elements.firstWhere((e) => e.id == selectedElement.id);
    if (_gesture != null) _dragOffset += delta;
    final drag = _gesture == null ? delta : _dragOffset;
    final b = e.box, a = document.area;
    final stretch = widthOnly && e.binding != 'qr' && e.binding != 'logo';
    final min = e.binding == 'qr' ? 60.0 : 12.0;
    final maximum =
        math.min((a.width - b.left) / b.width, (a.height - b.top) / b.height);
    final upper = stretch
        ? (a.width - b.left) / b.width
        : math.min(maximum, 72 / e.fontSize);
    final lower = stretch
        ? math.min(12 / b.width, upper)
        : math.min(upper, math.max(min / b.width, e.minFontSize / e.fontSize));
    var ratio = (stretch
            ? 1 + drag.dx / b.width
            : 1 + (drag.dx + drag.dy) / (b.width + b.height))
        .clamp(lower, upper);
    var next = Rect.fromLTWH(
        b.left, b.top, b.width * ratio, stretch ? b.height : b.height * ratio);
    guideX = guideY = null;
    if (snap) {
      final result = snapTicketBox(
          next,
          a.size,
          base.elements
              .where((other) => other.visible && other.id != e.id)
              .map((e) => e.box),
          zoom: zoom,
          gridStep: gridStep,
          anchor: b.topLeft,
          widthOnly: stretch,
          minRatio: lower / ratio,
          maxRatio: upper / ratio);
      next = result.box;
      ratio = next.width / b.width;
      guideX = result.x;
      guideY = result.y;
    }
    _changeOn(
        base,
        e.copyWith(
            box: next,
            fontSize: stretch
                ? e.fontSize
                : (e.fontSize * ratio).clamp(e.minFontSize, 72)));
  }

  void transformBackground(Size image, Offset delta,
      {int? corner, double zoom = 1, bool snap = true, double? gridStep}) {
    final base = _gesture ?? document;
    if (_gesture != null) _dragOffset += delta;
    final drag = _gesture == null ? delta : _dragOffset;
    final original = base.croppedBackgroundRect(image);
    final full = base.backgroundRect(image);
    var next = original.shift(drag);
    Offset? anchor;
    var lower = 0.0, upper = double.infinity;
    if (corner != null) {
      final corners = [
        original.topLeft,
        original.topRight,
        original.bottomRight,
        original.bottomLeft
      ];
      anchor = corners[(corner + 2) % 4];
      final vector = corners[corner] - anchor;
      final ratio = (1 +
              (drag.dx * vector.dx + drag.dy * vector.dy) /
                  vector.distanceSquared)
          .clamp(.1 / base.backgroundScale, 10 / base.backgroundScale);
      next = Rect.fromPoints(anchor, anchor + vector * ratio);
      lower = .1 / (base.backgroundScale * ratio);
      upper = 10 / (base.backgroundScale * ratio);
    }
    guideX = guideY = null;
    if (snap) {
      final result = snapTicketBox(
          next,
          base.area.size,
          positionedDocument(base)
              .elements
              .where((e) => e.visible)
              .map((e) => e.box),
          zoom: zoom,
          gridStep: gridStep,
          anchor: anchor,
          minRatio: lower,
          maxRatio: upper);
      next = result.box;
      guideX = result.x;
      guideY = result.y;
    }
    final ratio = next.width / original.width;
    final center = next.topLeft + (full.center - original.topLeft) * ratio;
    changeBackground(
        base.backgroundScale * ratio,
        Offset((center.dx - base.area.width / 2) / base.area.width,
            (center.dy - base.area.height / 2) / base.area.height));
  }

  void cropBackground(Size image, Offset delta,
      {int? corner, double zoom = 1, bool snap = true, double? gridStep}) {
    final base = _gesture ?? document;
    if (_gesture != null) _dragOffset += delta;
    final drag = _gesture == null ? delta : _dragOffset;
    final full = base.backgroundRect(image),
        crop = base.croppedBackgroundRect(image);
    final others = positionedDocument(base)
        .elements
        .where((e) => e.visible)
        .map((e) => e.box);
    var next = crop.shift(drag);
    guideX = guideY = null;
    if (corner == null) {
      if (snap) {
        final result = snapTicketBox(next, base.area.size, others,
            zoom: zoom, gridStep: gridStep);
        next = result.box;
        guideX = result.x;
        guideY = result.y;
      }
      next = Rect.fromLTWH(
          next.left
              .clamp(full.left, math.max(full.left, full.right - crop.width)),
          next.top
              .clamp(full.top, math.max(full.top, full.bottom - crop.height)),
          crop.width,
          crop.height);
    } else {
      final corners = [
        crop.topLeft,
        crop.topRight,
        crop.bottomRight,
        crop.bottomLeft
      ];
      final anchor = corners[(corner + 2) % 4];
      var point = corners[corner] + drag;
      if (snap) {
        final result = snapTicketBox(point & Size.zero, base.area.size, others,
            zoom: zoom, gridStep: gridStep);
        point = result.box.topLeft;
        guideX = result.x;
        guideY = result.y;
      }
      point = Offset(
          corner == 0 || corner == 3
              ? point.dx.clamp(
                  full.left, anchor.dx - math.min(full.width * .01, crop.width))
              : point.dx.clamp(
                  anchor.dx + math.min(full.width * .01, crop.width),
                  full.right),
          corner == 0 || corner == 1
              ? point.dy.clamp(full.top,
                  anchor.dy - math.min(full.height * .01, crop.height))
              : point.dy.clamp(
                  anchor.dy + math.min(full.height * .01, crop.height),
                  full.bottom));
      next = Rect.fromPoints(anchor, point);
    }
    if (guideX != null &&
        ![next.left, next.center.dx, next.right]
            .any((v) => (v - guideX!).abs() < .001)) guideX = null;
    if (guideY != null &&
        ![next.top, next.center.dy, next.bottom]
            .any((v) => (v - guideY!).abs() < .001)) guideY = null;
    final result = base.withBackgroundCrop(Rect.fromLTWH(
        ((next.left - full.left) / full.width).clamp(0, 1),
        ((next.top - full.top) / full.height).clamp(0, 1),
        (next.width / full.width).clamp(.001, 1),
        (next.height / full.height).clamp(.001, 1)));
    if (_gesture == null) {
      replace(result);
    } else {
      previewDocument(result);
    }
  }

  void undo() {
    canvasBlockers.clear();
    canvasHidden.clear();
    if (!canUndo) return;
    _redo.add(_snapshot);
    final previous = _undo.removeLast();
    document = previous.document;
    artworkKey = previous.artworkKey;
    notifyListeners();
  }

  void redo() {
    canvasBlockers.clear();
    canvasHidden.clear();
    if (!canRedo) return;
    _undo.add(_snapshot);
    final next = _redo.removeLast();
    document = next.document;
    artworkKey = next.artworkKey;
    notifyListeners();
  }
}

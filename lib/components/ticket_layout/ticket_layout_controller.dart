import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'models/ticket_layout.dart';
import 'ticket_snapping.dart';

class TicketLayoutController extends ChangeNotifier {
  TicketLayoutController(this.document, {this.artworkKey})
      : initial = document,
        initialArtworkKey = artworkKey;
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
    }
  }

  void previewDocument(TicketTemplate next) {
    beginGesture();
    document = next;
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
    document = next;
    this.artworkKey = artworkKey ?? this.artworkKey;
    guideX = guideY = null;
    selectedIds.removeWhere((id) => !document.elements.any((e) => e.id == id));
    notifyListeners();
  }

  void change(TicketElement e) {
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
    document = document.replace(e);
    notifyListeners();
  }

  void move(Offset delta,
      {double zoom = 1, bool snap = true, double? gridStep}) {
    final moving = (_gesture ?? document)
        .elements
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
          document.elements
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
    final e = (_gesture ?? document)
        .elements
        .firstWhere((e) => e.id == selectedElement.id);
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
          document.elements
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
    change(e.copyWith(
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
    final original = base.backgroundRect(image);
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
      final result = snapTicketBox(next, base.area.size,
          base.elements.where((e) => e.visible).map((e) => e.box),
          zoom: zoom,
          gridStep: gridStep,
          anchor: anchor,
          minRatio: lower,
          maxRatio: upper);
      next = result.box;
      guideX = result.x;
      guideY = result.y;
    }
    changeBackground(
        base.backgroundScale * next.width / original.width,
        Offset((next.center.dx - base.area.width / 2) / base.area.width,
            (next.center.dy - base.area.height / 2) / base.area.height));
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(_snapshot);
    final previous = _undo.removeLast();
    document = previous.document;
    artworkKey = previous.artworkKey;
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_snapshot);
    final next = _redo.removeLast();
    document = next.document;
    artworkKey = next.artworkKey;
    notifyListeners();
  }
}

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../ticket_layout_controller.dart';
import '../ticket_layout_service.dart';
import '../ticket_text.dart';
import '../ticket_layout_strings.dart';

class TicketLayoutCanvas extends StatefulWidget {
  final VoidCallback? onDismiss, onCanvasElementAttempt;
  final TicketLayoutController controller;
  final TicketLayoutResources resources;
  final Map<String, String?> data;
  final bool pan,
      wholePage,
      snap,
      grid,
      additiveSelection,
      editBackground,
      cropBackground,
      editCanvas;
  final double gridStep;
  final TransformationController transform;
  const TicketLayoutCanvas(
      {super.key,
      this.onDismiss,
      this.onCanvasElementAttempt,
      required this.controller,
      required this.resources,
      required this.data,
      required this.transform,
      this.pan = false,
      this.editBackground = false,
      this.cropBackground = false,
      this.editCanvas = false,
      this.additiveSelection = false,
      this.wholePage = false,
      this.snap = true,
      this.grid = false,
      this.gridStep = 10});
  @override
  State<TicketLayoutCanvas> createState() => TicketLayoutCanvasState();
}

class TicketLayoutCanvasState extends State<TicketLayoutCanvas> {
  final _viewport = GlobalKey();
  final _focus = FocusNode();
  final Set<int> _pointers = {};
  int? _editing, _imageCorner, _canvasHandle;
  int? _middlePan;
  Offset? _last, _marqueeStart, _dragStart;
  String? _pendingToggle;
  Set<String> _selectionBeforeMarquee = {};
  TicketResizeHandle? _resizeHandle, _hoverHandle;
  bool _space = false;
  double get zoom {
    final matrix = widget.transform.value;
    return math.sqrt(
        math.pow(matrix.entry(0, 0), 2) + math.pow(matrix.entry(1, 0), 2));
  }

  ui.Image? get backgroundImage {
    final artwork = widget.resources.artworks[widget.controller.artworkKey];
    return artwork != null ? artwork.image : widget.resources.background;
  }

  Size? get backgroundSize => backgroundImage == null
      ? null
      : Size(backgroundImage!.width.toDouble(),
          backgroundImage!.height.toDouble());
  Rect get viewBounds {
    final doc = widget.controller.document;
    var bounds = widget.wholePage ? Offset.zero & doc.page : doc.area;
    if (widget.editBackground && backgroundSize != null) {
      bounds = bounds.expandToInclude((widget.cropBackground
              ? doc.backgroundRect(backgroundSize!)
              : doc.croppedBackgroundRect(backgroundSize!))
          .shift(doc.area.topLeft));
    }
    return bounds;
  }

  bool get panning => widget.pan || _space;
  @override
  void initState() {
    super.initState();
    widget.transform.addListener(constrainView);
    WidgetsBinding.instance.addPostFrameCallback((_) => fit());
  }

  @override
  void didUpdateWidget(covariant TicketLayoutCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wholePage != widget.wholePage ||
        oldWidget.editBackground != widget.editBackground ||
        oldWidget.cropBackground != widget.cropBackground ||
        oldWidget.editCanvas != widget.editCanvas) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fit());
    }
  }

  @override
  void dispose() {
    widget.transform.removeListener(constrainView);
    _focus.dispose();
    super.dispose();
  }

  Size get viewportSize =>
      (_viewport.currentContext?.findRenderObject() as RenderBox?)?.size ??
      const Size(800, 500);
  bool _constraining = false;
  void constrainView() {
    if (_constraining || !mounted || _viewport.currentContext == null) return;
    final bounds = viewBounds;
    final size = viewportSize, matrix = widget.transform.value;
    final scale = zoom;
    double translation(
        double current, double start, double end, double viewport) {
      final inset = math.min(16.0, viewport / 4);
      final low = viewport - inset - end * scale, high = inset - start * scale;
      return current.clamp(math.min(low, high), math.max(low, high));
    }

    final x =
        translation(matrix.entry(0, 3), bounds.left, bounds.right, size.width);
    final y =
        translation(matrix.entry(1, 3), bounds.top, bounds.bottom, size.height);
    if ((x - matrix.entry(0, 3)).abs() < .001 &&
        (y - matrix.entry(1, 3)).abs() < .001) {
      return;
    }
    final next = matrix.clone()
      ..setEntry(0, 3, x)
      ..setEntry(1, 3, y);
    _constraining = true;
    widget.transform.value = next;
    _constraining = false;
  }

  void fit() {
    if (!mounted) return;
    final b = viewBounds;
    final size = viewportSize;
    final scale = math
        .min((size.width - 40) / b.width, (size.height - 40) / b.height)
        .clamp(widget.editBackground ? .02 : .2, 6.0);
    widget.transform.value = Matrix4.identity()
      ..translateByDouble((size.width - b.width * scale) / 2 - b.left * scale,
          (size.height - b.height * scale) / 2 - b.top * scale, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void zoomAt(double factor, [Offset? anchor]) {
    final point = anchor ?? viewportSize.center(Offset.zero);
    final scene = widget.transform.toScene(point);
    final scale = (zoom * factor).clamp(widget.editBackground ? .02 : .2, 6.0);
    widget.transform.value = Matrix4.identity()
      ..translateByDouble(
          point.dx - scene.dx * scale, point.dy - scene.dy * scale, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  TicketResizeHandle? _handleAt(Rect box, Offset point) {
    final tolerance = 10 / zoom;
    // Corners take precedence over sides, including on short text boxes.
    for (final handle
        in TicketResizeHandle.values.where((h) => h.x != 0 && h.y != 0)) {
      if ((point - handle.position(box)).distance <= tolerance) return handle;
    }
    final verticalTolerance = math.min(6 / zoom, box.height / 4);
    final horizontalTolerance = math.min(6 / zoom, box.width / 4);
    if (point.dx >= box.left && point.dx <= box.right) {
      if ((point.dy - box.top).abs() <= verticalTolerance) {
        return TicketResizeHandle.top;
      }
      if ((point.dy - box.bottom).abs() <= verticalTolerance) {
        return TicketResizeHandle.bottom;
      }
    }
    if (point.dy >= box.top && point.dy <= box.bottom) {
      if ((point.dx - box.left).abs() <= horizontalTolerance) {
        return TicketResizeHandle.left;
      }
      if ((point.dx - box.right).abs() <= horizontalTolerance) {
        return TicketResizeHandle.right;
      }
    }
    return null;
  }

  MouseCursor get _cursor {
    final handle = _resizeHandle ?? _hoverHandle;
    if (panning) return SystemMouseCursors.grab;
    if (handle == null) return MouseCursor.defer;
    if (handle.x == 0) return SystemMouseCursors.resizeUpDown;
    if (handle.y == 0) return SystemMouseCursors.resizeLeftRight;
    return handle.x == handle.y
        ? SystemMouseCursors.resizeUpLeftDownRight
        : SystemMouseCursors.resizeUpRightDownLeft;
  }

  void _hover(PointerHoverEvent event) {
    final selected = widget.controller.document
        .positionedElements(widget.data)
        .where((e) => e.id == widget.controller.selected)
        .firstOrNull;
    final point = widget.transform.toScene(event.localPosition) -
        widget.controller.document.area.topLeft;
    final handle = panning ||
            widget.editBackground ||
            widget.editCanvas ||
            selected == null ||
            selected.locked
        ? null
        : _handleAt(selected.box, point);
    if (handle != _hoverHandle) setState(() => _hoverHandle = handle);
  }

  void _down(PointerDownEvent event) {
    _pendingToggle = null;
    _focus.requestFocus();
    _pointers.add(event.pointer);
    if (event.buttons == kMiddleMouseButton) {
      _middlePan = event.pointer;
      return;
    }
    if (_pointers.length > 1) {
      _marqueeStart = null;
      widget.controller.selectionRect = null;
      widget.controller.cancelGesture();
      setState(() => _editing = null);
      return;
    }
    if (panning || event.buttons != kPrimaryButton) return;
    final point = widget.transform.toScene(event.localPosition) -
        widget.controller.document.area.topLeft;
    if (widget.editCanvas) {
      final size = widget.controller.document.area.size;
      final handles = [
        Offset(size.width, size.height / 2),
        Offset(size.width / 2, size.height),
        Offset(size.width, size.height),
        Offset(0, size.height / 2),
        Offset(size.width / 2, 0),
        Offset.zero,
        Offset(size.width, 0),
        Offset(0, size.height),
      ];
      _canvasHandle = null;
      for (var i = 0; i < handles.length; i++) {
        if ((point - handles[i]).distance < 22 / zoom) {
          _canvasHandle = i;
          break;
        }
      }
      if (_canvasHandle == null) {
        if (widget.controller.document
            .positionedElements(widget.data)
            .any((e) => e.visible && e.box.contains(point))) {
          widget.onCanvasElementAttempt?.call();
        }
        return;
      }
      widget.controller.beginGesture();
      _last = point;
      setState(() => _editing = event.pointer);
      return;
    }
    if (widget.editBackground) {
      if (backgroundSize == null) return;
      final rect =
          widget.controller.document.croppedBackgroundRect(backgroundSize!);
      final corners = [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft
      ];
      _imageCorner = null;
      for (var i = 0; i < corners.length; i++) {
        if ((point - corners[i]).distance < 14 / zoom) {
          _imageCorner = i;
          break;
        }
      }
      if (_imageCorner == null && !rect.contains(point)) return;
      widget.controller.beginGesture();
      _last = point;
      setState(() => _editing = event.pointer);
      return;
    }
    final selected = widget.controller.document
        .positionedElements(widget.data)
        .where((e) => e.id == widget.controller.selected)
        .firstOrNull;
    _resizeHandle = selected == null || selected.locked
        ? null
        : _handleAt(selected.box, point);
    final hit = widget.controller.document
        .positionedElements(widget.data)
        .reversed
        .where((e) => e.visible && e.box.inflate(3 / zoom).contains(point))
        .firstOrNull;
    final additive = widget.additiveSelection ||
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (_resizeHandle == null) {
      if (hit == null) {
        _marqueeStart = point;
        _selectionBeforeMarquee =
            additive ? {...widget.controller.selectedIds} : {};
        widget.controller.selectAll(_selectionBeforeMarquee);
        setState(() => _editing = event.pointer);
        return;
      }
      if (additive && widget.controller.selectedIds.contains(hit.id)) {
        _pendingToggle = hit.id;
      } else if (!widget.controller.selectedIds.contains(hit.id)) {
        widget.controller.select(hit.id, additive: additive);
      }
    }
    if (!widget.controller.selections.any((e) => !e.locked)) {
      if (_pendingToggle != null)
        widget.controller.select(_pendingToggle, additive: true);
      _pendingToggle = null;
      return;
    }
    widget.controller.beginGesture();
    _last = _dragStart = point;
    setState(() => _editing = event.pointer);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer == _middlePan) {
      final next = widget.transform.value.clone();
      next.setEntry(0, 3, next.entry(0, 3) + event.delta.dx);
      next.setEntry(1, 3, next.entry(1, 3) + event.delta.dy);
      widget.transform.value = next;
      return;
    }
    if (event.pointer != _editing || _pointers.length != 1) return;
    final point = widget.transform.toScene(event.localPosition) -
        widget.controller.document.area.topLeft;
    if (widget.editCanvas && _last != null && _canvasHandle != null) {
      final beforeOrigin = widget.controller.canvasOrigin;
      widget.controller.resizeCanvas(event.delta / zoom,
          backgroundImage: backgroundSize,
          handle: _canvasHandle!,
          zoom: zoom,
          snap: widget.snap && !HardwareKeyboard.instance.isAltPressed,
          gridStep: widget.grid ? widget.gridStep : null);
      final shift = (widget.controller.canvasOrigin - beforeOrigin) * zoom;
      if (shift != Offset.zero) {
        final matrix = widget.transform.value.clone();
        matrix.setEntry(0, 3, matrix.entry(0, 3) + shift.dx);
        matrix.setEntry(1, 3, matrix.entry(1, 3) + shift.dy);
        widget.transform.value = matrix;
      }
      _last = point;
      return;
    }
    if (widget.editBackground && _last != null) {
      (widget.cropBackground
              ? widget.controller.cropBackground
              : widget.controller.transformBackground)(
          backgroundSize!, point - _last!,
          corner: _imageCorner,
          zoom: zoom,
          snap: widget.snap && !HardwareKeyboard.instance.isAltPressed,
          gridStep: widget.grid ? widget.gridStep : null);
      _last = point;
      return;
    }
    if (_marqueeStart != null) {
      final rect = Rect.fromPoints(_marqueeStart!, point);
      widget.controller.selectionRect = rect;
      widget.controller.selectAll({
        ..._selectionBeforeMarquee,
        ...widget.controller.document
            .positionedElements(widget.data)
            .where((e) => e.visible && rect.overlaps(e.box))
            .map((e) => e.id)
      });
      return;
    }
    if (_pendingToggle != null) {
      if ((point - _dragStart!).distance * zoom < 3) return;
      _pendingToggle = null;
    }
    final delta = point - _last!;
    _last = point;
    if (_resizeHandle != null) {
      widget.controller.resize(delta,
          handle: _resizeHandle!,
          zoom: zoom,
          snap: widget.snap && !HardwareKeyboard.instance.isAltPressed,
          gridStep: widget.grid ? widget.gridStep : null);
    } else {
      widget.controller.move(delta,
          zoom: zoom,
          snap: widget.snap && !HardwareKeyboard.instance.isAltPressed,
          gridStep: widget.grid ? widget.gridStep : null);
    }
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_middlePan == e.pointer) _middlePan = null;
    if (_editing == e.pointer) {
      _resizeHandle = null;
      if (_pendingToggle != null && e is PointerUpEvent) {
        widget.controller.select(_pendingToggle, additive: true);
      }
      _pendingToggle = null;
      _marqueeStart = null;
      widget.controller.selectionRect = null;
      widget.controller.endGesture();
      setState(() => _editing = null);
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e.logicalKey == LogicalKeyboardKey.space) {
      setState(() => _space = e is! KeyUpEvent);
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!widget.editBackground &&
        ctrl &&
        e.logicalKey == LogicalKeyboardKey.keyA) {
      widget.controller.selectAll(widget.controller.document.elements
          .where((e) => e.visible)
          .map((e) => e.id));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      widget.controller.cancelGesture();
      widget.controller.select(null);
      _marqueeStart = null;
      widget.controller.selectionRect = null;
      setState(() => _editing = null);
      widget.onDismiss?.call();
      return KeyEventResult.handled;
    }
    if (!widget.editBackground && e.logicalKey == LogicalKeyboardKey.delete) {
      final s = widget.controller.selection;
      if (s != null && !['qr', 'ticketSymbol'].contains(s.binding)) {
        widget.controller.change(s.copyWith(visible: false));
      }
      return KeyEventResult.handled;
    }
    final step = HardwareKeyboard.instance.isShiftPressed ? 10.0 : 1.0;
    final delta = {
      LogicalKeyboardKey.arrowLeft: Offset(-step, 0),
      LogicalKeyboardKey.arrowRight: Offset(step, 0),
      LogicalKeyboardKey.arrowUp: Offset(0, -step),
      LogicalKeyboardKey.arrowDown: Offset(0, step)
    }[e.logicalKey];
    if (delta != null) {
      if (widget.cropBackground &&
          widget.editBackground &&
          backgroundSize != null) {
        widget.controller.cropBackground(backgroundSize!, delta, snap: false);
      } else if (widget.editBackground) {
        final doc = widget.controller.document;
        widget.controller.changeBackground(
            doc.backgroundScale,
            doc.backgroundOffset +
                Offset(delta.dx / doc.area.width, delta.dy / doc.area.height));
      } else {
        widget.controller.move(delta, snap: false);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
      focusNode: _focus,
      onKeyEvent: _key,
      child: ClipRect(
          child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: MouseRegion(
                  cursor: _cursor,
                  onHover: _hover,
                  onExit: (_) => setState(() => _hoverHandle = null),
                  child: Listener(
                      key: _viewport,
                      onPointerDown: _down,
                      onPointerMove: _move,
                      onPointerUp: _up,
                      onPointerCancel: (e) {
                        widget.controller.cancelGesture();
                        _up(e);
                      },
                      child: InteractiveViewer(
                          transformationController: widget.transform,
                          constrained: false,
                          boundaryMargin: const EdgeInsets.all(double.infinity),
                          minScale: widget.editBackground ? .02 : .2,
                          maxScale: 6,
                          panEnabled: panning || _editing == null,
                          scaleEnabled: true,
                          child: ListenableBuilder(
                              listenable: widget.transform,
                              builder: (context, _) => RepaintBoundary(
                                  child: CustomPaint(
                                      size: widget.controller.document.page,
                                      painter: TicketLayoutPainter(
                                          widget.controller,
                                          widget.resources,
                                          widget.data,
                                          zoom: zoom,
                                          editBackground: widget.editBackground,
                                          editCanvas: widget.editCanvas,
                                          cropBackground: widget.cropBackground,
                                          gridStep: widget.grid
                                              ? widget.gridStep
                                              : null))))))))));
}

class TicketLayoutPainter extends CustomPainter {
  final TicketLayoutController controller;
  final TicketLayoutResources resources;
  final Map<String, String?> data;
  final double zoom;
  final double? gridStep;
  final bool cropToTicket, editBackground, cropBackground, editCanvas;
  TicketLayoutPainter(this.controller, this.resources, this.data,
      {this.zoom = 1,
      this.gridStep,
      this.cropToTicket = false,
      this.editBackground = false,
      this.cropBackground = false,
      this.editCanvas = false})
      : super(repaint: controller);
  void _image(Canvas canvas, ui.Image image, Rect box, {double opacity = 1}) {
    final fitted = applyBoxFit(BoxFit.contain,
        Size(image.width.toDouble(), image.height.toDouble()), box.size);
    canvas.drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        Alignment.center.inscribe(fitted.destination, box),
        Paint()
          ..color = Colors.white.withValues(alpha: opacity)
          ..filterQuality = FilterQuality.medium);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final doc = controller.document;
    canvas.save();
    if (cropToTicket) {
      canvas.clipRect(Offset.zero & size);
      canvas.translate(-doc.area.left, -doc.area.top);
    }
    canvas.drawRect(Offset.zero & doc.page, Paint()..color = Colors.white);
    if (doc.canvasOpacity < 1) {
      canvas.save();
      canvas.clipRect(doc.area);
      final step = 10 / zoom;
      for (double y = doc.area.top; y < doc.area.bottom; y += step) {
        for (double x = doc.area.left; x < doc.area.right; x += step) {
          final dark = (((x - doc.area.left) / step).round() +
                  ((y - doc.area.top) / step).round())
              .isEven;
          canvas.drawRect(Rect.fromLTWH(x, y, step, step),
              Paint()..color = dark ? const Color(0xffe5e7eb) : Colors.white);
        }
      }
      canvas.restore();
    }
    if (doc.canvasOpacity > 0) {
      canvas.drawRect(
          doc.area,
          Paint()
            ..color = Color(int.parse('ff${doc.canvasColor}', radix: 16))
                .withValues(alpha: doc.canvasOpacity));
    }
    final artwork = resources.artworks[controller.artworkKey];
    final background = artwork != null ? artwork.image : resources.background;
    if (background != null) {
      if (editBackground && cropBackground) {
        _image(
            canvas,
            background,
            doc
                .backgroundRect(Size(
                    background.width.toDouble(), background.height.toDouble()))
                .shift(doc.area.topLeft),
            opacity: .2);
      }
      canvas.save();
      canvas.clipRect(doc.area);
      canvas.clipRect(doc
          .croppedBackgroundRect(
              Size(background.width.toDouble(), background.height.toDouble()))
          .shift(doc.area.topLeft));
      _image(
          canvas,
          background,
          doc
              .backgroundRect(Size(
                  background.width.toDouble(), background.height.toDouble()))
              .shift(doc.area.topLeft));
      canvas.restore();
    }
    if (doc.appearance['border'] == true) {
      final paint = Paint()
        ..color = const Color(0xffe0e0e0)
        ..strokeWidth = 1;
      for (double x = doc.area.left; x < doc.area.right; x += 5) {
        for (final y in [doc.area.top, doc.area.bottom]) {
          canvas.drawLine(Offset(x, y),
              Offset(math.min(x + 3.75, doc.area.right), y), paint);
        }
      }
      for (double y = doc.area.top; y < doc.area.bottom; y += 5) {
        for (final x in [doc.area.left, doc.area.right]) {
          canvas.drawLine(Offset(x, y),
              Offset(x, math.min(y + 3.75, doc.area.bottom)), paint);
        }
      }
    }
    canvas.save();
    canvas.translate(doc.area.left, doc.area.top);
    if (gridStep != null && gridStep! > 0) {
      final paint = Paint()
        ..color = Colors.blueGrey.withValues(alpha: .22)
        ..strokeWidth = .6 / zoom;
      for (double x = 0; x <= doc.area.width; x += gridStep!) {
        canvas.drawLine(Offset(x, 0), Offset(x, doc.area.height), paint);
      }
      for (double y = 0; y <= doc.area.height; y += gridStep!) {
        canvas.drawLine(Offset(0, y), Offset(doc.area.width, y), paint);
      }
    }
    for (final e in doc
        .positionedElements(data)
        .where((e) => e.visible && e.binding != 'qr')) {
      if (e.binding == 'logo') {
        if (resources.logo != null) _image(canvas, resources.logo!, e.box);
        continue;
      }
      final text = data[e.binding];
      if (text == null) continue;
      TicketTextFit fit;
      try {
        fit = fitTicketText(text, e, resources.metricsFor(doc, e));
      } on FormatException {
        canvas.drawRect(
            e.box, Paint()..color = Colors.red.withValues(alpha: .2));
        continue;
      }
      canvas.save();
      canvas.clipRect(e.box);
      for (var i = 0; i < fit.lines.length; i++) {
        var x = e.box.left +
            (e.align == 'center'
                ? (e.box.width - fit.widths[i]) / 2
                : e.align == 'right'
                    ? e.box.width - fit.widths[i]
                    : 0);
        x += ticketTextInsets(e, resources.metricsFor(doc, e)).left * fit.size;
        final lineStart = x;
        final baseline = e.box.top +
            resources.metricsFor(doc, e).ascent * fit.size +
            i * fit.size * 1.2;
        for (final rune in fit.lines[i].runes) {
          final c = String.fromCharCode(rune);
          canvas.save();
          canvas.translate(x, baseline);
          if (e.italic) {
            canvas.transform((Matrix4.identity()
                  ..setEntry(0, 1, -.2125565616700221))
                .storage);
          }
          for (final outline in [if (e.bold) true, false]) {
            final painter = TextPainter(
                text: TextSpan(
                    text: c,
                    style: TextStyle(
                        fontFamily: resources.fontFor(doc, e).loaderName,
                        fontSize: fit.size,
                        height: 1,
                        foreground: Paint()
                          ..color = Color(int.parse('ff${e.color}', radix: 16))
                          ..style = outline
                              ? PaintingStyle.stroke
                              : PaintingStyle.fill
                          ..strokeWidth = fit.size * .04)),
                textDirection: TextDirection.ltr)
              ..layout();
            painter.paint(
                canvas,
                Offset(
                    0,
                    -painter.computeDistanceToActualBaseline(
                        TextBaseline.alphabetic)));
            painter.dispose();
          }
          canvas.restore();
          x += resources.metricsFor(doc, e).width(c, fit.size);
        }
        if (e.underline) {
          canvas.drawLine(
              Offset(lineStart, baseline + fit.size * .1),
              Offset(x, baseline + fit.size * .1),
              Paint()
                ..color = Color(int.parse('ff${e.color}', radix: 16))
                ..strokeWidth = fit.size * .05);
        }
      }
      canvas.restore();
      if (fit.overflow || fit.replaced) {
        canvas.drawCircle(e.box.topRight, 3, Paint()..color = Colors.orange);
      }
    }
    final q = doc.elements.firstWhere((e) => e.binding == 'qr');
    final margin = (doc.qrAppearance['margin'] as num?)?.toDouble() ?? 4;
    final module = q.box.width / (resources.qrSize + 2 * margin);
    canvas.drawRect(
        q.box,
        Paint()
          ..color = Color(int.parse(
                  'ff${doc.qrAppearance['background'] ?? 'FFFFFF'}',
                  radix: 16))
              .withValues(
                  alpha:
                      (doc.qrAppearance['opacity'] as num?)?.toDouble() ?? 1));
    for (var y = 0; y < resources.qrSize; y++) {
      for (var x = 0; x < resources.qrSize; x++) {
        if (resources.qrModules[y * resources.qrSize + x] != 0) {
          canvas.drawRect(
              Rect.fromLTWH(q.box.left + (x + margin) * module,
                  q.box.top + (y + margin) * module, module, module),
              Paint()..color = Color(int.parse('ff${q.color}', radix: 16)));
        }
      }
    }
    final guide = Paint()
      ..color = Colors.pink
      ..strokeWidth = 1 / zoom;
    if (controller.guideX != null) {
      canvas.drawLine(Offset(controller.guideX!, 0),
          Offset(controller.guideX!, doc.area.height), guide);
    }
    if (controller.guideY != null) {
      canvas.drawLine(Offset(0, controller.guideY!),
          Offset(doc.area.width, controller.guideY!), guide);
    }
    if (editCanvas) {
      for (final e in doc.elements
          .where((e) => controller.canvasBlockers.contains(e.id))) {
        canvas.drawRect(e.box.inflate(3 / zoom),
            Paint()..color = Colors.deepOrange.withValues(alpha: .18));
        canvas.drawRect(
            e.box.inflate(3 / zoom),
            Paint()
              ..color = Colors.deepOrange
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3 / zoom);
      }
      final rect = Offset.zero & doc.area.size;
      canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.blue
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / zoom);
      for (final point in [
        rect.centerRight,
        rect.bottomCenter,
        rect.bottomRight,
        rect.centerLeft,
        rect.topCenter,
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
      ]) {
        canvas.drawCircle(point, 12 / zoom,
            Paint()..color = Colors.blue.withValues(alpha: .18));
        canvas.drawCircle(point, 9 / zoom, Paint()..color = Colors.blue);
        canvas.drawCircle(point, 6 / zoom, Paint()..color = Colors.white);
      }
    }
    if (editBackground && background != null) {
      final imageSize =
          Size(background.width.toDouble(), background.height.toDouble());
      final rect = doc.croppedBackgroundRect(imageSize);
      canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.blue
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / zoom);
      final corners = [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft
      ];
      if (cropBackground) {
        final length =
            math.min(18 / zoom, math.min(rect.width, rect.height) / 3);
        for (var i = 0; i < corners.length; i++) {
          final point = corners[i];
          final dx = i == 0 || i == 3 ? length : -length;
          final dy = i < 2 ? length : -length;
          final path = Path()
            ..moveTo(point.dx + dx, point.dy)
            ..lineTo(point.dx, point.dy)
            ..lineTo(point.dx, point.dy + dy);
          canvas.drawPath(
              path,
              Paint()
                ..color = Colors.black54
                ..style = PaintingStyle.stroke
                ..strokeWidth = 6 / zoom);
          canvas.drawPath(
              path,
              Paint()
                ..color = Colors.white
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3 / zoom);
        }
      } else {
        final h = 10 / zoom;
        for (final point in corners) {
          canvas.drawRect(Rect.fromCenter(center: point, width: h, height: h),
              Paint()..color = Colors.blue);
        }
      }
    }

    if (controller.selectionRect case final Rect rect) {
      canvas.drawRect(
          rect, Paint()..color = Colors.blue.withValues(alpha: .12));
      canvas.drawRect(
          rect,
          Paint()
            ..color = Colors.blue
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 / zoom);
    }
    for (final selected in doc.positionedElements(data).where((e) =>
        !editCanvas &&
        !editBackground &&
        controller.selectedIds.contains(e.id))) {
      canvas.drawRect(
          selected.box,
          Paint()
            ..color = Colors.blue
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / zoom);
      if (!selected.locked && controller.selectedIds.length == 1) {
        final h = 10 / zoom;
        for (final handle in TicketResizeHandle.values) {
          canvas.drawRect(
              Rect.fromCenter(
                  center: handle.position(selected.box), width: h, height: h),
              Paint()..color = Colors.blue);
        }
      }
      if (!selected.visible ||
          data[selected.binding] == null &&
              selected.binding != 'qr' &&
              selected.binding != 'logo') {
        final p = TextPainter(
            text: TextSpan(
                text: TicketLayoutStrings.binding(selected.binding),
                style: const TextStyle(color: Colors.blue, fontSize: 10)),
            textDirection: TextDirection.ltr)
          ..layout(maxWidth: selected.box.width);
        p.paint(canvas, selected.box.topLeft);
        p.dispose();
      }
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TicketLayoutPainter old) =>
      old.editBackground != editBackground ||
      old.cropBackground != cropBackground ||
      old.data != data ||
      old.resources != resources ||
      old.zoom != zoom ||
      old.gridStep != gridStep ||
      old.cropToTicket != cropToTicket ||
      old.controller != controller;
}

/// Sidebar thumbnail uses the saved crop, rather than the uncropped source URL.
class TicketBackgroundPreviewPainter extends CustomPainter {
  final ui.Image image;
  final Rect crop;
  TicketBackgroundPreviewPainter(this.image, this.crop);
  @override
  void paint(Canvas canvas, Size size) {
    final source = Rect.fromLTWH(
        crop.left * image.width,
        crop.top * image.height,
        crop.width * image.width,
        crop.height * image.height);
    final fit = applyBoxFit(BoxFit.contain, source.size, size);
    canvas.drawImageRect(
        image,
        source,
        Alignment.center.inscribe(fit.destination, Offset.zero & size),
        Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(covariant TicketBackgroundPreviewPainter old) =>
      old.image != image || old.crop != crop;
}

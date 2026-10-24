import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;
import 'layout_inline_label.dart';
import 'layout_table_selection.dart';
import 'layout_context_menu_stub.dart'
    if (dart.library.js_interop) 'layout_context_menu_web.dart'
    as context_menu;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../layout_scene_cache.dart';
import '../layout_path.dart';
import '../layout_native_text.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

// Matrix4's 3D maximum includes the unchanged z-axis (1), so it cannot
// measure a zoom below 1. The camera is a two-dimensional similarity transform.
double _cameraScale(Matrix4? value) => value == null
    ? 1
    : math.sqrt(
        value.entry(0, 0) * value.entry(0, 0) +
            value.entry(1, 0) * value.entry(1, 0),
      );

/// Shared display-list consumer. All document geometry comes from the core.
class LayoutSceneSurface extends StatefulWidget {
  const LayoutSceneSurface({
    super.key,
    required this.document,
    this.resources = const {},
    this.presentation = const {},
    this.retainPendingTextPreview = false,
    this.selected = const {},
    this.showSeatSelectionChecks = true,
    this.highlightedIds = const {},
    this.selectableIds,
    this.canvasSelected = false,
    this.backgroundSelected = false,
    this.transientForegroundIds = const {},
    this.warningIds = const {},
    this.blockedPlacementHulls = const [],
    this.snapGuides = const [],
    this.onViewportScaleChanged,
    this.onTap,
    this.onSelectDown,
    this.onPointTap,
    this.onHover,
    this.pathPoints = const [],
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
    this.pan = true,
    this.touchPanOnEmpty = false,
    this.panOnTouchDown,
    this.showControls = true,
    this.compactZoomControls = false,
    this.showGrid = false,
    this.gridStep = 8,
    this.gridOrigin = Offset.zero,
    this.animate = true,
    this.onHandleStart,
    this.onDropPreview,
    this.onDrop,
    this.onDropCancel,
    this.onDoubleTap,
    this.marquee,
    this.inlineNode,
    this.onInlineSubmit,
    this.inlineTextStyleBuilder,
    this.onInlineCancel,
    this.onInlineUndo,
    this.onInlineRedo,
    this.onDoubleTapAt,
    this.onContextMenu,
  });
  final VenueLayoutDocument document;
  final Map<String, dynamic> resources, presentation;
  final Set<String> selected, highlightedIds;

  /// Commercial selections use checked seats; geometry selections use bounds.
  final bool showSeatSelectionChecks;
  final Set<String>? selectableIds;
  final Set<String> transientForegroundIds, warningIds;
  final List<List<List<double>>> blockedPlacementHulls;
  final List<Map<String, dynamic>> snapGuides;
  final ValueChanged<double>? onViewportScaleChanged;
  final ValueChanged<Offset>? onTap, onDragStart, onDragUpdate;
  final ValueChanged<Offset>? onSelectDown, onPointTap, onHover;
  final List<Offset> pathPoints;
  final VoidCallback? onDragEnd, onDragCancel;
  final bool pan, showControls, animate;

  /// In Select mode, a finger on empty canvas navigates instead of drawing a marquee.
  final bool touchPanOnEmpty;
  final bool Function(Offset world)? panOnTouchDown;
  final bool retainPendingTextPreview;
  final bool compactZoomControls;
  final bool showGrid;
  final double gridStep;
  final Offset gridOrigin;
  final bool canvasSelected, backgroundSelected;
  final Rect? marquee;
  final LayoutNode? inlineNode;
  final ValueChanged<String>? onInlineSubmit;
  final Future<TextStyle> Function(LayoutNode)? inlineTextStyleBuilder;
  final VoidCallback? onInlineCancel;
  final VoidCallback? onInlineUndo, onInlineRedo;
  final ValueChanged<Offset>? onDoubleTapAt;
  final void Function(Offset world, Offset global)? onContextMenu;
  final void Function(String, Offset)? onHandleStart, onDropPreview, onDrop;
  final VoidCallback? onDropCancel, onDoubleTap;

  @override
  State<LayoutSceneSurface> createState() => _LayoutSceneSurfaceState();
}

class _LayoutSceneSurfaceState extends State<LayoutSceneSurface>
    with SingleTickerProviderStateMixin {
  // Edge topology changes while painting a strip. Retain the original handle
  // list until pointer-up so its recognizer is never replaced mid-drag.
  VenueLayoutDocument? _edgeHandleDocument;
  LayoutNode? _edgeHandleNode;

  List<List<double>>? _vertexPoints(LayoutNode node) {
    if (node.kind == 'table') {
      return node.surface?['type'] == 'grid' ? localHull(node) : null;
    }
    final points = node.properties['points'];
    if (points is List) {
      return points
          .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
          .toList();
    }
    return const [
          'line',
          'arrow',
          'polyline',
        ].contains(node.properties['shape'])
        ? [
            [-node.width / 2, 0],
            [node.width / 2, 0],
          ]
        : null;
  }

  bool _orthogonalSurface(LayoutNode node) =>
      node.kind == 'table' && node.surface?['type'] == 'grid';

  final _camera = TransformationController();
  String? _hoverMessage, _hoverNodeId;
  Offset _hoverPosition = Offset.zero;
  GlobalKey<TooltipState> _hoverTooltipKey = GlobalKey<TooltipState>();

  MouseCursor get _pickerCursor {
    if (widget.pan && widget.onTap == null) return SystemMouseCursors.grab;
    final id = _hoverNodeId;
    if (id != null &&
        widget.document.nodes.any(
          (n) =>
              n.id == id &&
              (widget.selectableIds?.contains(n.id) ??
                  (n.kind == 'seat' || n.kind == 'capacityArea')),
        )) {
      final raw = widget.presentation[id];
      final p = raw is Map ? raw : const {};
      final unavailable =
          p['selectable'] == false ||
          p['pending'] == true ||
          const [
            'occupied',
            'unavailable',
            'disabled',
            'reserved',
            'blocked',
            'sold',
          ].contains(p['status']);
      return unavailable ? SystemMouseCursors.basic : SystemMouseCursors.click;
    }
    return SystemMouseCursors.basic;
  }

  void _hideHoverTooltip({bool clearNode = false}) {
    if (_hoverMessage != null || (clearNode && _hoverNodeId != null)) {
      setState(() {
        _hoverMessage = null;
        if (clearNode) _hoverNodeId = null;
      });
    }
  }

  void _showHoverTooltip(Offset global, Offset world) {
    final id = hitTest(widget.document, world.dx, world.dy);
    final presentation = id == null ? null : widget.presentation[id];
    final message = presentation is Map
        ? presentation['tooltip'] as String?
        : null;
    if (message == _hoverMessage && id == _hoverNodeId) return;
    final box = context.findRenderObject() as RenderBox?;
    setState(() {
      _hoverMessage = message;
      _hoverNodeId = id;
      _hoverPosition = box?.globalToLocal(global) ?? Offset.zero;
      _hoverTooltipKey = GlobalKey<TooltipState>();
    });
    if (message != null && message.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _hoverTooltipKey.currentState?.ensureTooltipVisible();
      });
    }
  }

  Offset? _doubleTapPosition;
  Offset? _pointTapDown;
  Offset? _dragPointerDown;
  bool _touchPanning = false;
  final _touchPointers = <int>{};
  int? _marginPanPointer;
  Offset? _marginPanDown, _marginPanLast;
  bool _marginPanActive = false;

  void _endMarginPan() {
    _marginPanPointer = null;
    _marginPanDown = _marginPanLast = null;
    _marginPanActive = false;
  }

  late final _motion = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: layoutMotionTokens['reflowMs']!),
  );
  Map<String, dynamic>? _motionFrom;
  late final VoidCallback _stopContextMenu;
  @override
  void initState() {
    super.initState();
    _stopContextMenu = context_menu.suppressCanvasContextMenu((x, y) {
      if (!mounted || widget.onContextMenu == null) return false;
      final box = context.findRenderObject();
      return box is RenderBox &&
          box.hasSize &&
          (Offset.zero & box.size).contains(box.globalToLocal(Offset(x, y)));
    });
  }

  @override
  void didUpdateWidget(LayoutSceneSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animate ||
        (oldWidget.retainPendingTextPreview &&
            !widget.retainPendingTextPreview) ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      _motion.stop();
      _motion.value = 1;
      _motionFrom = null;
      return;
    }
    if (_scene != null &&
        (!identical(oldWidget.document, widget.document) ||
            !sameLayoutValue(oldWidget.presentation, widget.presentation))) {
      _motionFrom = _motion.isAnimating && _motionFrom != null
          ? interpolateScene(_motionFrom!, _scene!, _motion.value)
          : _scene;
      _motion.forward(from: 0);
    }
  }

  bool _interactionDragging = false, _twoFinger = false;
  double _gestureScale = 1;

  Rect? _cameraCanvas;
  double get _fitCameraZoom {
    final bounds = _cameraCanvas, size = _size;
    if (bounds == null || size == null) return 1;
    return math.min(
      math.max(1, size.width - 32) / bounds.width,
      math.max(1, size.height - 32) / bounds.height,
    );
  }

  Matrix4 _boundCamera(Matrix4 value) {
    final bounds = _cameraCanvas, size = _size;
    if (bounds == null || size == null) return value;
    final zoom = _cameraScale(value);
    double translation(double value, double start, double end, double extent) {
      // Each plan edge may reach the viewport midpoint, but never pass it.
      // This caps empty space at half the viewport, even for a narrow plan.
      final visible = extent / 2;
      return value.clamp(visible - end * zoom, extent - visible - start * zoom);
    }

    return value.clone()..setTranslationRaw(
      translation(value.entry(0, 3), bounds.left, bounds.right, size.width),
      translation(value.entry(1, 3), bounds.top, bounds.bottom, size.height),
      0,
    );
  }

  void _moveCamera(Offset focal, Offset delta, double scaleChange) {
    final current = _cameraScale(_camera.value);
    final fit = _fitCameraZoom;
    final factor =
        (current * scaleChange).clamp(
          fit * (widget.compactZoomControls ? 1 : .9),
          fit * (widget.compactZoomControls ? 5 : 20),
        ) /
        current;
    _camera.value = _boundCamera(
      Matrix4.translationValues(focal.dx, focal.dy, 0)
        ..multiply(Matrix4.diagonal3Values(factor, factor, 1))
        ..multiply(
          Matrix4.translationValues(
            -focal.dx + delta.dx,
            -focal.dy + delta.dy,
            0,
          ),
        )
        ..multiply(_camera.value),
    );
  }

  void _pointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent && event is! PointerScaleEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (signal) {
      if (signal is PointerScaleEvent) {
        _moveCamera(signal.localPosition, Offset.zero, signal.scale);
      } else if (signal is PointerScrollEvent) {
        final keyboard = HardwareKeyboard.instance;
        if (!keyboard.isShiftPressed) {
          _moveCamera(
            signal.localPosition,
            Offset.zero,
            math.exp(-signal.scrollDelta.dy / 200),
          );
        } else {
          final delta = keyboard.isShiftPressed && signal.scrollDelta.dx == 0
              ? Offset(signal.scrollDelta.dy, 0)
              : signal.scrollDelta;
          _moveCamera(signal.localPosition, -delta, 1);
        }
      }
    });
  }

  Timer? _autopanTimer;
  Offset? _autopanPosition;
  VoidCallback? _autopanUpdate;
  void _stopAutopan() {
    _autopanTimer?.cancel();
    _autopanTimer = null;
    _autopanUpdate = null;
  }

  void _trackAutopan(Offset localPosition, VoidCallback update) {
    _autopanPosition = localPosition;
    _autopanUpdate = update;
    _autopanTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final point = _autopanPosition, size = _size;
      if (!mounted ||
          point == null ||
          size == null ||
          !(Offset.zero & size).contains(point)) {
        _stopAutopan();
        return;
      }
      double speed(double value, double extent) => value < 40
          ? (40 - value) / 40 * 10
          : value > extent - 40
          ? -(value - extent + 40) / 40 * 10
          : 0;
      final dx = speed(point.dx, size.width), dy = speed(point.dy, size.height);
      if (dx != 0 || dy != 0) {
        _moveCamera(Offset.zero, Offset(dx, dy), 1);
        _autopanUpdate?.call();
      }
    });
  }

  Map<String, dynamic>? _frame;
  Size? _size;
  final _sceneCache = LayoutSceneCache();
  final _nativeText = LayoutNativeTextCache();
  final _nativeFonts = <String, TextStyle>{};
  final _nativeFontLoads = <String>{};
  final _nativeFontErrors = <String>{};
  Set<String> _activeNativeFontKeys = {};
  String _nativeFontKey(LayoutNode node) {
    final label = resolveNodeAppearance(widget.document, node).label;
    final family =
        (widget.resources['fontFamilies'] as Map?)?[label['fontFamilyId']]
            as Map?;
    final face =
        (family?['faces']
            as Map?)?['${label['weight']}:${label['italic'] == true ? 'italic' : 'normal'}'];
    return '${label['fontFamilyId']}:${label['weight']}:${label['italic']}:$face';
  }

  bool _usesNativeText(LayoutNode node) {
    if (const {'seat', 'group', 'image', 'vector'}.contains(node.kind) ||
        isCouchNode(node) ||
        isBarNode(node)) {
      return false;
    }
    final text = node.kind == 'text'
        ? '${node.properties['text'] ?? ''}'
        : '${(widget.presentation[node.id] as Map?)?['label'] ?? node.label}';
    return text.isNotEmpty;
  }

  void _loadNativeFonts() {
    final nodes = widget.document.nodes.where(_usesNativeText).toList();
    final active = nodes.map(_nativeFontKey).toSet();
    for (final key in _nativeFontErrors.difference(active)) {
      _nativeFontLoads.remove(key);
      _nativeFontErrors.remove(key);
    }
    _activeNativeFontKeys = active;
    for (final node in nodes) {
      final key = _nativeFontKey(node);
      if (!_nativeFontLoads.add(key)) continue;
      widget.inlineTextStyleBuilder!(node)
          .then((style) {
            if (mounted) {
              setState(() {
                _nativeFonts[key] = style;
                _nativeFontErrors.remove(key);
              });
            }
          })
          .catchError((Object error) {
            if (!mounted) return;
            // A late failure from a dismissed font preview must not poison the
            // current face. Returning to that face starts a fresh request.
            if (_activeNativeFontKeys.contains(key)) {
              setState(() => _nativeFontErrors.add(key));
            } else {
              _nativeFontLoads.remove(key);
            }
          });
    }
  }

  void _retryNativeFonts() => setState(() {
    final failed = _nativeFontErrors.intersection(_activeNativeFontKeys);
    _nativeFontLoads.removeAll(failed);
    _nativeFontErrors.removeAll(failed);
  });

  final _textPreviewCache = LayoutTextPreviewCache();
  Map<String, dynamic>? _scene;

  @override
  void dispose() {
    _nativeText.dispose();
    _stopAutopan();
    _stopContextMenu();
    _motion.dispose();
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      _frame ??= Map<String, dynamic>.from(widget.document.canvas);
      final frame = _frame!;
      final width = (frame['width'] as num? ?? 2400).toDouble();
      final height = (frame['height'] as num? ?? 1600).toDouble();
      final x = (frame['x'] as num? ?? 0).toDouble();
      final y = (frame['y'] as num? ?? 0).toDouble();
      Offset? previousCenter;
      double? previousWorldZoom;
      final previousSize = _size;
      if (previousSize != null && previousSize != size) {
        final previousScale = math
            .min(
              (previousSize.width - 32) / width,
              (previousSize.height - 32) / height,
            )
            .clamp(.00001, 100.0);
        final previousOffset = Offset(
          (previousSize.width - width * previousScale) / 2,
          (previousSize.height - height * previousScale) / 2,
        );
        previousCenter =
            (_camera.toScene(previousSize.center(Offset.zero)) -
                    previousOffset) /
                previousScale +
            Offset(x, y);
        previousWorldZoom = previousScale * _cameraScale(_camera.value);
      }
      _size = size;
      final scale = math
          .min((size.width - 32) / width, (size.height - 32) / height)
          .clamp(.00001, 100.0);
      final offset = Offset(
        (size.width - width * scale) / 2,
        (size.height - height * scale) / 2,
      );
      final canvas = widget.document.canvas;
      _cameraCanvas = Rect.fromLTWH(
        offset.dx + ((canvas['x'] as num? ?? 0) - x) * scale,
        offset.dy + ((canvas['y'] as num? ?? 0) - y) * scale,
        (canvas['width'] as num).toDouble() * scale,
        (canvas['height'] as num).toDouble() * scale,
      );
      if (previousCenter != null) {
        final fit = _fitCameraZoom;
        final zoom = (previousWorldZoom! / scale).clamp(
          fit * (widget.compactZoomControls ? 1 : .9),
          fit * (widget.compactZoomControls ? 5 : 20),
        );
        final at = (previousCenter - Offset(x, y)) * scale + offset;
        _camera.value = _boundCamera(
          Matrix4.diagonal3Values(zoom, zoom, 1)..setTranslationRaw(
            size.width / 2 - at.dx * zoom,
            size.height / 2 - at.dy * zoom,
            0,
          ),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onViewportScaleChanged?.call(
            scale * _cameraScale(_camera.value),
          );
        }
      });
      Offset world(Offset p) {
        widget.onViewportScaleChanged?.call(
          scale * _cameraScale(_camera.value),
        );
        return (_camera.toScene(p) - offset) / scale + Offset(x, y);
      }

      final presentation = !widget.showSeatSelectionChecks
          ? {
              ...widget.presentation,
              for (final node in widget.document.nodes)
                if (node.kind == 'seat' &&
                    (widget.presentation[node.id] as Map?)?['selected'] == true)
                  node.id: {
                    ...widget.presentation[node.id] as Map,
                    'selected': false,
                  },
            }
          : widget.onSelectDown == null
          ? widget.presentation
          : {
              ...widget.presentation,
              for (final node in widget.document.nodes)
                if (node.kind == 'seat' && widget.selected.contains(node.id))
                  node.id: {
                    ...?widget.presentation[node.id] as Map?,
                    'selected': true,
                    'fill': layoutSelectedSeatFill,
                  },
            };
      _scene = _textPreviewCache.update(
        _sceneCache.update(
          widget.document,
          resources: widget.resources,
          presentation: presentation,
        ),
        widget.document,
        enabled: widget.retainPendingTextPreview,
      );
      final nativeEditing =
          widget.retainPendingTextPreview &&
          widget.inlineTextStyleBuilder != null;
      if (nativeEditing) {
        _loadNativeFonts();
        _scene = _nativeText.update(
          _scene!,
          widget.document,
          _nativeFonts,
          _nativeFontKey,
          presentation: presentation,
        );
      }
      final fontFailed =
          nativeEditing &&
          _nativeFontErrors.intersection(_activeNativeFontKeys).isNotEmpty;
      if (fontFailed) {
        _scene = {
          ..._scene!,
          'issues': [
            ..._scene!['issues'] as List,
            {'reason': 'Font unavailable'},
          ],
        };
      }
      final scene = _scene!;
      final issues = scene['issues'] as List? ?? const [];
      final textWaiting =
          widget.retainPendingTextPreview &&
          issues.isNotEmpty &&
          issues.every(
            (issue) => const {
              'text_layout_unavailable',
              'font_family_unavailable',
              'font_face_unavailable',
            }.contains(issue['reason']),
          );
      Offset globalWorld(Offset p) =>
          world((context.findRenderObject()! as RenderBox).globalToLocal(p));
      void dragAt(Offset global, [String? kind]) {
        void update() {
          if (kind == null) {
            widget.onDragUpdate?.call(globalWorld(global));
          } else {
            widget.onDropPreview?.call(kind, globalWorld(global));
          }
        }

        update();
        _trackAutopan(
          (context.findRenderObject()! as RenderBox).globalToLocal(global),
          update,
        );
      }

      final selectedNodes = widget.document.nodes
          .where((node) => widget.selected.contains(node.id))
          .map((node) => tabletopSelectionNode(widget.document, node))
          .toList();
      final resizeSelection = selectedNodes.firstOrNull;
      final edgeSelection = _edgeHandleNode == null
          ? selectedNodes
          : [_edgeHandleNode!];
      final resizeBounds = resizeSelection?.kind == 'group'
          ? selectionBounds(widget.document, {resizeSelection!.id})
          : {
              'width': resizeSelection?.width ?? 0.0,
              'height': resizeSelection?.height ?? 0.0,
            };

      Widget handle(
        String mode,
        List<double> at,
        IconData icon, {
        Offset screenOffset = Offset.zero,
        MouseCursor cursor = SystemMouseCursors.precise,
      }) => AnimatedBuilder(
        animation: _camera,
        builder: (context, _) {
          var screen =
              MatrixUtils.transformPoint(
                _camera.value,
                (Offset(at[0], at[1]) - Offset(x, y)) * scale + offset,
              ) +
              screenOffset;
          final rotation = mode == 'Rotate';
          final insert =
              mode.startsWith('Insert vertex ') ||
              mode.startsWith('Extend edge ');
          final amplitude = mode == 'Zigzag amplitude';
          final label = mode.startsWith('Zigzag endpoint ')
              ? 'Line endpoint handle'
              : amplitude
              ? 'Zigzag height handle'
              : insert
              ? (mode.startsWith('Extend edge ')
                    ? 'Extend surface'
                    : 'Add bend')
              : '$mode handle';
          // Keep a draggable body between handles when the plan is fitted to
          // a tall hall. Fixed 24px edge targets can cover the entire tabletop.
          final target = mode.startsWith('Resize')
              ? (math.min(resizeBounds['width']!, resizeBounds['height']!) *
                        scale *
                        _cameraScale(_camera.value) /
                        3)
                    .clamp(10.0, 24.0)
              : 24.0;
          // Keep group controls outside the chairs on the selection boundary.
          if (mode.startsWith('Resize') &&
              resizeSelection?.kind == 'group' &&
              resizeSelection!.assembly?['kind'] == null) {
            final direction = mode == 'Resize' ? 'se' : mode.substring(7);
            final outset = target / 2 + 2;
            screen += Offset(
              direction.contains('w')
                  ? -outset
                  : direction.contains('e')
                  ? outset
                  : 0,
              direction.contains('n')
                  ? -outset
                  : direction.contains('s')
                  ? outset
                  : 0,
            );
          }
          return Positioned(
            key: ValueKey('layout-handle-$mode'),
            left: screen.dx - target / 2,
            top: screen.dy - target / 2,
            child: Semantics(
              button: true,
              label: VenueLayoutStrings.text(context, label),
              child: Tooltip(
                message: VenueLayoutStrings.text(context, label),
                child: MouseRegion(
                  cursor: cursor,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (e) {
                      if (mode.startsWith('Extend edge ')) {
                        _edgeHandleDocument = widget.document;
                        _edgeHandleNode = selectedNodes.single;
                      }
                      widget.onHandleStart?.call(
                        mode,
                        globalWorld(e.globalPosition),
                      );
                    },
                    onPanUpdate: (e) => dragAt(e.globalPosition),
                    onPanEnd: (_) {
                      _stopAutopan();
                      widget.onDragEnd?.call();
                      if (_edgeHandleNode != null) {
                        setState(() {
                          _edgeHandleNode = null;
                          _edgeHandleDocument = null;
                        });
                      }
                    },
                    onPanCancel: () {
                      _stopAutopan();
                      widget.onDragCancel?.call();
                      if (_edgeHandleNode != null) {
                        setState(() {
                          _edgeHandleNode = null;
                          _edgeHandleDocument = null;
                        });
                      }
                    },
                    child: SizedBox(
                      width: target,
                      height: target,
                      child: Center(
                        child: Container(
                          width: rotation ? 12 : 10,
                          height: rotation ? 12 : 10,
                          decoration: BoxDecoration(
                            color: rotation || insert || amplitude
                                ? Theme.of(context).colorScheme.surface
                                : Theme.of(context).colorScheme.primary,
                            shape: rotation || insert || amplitude
                                ? BoxShape.circle
                                : BoxShape.rectangle,
                            border: rotation || insert || amplitude
                                ? Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    width: 1.5,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
      bool unlocked(LayoutNode node) {
        final byId = {for (final n in widget.document.nodes) n.id: n};
        LayoutNode? current = node;
        while (current != null) {
          if (current.locked) return false;
          current = byId[current.parentId];
        }
        return true;
      }

      MouseCursor resizeCursor(LayoutNode node, double sx, double sy) {
        final matrix = worldMatrix(widget.document, node);
        final angle = math.atan2(
          matrix[1] * sx + matrix[3] * sy,
          matrix[0] * sx + matrix[2] * sy,
        );
        final axis = ((angle / (math.pi / 4)).round() % 4 + 4) % 4;
        return [
          SystemMouseCursors.resizeLeftRight,
          SystemMouseCursors.resizeUpLeftDownRight,
          SystemMouseCursors.resizeUpDown,
          SystemMouseCursors.resizeUpRightDownLeft,
        ][axis];
      }

      Widget inlineEditor(LayoutNode node) => AnimatedBuilder(
        animation: _camera,
        builder: (context, _) {
          final matrix = worldMatrix(widget.document, node);
          final fontSize =
              (node.properties['size'] as num? ??
                      (node.kind == 'text' ? 24 : 16))
                  .toDouble();
          final zoom = scale * _cameraScale(_camera.value);
          final width =
              math.max(24.0, node.width - (node.kind == 'text' ? 0 : 12)) *
              zoom;
          final height =
              (node.kind == 'text'
                  ? math.max(fontSize * 1.6, node.height)
                  : math.min(node.height, fontSize * 1.8)) *
              zoom;
          final center = MatrixUtils.transformPoint(
            _camera.value,
            (Offset(matrix[4], matrix[5]) - Offset(x, y)) * scale + offset,
          );
          final angle =
              math.atan2(matrix[1], matrix[0]) +
              math.atan2(_camera.value.entry(1, 0), _camera.value.entry(0, 0));
          // Native text input lays out in viewport pixels. Only rotation needs
          // a paint transform; camera zoom never scales the editable subtree.
          Widget input(TextStyle? nativeStyle) => LayoutInlineLabel(
            key: ValueKey(node.id),
            value: node.kind == 'text'
                ? '${node.properties['text'] ?? node.label}'
                : node.label,
            style: TextStyle(
              fontFamily: nativeStyle?.fontFamily,
              fontSize: fontSize * zoom,
              color: LayoutScenePainter.color(
                node.properties['color'],
                const Color(0xff202830),
              ),
              fontWeight:
                  nativeStyle?.fontWeight ??
                  (node.properties['weight'] == 700
                      ? FontWeight.bold
                      : FontWeight.normal),
              fontStyle:
                  nativeStyle?.fontStyle ??
                  (node.properties['italic'] == true
                      ? FontStyle.italic
                      : FontStyle.normal),
              height: (node.properties['lineHeight'] as num?)?.toDouble(),
            ),
            textAlign:
                node.kind == 'text' && node.properties['align'] != 'center'
                ? (node.properties['align'] == 'right'
                      ? TextAlign.right
                      : TextAlign.left)
                : TextAlign.center,
            background: LayoutScenePainter.color(
              node.kind == 'text' ? '#FFFFFFFF' : node.properties['fill'],
              const Color(0xffe2e8f0),
            ),
            onSubmit: (value) => widget.onInlineSubmit?.call(value),
            onCancel: () => widget.onInlineCancel?.call(),
            onUndo: widget.onInlineUndo,
            onRedo: widget.onInlineRedo,
          );
          final editor = widget.inlineTextStyleBuilder == null
              ? input(null)
              : FutureBuilder<TextStyle>(
                  key: ValueKey(
                    '${node.id}:${node.properties['fontFamilyId']}:${node.properties['weight']}:${node.properties['italic']}',
                  ),
                  future: widget.inlineTextStyleBuilder!(widget.inlineNode!),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(
                        child: LayoutText('Font unavailable'),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return input(snapshot.data);
                  },
                );
          return Positioned(
            left: center.dx - width / 2,
            top: center.dy - height / 2,
            width: width,
            height: height,
            child: angle.abs() < 1e-10
                ? editor
                : Transform.rotate(angle: angle, child: editor),
          );
        },
      );
      final seatLinks = tableSeatLinks(
        widget.document,
        widget.showSeatSelectionChecks
            ? widget.selected
            : selectedNodes.map((node) => node.id).toSet(),
      );
      Map<String, double> localBounds(LayoutNode node) {
        if (node.assembly?['kind'] != 'rows') {
          return {
            'x': -node.width / 2,
            'y': -node.height / 2,
            'width': node.width,
            'height': node.height,
          };
        }
        return rowAssemblyBounds(widget.document, node.id);
      }

      final handleBounds = {
        for (final node in selectedNodes) node.id: localBounds(node),
      };
      List<double> handlePoint(LayoutNode node, double dx, double dy) {
        if ((node.kind == 'group' && node.assembly?['kind'] == null) ||
            const ['bus', 'compartments'].contains(node.assembly?['kind'])) {
          final b = selectionBounds(widget.document, {node.id});
          return [
            b['x']! + b['width']! * (dx + 1) / 2,
            b['y']! + b['height']! * (dy + 1) / 2,
          ];
        }
        final b = handleBounds[node.id]!;
        return transformPoint(
          worldMatrix(widget.document, node),
          b['x']! + b['width']! * (dx + 1) / 2,
          b['y']! + b['height']! * (dy + 1) / 2,
        );
      }

      Offset rotationOutset(LayoutNode node) {
        if (node.kind == 'group') return const Offset(0, -24);
        final m = worldMatrix(widget.document, node);
        final normal =
            MatrixUtils.transformPoint(_camera.value, Offset(-m[2], -m[3])) -
            MatrixUtils.transformPoint(_camera.value, Offset.zero);
        return normal.distance < 1e-9
            ? const Offset(0, -24)
            : normal / normal.distance * 24;
      }

      return Listener(
        onPointerSignal: _pointerSignal,
        onPointerCancel: (_) {
          _stopAutopan();
          _interactionDragging = false;
          widget.onDragCancel?.call();
        },
        child: DragTarget<String>(
          onWillAcceptWithDetails: (_) => widget.onDrop != null,
          onMove: (details) => dragAt(details.offset, details.data),
          onAcceptWithDetails: (details) {
            _stopAutopan();
            widget.onDrop?.call(details.data, globalWorld(details.offset));
          },
          onLeave: (_) {
            _stopAutopan();
            widget.onDropCancel?.call();
          },
          builder: (context, candidate, rejected) => Stack(
            children: [
              if (_hoverMessage != null && _hoverMessage!.isNotEmpty)
                Positioned(
                  left: _hoverPosition.dx,
                  top: _hoverPosition.dy,
                  child: IgnorePointer(
                    child: Tooltip(
                      key: _hoverTooltipKey,
                      message: _hoverMessage!,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh.withAlpha(255),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                      triggerMode: TooltipTriggerMode.manual,
                      child: const SizedBox(width: 1, height: 1),
                    ),
                  ),
                ),
              Positioned.fill(
                key: const ValueKey('layout-map-gesture-surface'),
                child: ClipRect(
                  child: MouseRegion(
                    onExit: (_) => _hideHoverTooltip(clearNode: true),
                    cursor:
                        widget.compactZoomControls ||
                            (widget.onSelectDown != null &&
                                widget.onDragStart == null)
                        ? _pickerCursor
                        : widget.onPointTap != null
                        ? SystemMouseCursors.precise
                        : widget.pan
                        ? SystemMouseCursors.grab
                        : SystemMouseCursors.basic,
                    child: GestureDetector(
                      // The secondary-click recognizer otherwise advertises a
                      // primary semantic tap with no handler. Web semantics
                      // consumes coordinate clicks before selection sees them.
                      // Object actions remain available through the inspector.
                      excludeFromSemantics: true,
                      behavior: HitTestBehavior.opaque,
                      onSecondaryTapUp: widget.onContextMenu == null
                          ? null
                          : (details) => widget.onContextMenu!(
                              globalWorld(details.globalPosition),
                              details.globalPosition,
                            ),
                      onLongPressStart: widget.onContextMenu == null
                          ? null
                          : (details) {
                              _pointTapDown = null;
                              widget.onContextMenu!(
                                globalWorld(details.globalPosition),
                                details.globalPosition,
                              );
                            },
                      onScaleStart: (details) {
                        _gestureScale = 1;
                        if (_touchPanning && !_twoFinger) {
                          widget.onDragCancel?.call();
                        }
                        if (!widget.pan &&
                            !_twoFinger &&
                            !_touchPanning &&
                            details.pointerCount == 1 &&
                            widget.onDragStart != null) {
                          _interactionDragging = true;
                          widget.onDragStart!(
                            globalWorld(_dragPointerDown ?? details.focalPoint),
                          );
                        }
                      },
                      onScaleUpdate: (details) {
                        if (details.pointerCount != 1) {
                          _endMarginPan();
                          if (_interactionDragging) {
                            _stopAutopan();
                            widget.onDragCancel?.call();
                            _interactionDragging = false;
                          }
                          _twoFinger = true;
                        }
                        // Empty margins own their single-finger movement at
                        // the pointer boundary, including when a host gesture
                        // recognizer wins the arena. Do not apply it twice.
                        if (_marginPanPointer != null &&
                            details.pointerCount == 1) {
                          _gestureScale = details.scale;
                          return;
                        }
                        if (widget.pan || _touchPanning || _twoFinger) {
                          _moveCamera(
                            details.localFocalPoint,
                            details.focalPointDelta,
                            details.scale / _gestureScale,
                          );
                        } else if (_interactionDragging) {
                          dragAt(details.focalPoint);
                        }
                        _gestureScale = details.scale;
                      },
                      onScaleEnd: (_) {
                        _stopAutopan();
                        if (_interactionDragging) widget.onDragEnd?.call();
                        _interactionDragging = false;
                        // Navigation owns the full 1-2-1 pointer sequence.
                        // Reset only when the next independent pointer arrives.
                      },
                      child: GestureDetector(
                        // A semantic tap synthesizes the center, losing the
                        // coordinate needed to place or select an object.
                        excludeFromSemantics: true,
                        behavior: HitTestBehavior.opaque,
                        onDoubleTapDown: widget.onDoubleTapAt == null
                            ? null
                            : (e) => _doubleTapPosition = globalWorld(
                                e.globalPosition,
                              ),
                        onDoubleTap: widget.onDoubleTapAt == null
                            ? widget.onDoubleTap
                            : () {
                                if (_doubleTapPosition != null) {
                                  widget.onDoubleTapAt!(_doubleTapPosition!);
                                }
                              },
                        onTapUp: widget.onTap == null
                            ? null
                            : (e) {
                                if (!_twoFinger) {
                                  widget.onTap!(globalWorld(e.globalPosition));
                                }
                              },
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (event) {
                            _hideHoverTooltip();
                            if (event.buttons != kPrimaryButton) return;
                            if (_touchPointers.isEmpty) {
                              _endMarginPan();
                              _twoFinger = false;
                              _touchPanning = false;
                            }
                            _touchPointers.add(event.pointer);
                            if (_touchPointers.length > 1) {
                              _endMarginPan();
                              _twoFinger = true;
                              _pointTapDown = null;
                              _dragPointerDown = null;
                              _stopAutopan();
                              widget.onDragCancel?.call();
                              _interactionDragging = false;
                              return;
                            }
                            if (_dragPointerDown == null) {
                              final world = globalWorld(event.position);
                              _touchPanning =
                                  widget.touchPanOnEmpty &&
                                  event.kind == PointerDeviceKind.touch &&
                                  (widget.panOnTouchDown?.call(world) ??
                                      (hitTest(
                                            widget.document,
                                            world.dx,
                                            world.dy,
                                            tolerance: 0,
                                          ) ==
                                          null));
                              final bounds = _cameraCanvas;
                              if (event.kind == PointerDeviceKind.touch &&
                                  widget.pan &&
                                  bounds != null &&
                                  !bounds.contains(
                                    _camera.toScene(event.localPosition),
                                  )) {
                                _marginPanPointer = event.pointer;
                                _marginPanDown = _marginPanLast =
                                    event.localPosition;
                              }
                              _dragPointerDown = event.position;
                            }
                            _pointTapDown = widget.onPointTap == null
                                ? null
                                : event.position;
                            widget.onSelectDown?.call(
                              globalWorld(event.position),
                            );
                          },
                          onPointerHover: (event) {
                            final world = globalWorld(event.position);
                            _showHoverTooltip(event.position, world);
                            widget.onHover?.call(world);
                          },
                          onPointerMove: (event) {
                            if (_marginPanPointer == event.pointer) {
                              if (!_marginPanActive &&
                                  (event.localPosition - _marginPanDown!)
                                          .distance >
                                      kTouchSlop) {
                                _marginPanActive = true;
                              }
                              if (_marginPanActive) {
                                _moveCamera(
                                  event.localPosition,
                                  event.localPosition - _marginPanLast!,
                                  1,
                                );
                                _marginPanLast = event.localPosition;
                              }
                            }
                            if (_pointTapDown != null &&
                                (event.position - _pointTapDown!).distance >
                                    kTouchSlop) {
                              _pointTapDown = null;
                            }
                          },
                          onPointerCancel: (event) {
                            if (_marginPanPointer == event.pointer) {
                              _endMarginPan();
                            }
                            _touchPointers.remove(event.pointer);
                            _pointTapDown = null;
                            _dragPointerDown = null;
                          },
                          onPointerUp: (event) {
                            if (_marginPanPointer == event.pointer) {
                              _endMarginPan();
                            }
                            _touchPointers.remove(event.pointer);
                            _dragPointerDown = null;
                            final down = _pointTapDown;
                            _pointTapDown = null;
                            if (down != null) {
                              widget.onPointTap?.call(
                                globalWorld(event.position),
                              );
                            }
                          },
                          child: CustomPaint(
                            size: size,
                            painter: LayoutScenePainter(
                              scene: scene,
                              camera: _camera,
                              motion: _motion,
                              fromScene: _motionFrom,
                              resources: widget.resources,
                              selected: widget.selected,
                              seatLinks: seatLinks,
                              snapGuides: widget.snapGuides,
                              showGrid: widget.showGrid,
                              gridStep: widget.gridStep,
                              gridOrigin: widget.gridOrigin,
                              transientForegroundIds:
                                  widget.transientForegroundIds,
                              blockedPlacementHulls:
                                  widget.blockedPlacementHulls,
                              warningHulls: [
                                for (final node in widget.document.nodes)
                                  if (widget.warningIds.contains(node.id))
                                    (() {
                                      final b = selectionBounds(
                                        widget.document,
                                        {node.id},
                                      );
                                      return <List<double>>[
                                        [b['x']!, b['y']!],
                                        [b['x']! + b['width']!, b['y']!],
                                        [
                                          b['x']! + b['width']!,
                                          b['y']! + b['height']!,
                                        ],
                                        [b['x']!, b['y']! + b['height']!],
                                      ];
                                    })(),
                              ],
                              // Strong selection bounds are independent of the
                              // commercial check marker presentation.
                              emphasizeSelection: true,
                              selectionHulls: [
                                if (widget.backgroundSelected)
                                  backgroundHull(widget.document),
                                for (final node in widget.document.nodes.where(
                                  (n) => widget.highlightedIds.contains(n.id),
                                ))
                                  worldHull(
                                    node,
                                    worldMatrix(widget.document, node),
                                  ),
                                if (widget.canvasSelected)
                                  (() {
                                    final c = widget.document.canvas;
                                    final l = (c['x'] as num).toDouble(),
                                        t = (c['y'] as num).toDouble(),
                                        r = l + (c['width'] as num),
                                        b = t + (c['height'] as num);
                                    return <List<double>>[
                                      [l, t],
                                      [r, t],
                                      [r, b],
                                      [l, b],
                                    ];
                                  })(),
                                for (final node in selectedNodes.where(
                                  (node) =>
                                      node.kind != 'seat' ||
                                      !widget.showSeatSelectionChecks,
                                ))
                                  if (node.kind == 'group')
                                    (() {
                                      final b = selectionBounds(
                                        widget.document,
                                        {node.id},
                                      );
                                      return <List<double>>[
                                        [b['x']!, b['y']!],
                                        [b['x']! + b['width']!, b['y']!],
                                        [
                                          b['x']! + b['width']!,
                                          b['y']! + b['height']!,
                                        ],
                                        [b['x']!, b['y']! + b['height']!],
                                      ];
                                    })()
                                  else
                                    [
                                      for (final corner in <List<double>>[
                                        [-node.width / 2, -node.height / 2],
                                        [node.width / 2, -node.height / 2],
                                        [node.width / 2, node.height / 2],
                                        [-node.width / 2, node.height / 2],
                                      ])
                                        transformPoint(
                                          worldMatrix(widget.document, node),
                                          corner[0],
                                          corner[1],
                                        ),
                                    ],
                              ],
                              scale: scale,
                              offset: offset - Offset(x, y) * scale,
                              canvasColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              selectionColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.marquee != null)
                AnimatedBuilder(
                  animation: _camera,
                  builder: (context, _) {
                    Offset screen(Offset p) => MatrixUtils.transformPoint(
                      _camera.value,
                      (p - Offset(x, y)) * scale + offset,
                    );
                    return Positioned.fromRect(
                      rect: Rect.fromPoints(
                        screen(widget.marquee!.topLeft),
                        screen(widget.marquee!.bottomRight),
                      ),
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: .1),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              for (final point in widget.pathPoints)
                AnimatedBuilder(
                  animation: _camera,
                  builder: (context, _) {
                    final at = MatrixUtils.transformPoint(
                      _camera.value,
                      (point - Offset(x, y)) * scale + offset,
                    );
                    return Positioned(
                      left: at.dx - 4,
                      top: at.dy - 4,
                      child: IgnorePointer(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              if (widget.canvasSelected && widget.onHandleStart != null)
                for (final direction in <String, List<double>>{
                  'n': [.5, 0],
                  'e': [1, .5],
                  's': [.5, 1],
                  'w': [0, .5],
                  'nw': [0, 0],
                  'ne': [1, 0],
                  'sw': [0, 1],
                  'se': [1, 1],
                }.entries)
                  handle(
                    'Canvas resize ${direction.key}',
                    [
                      (widget.document.canvas['x'] as num).toDouble() +
                          (widget.document.canvas['width'] as num) *
                              direction.value[0],
                      (widget.document.canvas['y'] as num).toDouble() +
                          (widget.document.canvas['height'] as num) *
                              direction.value[1],
                    ],
                    Icons.open_in_full,
                    cursor: direction.key == 'n' || direction.key == 's'
                        ? SystemMouseCursors.resizeUpDown
                        : direction.key == 'e' || direction.key == 'w'
                        ? SystemMouseCursors.resizeLeftRight
                        : direction.key == 'nw' || direction.key == 'se'
                        ? SystemMouseCursors.resizeUpLeftDownRight
                        : SystemMouseCursors.resizeUpRightDownLeft,
                  ),
              if (widget.onHandleStart != null &&
                  selectedNodes.length > 1 &&
                  selectedNodes.every(unlocked))
                handle(
                  'Rotate',
                  [
                    selectionBounds(widget.document, widget.selected)['x']! +
                        selectionBounds(
                              widget.document,
                              widget.selected,
                            )['width']! /
                            2,
                    selectionBounds(widget.document, widget.selected)['y']!,
                  ],
                  Icons.rotate_right,
                  screenOffset: const Offset(0, -24),
                  cursor: SystemMouseCursors.grab,
                ),
              if (widget.onHandleStart != null &&
                  selectedNodes.length == 1 &&
                  (selectedNodes.single.kind != 'seat' ||
                      !widget.showSeatSelectionChecks) &&
                  unlocked(selectedNodes.single)) ...[
                // Edge targets precede corner targets so corners win overlaps.
                if (!const [
                      'line',
                      'polyline',
                      'arrow',
                    ].contains(selectedNodes.single.properties['shape']) &&
                    !const [
                      'bus',
                      'compartments',
                    ].contains(selectedNodes.single.assembly?['kind']))
                  for (final direction in <String, List<double>>{
                    'n': [0, -1],
                    'e': [1, 0],
                    's': [0, 1],
                    'w': [-1, 0],
                    'nw': [-1, -1],
                    'ne': [1, -1],
                    'sw': [-1, 1],
                    'se': [1, 1],
                  }.entries)
                    handle(
                      direction.key == 'se'
                          ? 'Resize'
                          : 'Resize ${direction.key}',
                      handlePoint(
                        selectedNodes.single,
                        direction.value[0],
                        direction.value[1],
                      ),
                      Icons.open_in_full,
                      cursor: resizeCursor(
                        selectedNodes.single,
                        direction.value[0],
                        direction.value[1],
                      ),
                    ),
                handle(
                  'Rotate',
                  handlePoint(selectedNodes.single, 0, -1),
                  Icons.rotate_right,
                  screenOffset: rotationOutset(selectedNodes.single),
                  cursor: SystemMouseCursors.grab,
                ),
                if ((edgeSelection.single.kind == 'table'
                        ? _orthogonalSurface(edgeSelection.single)
                        : widget.selected.contains(edgeSelection.single.id)) &&
                    !isZigzagNode(edgeSelection.single) &&
                    (edgeSelection.single.kind == 'table' ||
                        const [
                          'polyline',
                          'polygon',
                        ].contains(edgeSelection.single.properties['shape'])) &&
                    _vertexPoints(edgeSelection.single) != null)
                  for (
                    var i = 0;
                    i <
                        _vertexPoints(edgeSelection.single)!.length -
                            (edgeSelection.single.kind == 'table' ||
                                    edgeSelection.single.properties['shape'] ==
                                        'polygon'
                                ? 0
                                : 1);
                    i++
                  )
                    for (
                      var cell = 0;
                      cell <
                          (edgeSelection.single.kind == 'table'
                              ? (() {
                                  final points = _vertexPoints(
                                    edgeSelection.single,
                                  )!;
                                  final a = points[i],
                                      b = points[(i + 1) % points.length];
                                  final step =
                                      (edgeSelection
                                                  .single
                                                  .surface!['moduleSize']
                                              as num)
                                          .toDouble();
                                  return ((a[0] - b[0]).abs() +
                                          (a[1] - b[1]).abs()) ~/
                                      step;
                                })()
                              : 1);
                      cell++
                    )
                      handle(
                        edgeSelection.single.kind == 'table'
                            ? 'Extend edge $i cell $cell'
                            : 'Insert vertex $i',
                        (() {
                          final points = _vertexPoints(edgeSelection.single)!;
                          final a = points[i],
                              b = points[(i + 1) % points.length];
                          final step = edgeSelection.single.kind == 'table'
                              ? (edgeSelection.single.surface!['moduleSize']
                                        as num)
                                    .toDouble()
                              : 1.0;
                          final length =
                              (a[0] - b[0]).abs() + (a[1] - b[1]).abs();
                          final t = edgeSelection.single.kind == 'table'
                              ? (cell + .5) * step / length
                              : .5;
                          return transformPoint(
                            worldMatrix(
                              _edgeHandleDocument ?? widget.document,
                              edgeSelection.single,
                            ),
                            a[0] + (b[0] - a[0]) * t,
                            a[1] + (b[1] - a[1]) * t,
                          );
                        })(),
                        Icons.add,
                        cursor: SystemMouseCursors.precise,
                      ),
                if (widget.selected.contains(selectedNodes.single.id) &&
                    selectedNodes.single.kind != 'table' &&
                    !isZigzagNode(selectedNodes.single) &&
                    _vertexPoints(selectedNodes.single) != null)
                  for (
                    var i = 0;
                    i < _vertexPoints(selectedNodes.single)!.length;
                    i++
                  )
                    handle(
                      'Vertex $i',
                      transformPoint(
                        worldMatrix(widget.document, selectedNodes.single),
                        _vertexPoints(selectedNodes.single)![i][0],
                        _vertexPoints(selectedNodes.single)![i][1],
                      ),
                      Icons.circle_outlined,
                    ),
                if (isZigzagNode(selectedNodes.single)) ...[
                  for (final index in [
                    0,
                    _vertexPoints(selectedNodes.single)!.length - 1,
                  ])
                    handle(
                      'Zigzag endpoint $index',
                      transformPoint(
                        worldMatrix(widget.document, selectedNodes.single),
                        _vertexPoints(selectedNodes.single)![index][0],
                        _vertexPoints(selectedNodes.single)![index][1],
                      ),
                      Icons.circle_outlined,
                    ),
                  handle(
                    'Zigzag amplitude',
                    (() {
                      final node = selectedNodes.single;
                      final points = _vertexPoints(node)!;
                      final first = points.first, last = points.last;
                      final dx = last[0] - first[0], dy = last[1] - first[1];
                      final length = math.sqrt(dx * dx + dy * dy);
                      final height = (node.properties['zigzagAmplitude'] as num)
                          .toDouble();
                      final nx = length > 0 ? -dy / length : 0.0;
                      final ny = length > 0 ? dx / length : 1.0;
                      return transformPoint(
                        worldMatrix(widget.document, node),
                        (first[0] + last[0]) / 2 + nx * height,
                        (first[1] + last[1]) / 2 + ny * height,
                      );
                    })(),
                    Icons.height,
                  ),
                ],
              ],
              if (widget.inlineNode != null)
                inlineEditor(
                  widget.inlineNode!.copyWith(
                    properties: effectiveNodeProperties(
                      widget.document,
                      widget.inlineNode!,
                    ),
                  ),
                ),
              if (widget.showControls)
                Positioned(
                  right: widget.compactZoomControls ? 16 : 8,
                  bottom: widget.compactZoomControls ? 16 : 8,
                  child: widget.compactZoomControls
                      ? AnimatedBuilder(
                          animation: _camera,
                          builder: (context, _) {
                            final zoom = _cameraScale(_camera.value),
                                fit = _fitCameraZoom;
                            Widget button(
                              String label,
                              IconData icon,
                              VoidCallback? action,
                            ) => SizedBox(
                              width: 44,
                              height: 44,
                              child: IconButton(
                                tooltip: VenueLayoutStrings.text(
                                  context,
                                  label,
                                ),
                                iconSize: 20,
                                padding: EdgeInsets.zero,
                                onPressed: action,
                                icon: Icon(icon),
                              ),
                            );
                            return Material(
                              color: Theme.of(context).colorScheme.surface,
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    button(
                                      'Zoom in',
                                      Icons.add,
                                      zoom < fit * 5 - .001
                                          ? () => _moveCamera(
                                              Offset(
                                                size.width / 2,
                                                size.height / 2,
                                              ),
                                              Offset.zero,
                                              1.25,
                                            )
                                          : null,
                                    ),
                                    button(
                                      'Zoom out',
                                      Icons.remove,
                                      zoom > fit + .001
                                          ? () => _moveCamera(
                                              Offset(
                                                size.width / 2,
                                                size.height / 2,
                                              ),
                                              Offset.zero,
                                              1 / 1.25,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(
                                      width: 44,
                                      child: Divider(height: 3),
                                    ),
                                    button(
                                      'Fit plan',
                                      Icons.fullscreen,
                                      () => setState(() {
                                        _frame = null;
                                        _camera.value = Matrix4.identity();
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )
                      : size.width < 700
                      ? IconButton.filledTonal(
                          key: const ValueKey('layout-mobile-fit-plan'),
                          tooltip: VenueLayoutStrings.text(context, 'Fit plan'),
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          onPressed: () => setState(() {
                            _frame = null;
                            _camera.value = Matrix4.identity();
                          }),
                          icon: const Icon(Icons.fit_screen),
                        )
                      : FilledButton.tonalIcon(
                          onPressed: () => setState(() {
                            _frame = null;
                            _camera.value = Matrix4.identity();
                          }),
                          icon: const Icon(Icons.fit_screen),
                          label: const LayoutText('Fit plan'),
                        ),
                ),
              if (widget.showControls && issues.isNotEmpty)
                Positioned(
                  left: 8,
                  top: 8,
                  right: 8,
                  child: Material(
                    color: textWaiting
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: LayoutText(
                              fontFailed
                                  ? 'The selected font could not be loaded.'
                                  : textWaiting
                                  ? 'Text is not ready yet.'
                                  : 'Part of the plan could not be displayed.',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (fontFailed)
                            TextButton(
                              onPressed: _retryNativeFonts,
                              child: const LayoutText('Retry font'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class LayoutScenePainter extends CustomPainter {
  LayoutScenePainter({
    required this.scene,
    required this.resources,
    required this.selected,
    required this.scale,
    required this.offset,
    required this.canvasColor,
    required this.selectionColor,
    this.camera,
    this.showGrid = false,
    this.gridStep = 8,
    this.gridOrigin = Offset.zero,
    this.motion,
    this.fromScene,
    this.seatLinks = const [],
    this.selectionHulls = const [],
    this.emphasizeSelection = false,
    this.warningHulls = const [],
    this.blockedPlacementHulls = const [],
    this.snapGuides = const [],
    this.transientForegroundIds = const {},
  }) : super(repaint: Listenable.merge([camera, motion]));
  final Map<String, dynamic> scene, resources;
  final Set<String> selected;
  final List<TableSeatLink> seatLinks;
  final List<List<List<double>>> selectionHulls,
      warningHulls,
      blockedPlacementHulls;
  final List<Map<String, dynamic>> snapGuides;
  final Set<String> transientForegroundIds;
  final double scale;
  final bool showGrid;
  final bool emphasizeSelection;
  final double gridStep;
  final Offset gridOrigin;
  final Offset offset;
  final Color canvasColor, selectionColor;
  final TransformationController? camera;
  final Animation<double>? motion;
  final Map<String, dynamic>? fromScene;
  static final Expando<Path> _paths = Expando<Path>();
  static Color color(dynamic value, Color fallback) {
    if (value is! String) return fallback;
    final text = value.replaceFirst('#', '');
    final n = int.tryParse(text, radix: 16);
    if (n == null) return fallback;
    return text.length == 8
        ? Color(((n & 255) << 24) | (n >> 8))
        : Color(0xff000000 | n);
  }

  static Path path(List commands) => layoutPath(commands);

  @override
  void paint(Canvas canvas, Size size) {
    final display = fromScene != null && motion != null && motion!.value < 1
        ? interpolateScene(fromScene!, scene, motion!.value)
        : scene;
    if (camera != null) canvas.transform(camera!.value.storage);
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    final c = display['canvas'] as Map? ?? const {};
    double cv(String k, double fallback) =>
        (c[k] as num? ?? fallback).toDouble();
    canvas.drawRect(
      Rect.fromLTWH(
        cv('x', 0),
        cv('y', 0),
        cv('width', 2400),
        cv('height', 1600),
      ),
      Paint()..color = color(c['fill'] ?? c['color'], canvasColor),
    );
    final topLeft =
        ((camera?.toScene(Offset.zero) ?? Offset.zero) - offset) / scale;
    final bottomRight =
        ((camera?.toScene(Offset(size.width, size.height)) ??
                Offset(size.width, size.height)) -
            offset) /
        scale;
    final visible = cullScene(display, {
      'x': topLeft.dx,
      'y': topLeft.dy,
      'width': bottomRight.dx - topLeft.dx,
      'height': bottomRight.dy - topLeft.dy,
    }, zoom: scale * _cameraScale(camera?.value));
    // Raise complete assemblies for the gesture only, including their glyphs.
    bool foreground(dynamic item) =>
        transientForegroundIds.contains(item['nodeId'] ?? item['id']);
    final paintOrder = transientForegroundIds.isEmpty
        ? visible
        : [
            ...visible.where((item) => !foreground(item)),
            ...visible.where(foreground),
          ];
    var gridPainted = false;
    void paintGrid() {
      if (!showGrid) return;
      final zoom = scale * _cameraScale(camera?.value);
      final bounds = Rect.fromLTWH(
        cv('x', 0),
        cv('y', 0),
        cv('width', 2400),
        cv('height', 1600),
      ).intersect(Rect.fromPoints(topLeft, bottomRight));
      if (bounds.isEmpty) return;
      // Keep the selected lattice. Coarser multiples avoid dense
      // moire and cap work to the visible viewport when zoomed out.
      var step = gridStep;
      while (step * zoom < 12) {
        step *= 5;
      }
      final dark =
          color(c['fill'] ?? c['color'], canvasColor).computeLuminance() < .3;
      final minor = Paint()
        ..color = (dark ? Colors.white : const Color(0xff475569)).withValues(
          alpha: dark ? .18 : .14,
        )
        ..strokeWidth = .6 / zoom;
      final major = Paint()
        ..color = (dark ? Colors.white : const Color(0xff475569)).withValues(
          alpha: dark ? .3 : .26,
        )
        ..strokeWidth = .8 / zoom;
      canvas.save();
      canvas.clipRect(bounds);
      for (
        var x =
            gridOrigin.dx +
            ((bounds.left - gridOrigin.dx) / step).ceil() * step;
        x <= bounds.right;
        x += step
      ) {
        canvas.drawLine(
          Offset(x, bounds.top),
          Offset(x, bounds.bottom),
          ((x - gridOrigin.dx) / step).round() % 5 == 0 ? major : minor,
        );
      }
      for (
        var y =
            gridOrigin.dy + ((bounds.top - gridOrigin.dy) / step).ceil() * step;
        y <= bounds.bottom;
        y += step
      ) {
        canvas.drawLine(
          Offset(bounds.left, y),
          Offset(bounds.right, y),
          ((y - gridOrigin.dy) / step).round() % 5 == 0 ? major : minor,
        );
      }
      canvas.restore();
    }

    final relatedIds = seatLinks.map((link) => link.seatId).toSet();
    final zoom = scale * _cameraScale(camera?.value);
    for (final raw in paintOrder) {
      final item = raw as Map;
      if (!gridPainted &&
          item['id'] != 'background' &&
          item['kind'] != 'floor') {
        paintGrid();
        gridPainted = true;
      }
      if (item['kind'] == 'vectorRestore') {
        canvas.restore();
        continue;
      }
      if (item['kind'] == 'vectorLayer') {
        canvas.saveLayer(
          null,
          Paint()
            ..color = Colors.white.withValues(
              alpha: (item['opacity'] as num).toDouble(),
            ),
        );
        continue;
      }
      if (item['kind'] == 'vectorClip') {
        canvas.save();
        final m = item['matrix'] as List;
        final transform = Matrix4.identity()
          ..setEntry(0, 0, (m[0] as num).toDouble())
          ..setEntry(1, 0, (m[1] as num).toDouble())
          ..setEntry(0, 1, (m[2] as num).toDouble())
          ..setEntry(1, 1, (m[3] as num).toDouble())
          ..setEntry(0, 3, (m[4] as num).toDouble())
          ..setEntry(1, 3, (m[5] as num).toDouble());
        final p = path(item['path'] as List)
          ..fillType = item['fillRule'] == 'evenodd'
              ? PathFillType.evenOdd
              : PathFillType.nonZero;
        canvas.clipPath(p.transform(transform.storage));
        continue;
      }
      canvas.save();
      final clip = item['clip'] as Map?;
      if (clip != null) {
        canvas.clipRect(
          Rect.fromLTWH(
            (clip['x'] as num? ?? 0).toDouble(),
            (clip['y'] as num? ?? 0).toDouble(),
            (clip['width'] as num).toDouble(),
            (clip['height'] as num).toDouble(),
          ),
        );
      }
      Color itemColor(dynamic value) {
        final c = color(value, Colors.transparent);
        return c.withValues(
          alpha: c.a * (item['opacity'] as num? ?? 1).toDouble(),
        );
      }

      final m = item['matrix'] as List? ?? [1, 0, 0, 1, 0, 0];
      canvas.transform(
        Matrix4(
          (m[0] as num).toDouble(),
          (m[1] as num).toDouble(),
          0,
          0,
          (m[2] as num).toDouble(),
          (m[3] as num).toDouble(),
          0,
          0,
          0,
          0,
          1,
          0,
          (m[4] as num).toDouble(),
          (m[5] as num).toDouble(),
          0,
          1,
        ).storage,
      );
      final localClip = item['localClip'] as Map?;
      if (localClip != null) {
        canvas.clipRect(
          Rect.fromLTWH(
            (localClip['x'] as num).toDouble(),
            (localClip['y'] as num).toDouble(),
            (localClip['width'] as num).toDouble(),
            (localClip['height'] as num).toDouble(),
          ),
        );
      }
      if (item['kind'] == 'nativeText') {
        (item['nativeParagraph'] as TextPainter).paint(
          canvas,
          item['nativeOffset'] as Offset,
        );
        canvas.restore();
        continue;
      }
      ui.Shader? shader(Object? raw) {
        if (raw is! Map) return null;
        final colors = (raw['colors'] as List)
                .map((v) => itemColor(v))
                .toList(),
            stops = (raw['stops'] as List)
                .map((v) => (v as num).toDouble())
                .toList();
        Offset point(Object? v) => Offset(
          ((v as List)[0] as num).toDouble(),
          (v[1] as num).toDouble(),
        );
        final tile = switch (raw['spread']) {
          'repeat' => TileMode.repeated,
          'reflect' => TileMode.mirror,
          _ => TileMode.clamp,
        };
        if (raw['type'] == 'linear') {
          return ui.Gradient.linear(
            point(raw['from']),
            point(raw['to']),
            colors,
            stops,
            tile,
          );
        }
        final m = raw['matrix'] as List;
        final matrix = Matrix4.identity()
          ..setEntry(0, 0, (m[0] as num).toDouble())
          ..setEntry(1, 0, (m[1] as num).toDouble())
          ..setEntry(0, 1, (m[2] as num).toDouble())
          ..setEntry(1, 1, (m[3] as num).toDouble())
          ..setEntry(0, 3, (m[4] as num).toDouble())
          ..setEntry(1, 3, (m[5] as num).toDouble());
        return ui.Gradient.radial(
          point(raw['center']),
          (raw['radius'] as num).toDouble(),
          colors,
          stops,
          tile,
          matrix.storage,
          raw['focal'] == null ? null : point(raw['focal']),
        );
      }

      final commands = item['path'] as List?;
      if (commands != null) {
        final p = _paths[item] ??= (path(commands)
          ..fillType = item['fillRule'] == 'evenodd'
              ? PathFillType.evenOdd
              : PathFillType.nonZero);
        if (item['fill'] != null) {
          canvas.drawPath(
            p,
            Paint()
              ..color = itemColor(item['fill'])
              ..shader = shader(item['fillGradient']),
          );
        }
        final strokeWidth = (item['strokeWidth'] as num? ?? 0).toDouble();
        if (item['stroke'] != null && strokeWidth > 0) {
          canvas.drawPath(
            p,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap =
                  item['kind'] == 'state' || item['strokeCap'] == 'round'
                  ? StrokeCap.round
                  : item['strokeCap'] == 'square'
                  ? StrokeCap.square
                  : StrokeCap.butt
              ..strokeJoin =
                  item['kind'] == 'state' || item['strokeJoin'] == 'round'
                  ? StrokeJoin.round
                  : item['strokeJoin'] == 'bevel'
                  ? StrokeJoin.bevel
                  : StrokeJoin.miter
              ..strokeMiterLimit = (item['miterLimit'] as num? ?? 4).toDouble()
              ..strokeWidth = item['screenStrokeWidth'] is num
                  ? (item['screenStrokeWidth'] as num).toDouble() / zoom
                  : item['kind'] == 'floor'
                  ? strokeWidth / zoom
                  : strokeWidth
              ..color = itemColor(item['stroke'])
              ..shader = shader(item['strokeGradient']),
          );
        }
      }
      if (commands != null && relatedIds.contains(item['id'])) {
        final outline = _paths[item] ??= path(commands);
        canvas.drawPath(
          outline,
          Paint()..color = selectionColor.withValues(alpha: .08),
        );
        canvas.drawPath(
          outline,
          Paint()
            ..color = selectionColor.withValues(alpha: .65)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 / zoom,
        );
      }
      final images = resources['images'] as Map?;
      final image = images?[item['assetRef']];
      if (image is ui.Image) {
        Rect rectangle(Map values) => Rect.fromLTWH(
          (values['x'] as num).toDouble(),
          (values['y'] as num).toDouble(),
          (values['width'] as num).toDouble(),
          (values['height'] as num).toDouble(),
        );
        final src = rectangle(item['sourceRect'] as Map);
        final destination = rectangle(item['destinationRect'] as Map);
        canvas.drawImageRect(
          image,
          src,
          destination,
          Paint()
            ..color = Colors.white.withValues(
              alpha: (item['opacity'] as num? ?? 1).toDouble(),
            ),
        );
      }
      canvas.restore();
    }
    final connectionPaint = Paint()
      ..color = Color.lerp(selectionColor, const Color(0xff16354d), .25)!
      ..strokeWidth = 2.5 / zoom
      ..strokeCap = StrokeCap.round;
    final viewport = Rect.fromPoints(topLeft, bottomRight);
    for (final link in seatLinks) {
      if (!Rect.fromPoints(
        link.tablePoint,
        link.seatPoint,
      ).inflate(3 / zoom).overlaps(viewport)) {
        continue;
      }
      final delta = link.seatPoint - link.tablePoint, length = delta.distance;
      if (length < 1e-6) continue;
      // Solid screen-space strokes stay visible even in the short chair gap.
      canvas.drawLine(link.tablePoint, link.seatPoint, connectionPaint);
      canvas.drawCircle(
        link.tablePoint,
        3 / zoom,
        Paint()..color = connectionPaint.color,
      );
    }
    final guidePaint = Paint()
      ..color = selectionColor.withValues(alpha: .8)
      ..strokeWidth = 1 / (scale * _cameraScale(camera?.value));
    final extent =
        math.max(topLeft.distance, bottomRight.distance) +
        (bottomRight - topLeft).distance;
    if (!gridPainted) paintGrid();
    for (final guide in snapGuides) {
      canvas.save();
      canvas.rotate((guide['rotation'] as num? ?? 0) * math.pi / 180);
      final value = (guide['value'] as num).toDouble();
      if (guide['axis'] == 'x') {
        canvas.drawLine(
          Offset(value, -extent),
          Offset(value, extent),
          guidePaint,
        );
      } else {
        canvas.drawLine(
          Offset(-extent, value),
          Offset(extent, value),
          guidePaint,
        );
      }
      canvas.restore();
    }
    // Rejected translation stays outside the document/history, but its target
    // footprint remains visible at the pointer like a blocked palette drop.
    for (final hull in blockedPlacementHulls) {
      if (hull.isEmpty) continue;
      final path = Path()..moveTo(hull.first[0], hull.first[1]);
      for (final p in hull.skip(1)) {
        path.lineTo(p[0], p[1]);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0x20DC2626));
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFDC2626)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / zoom,
      );
    }
    final outline = Paint()
      ..color = selectionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / (scale * _cameraScale(camera?.value));
    for (final hull in [...selectionHulls, ...warningHulls]) {
      outline.color = warningHulls.contains(hull)
          ? const Color(0xFFDC2626)
          : selectionColor;
      if (hull.isEmpty) continue;
      final path = Path()..moveTo(hull.first[0], hull.first[1]);
      for (final p in hull.skip(1)) {
        path.lineTo(p[0], p[1]);
      }
      path.close();
      if (warningHulls.contains(hull)) {
        canvas.drawPath(path, Paint()..color = const Color(0x20DC2626));
      }
      if (emphasizeSelection && !warningHulls.contains(hull)) {
        canvas.drawPath(
          path,
          Paint()..color = selectionColor.withValues(alpha: .16),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6 / zoom,
        );
        outline.strokeWidth = 3 / zoom;
      } else {
        outline.strokeWidth = 1.5 / zoom;
      }
      canvas.drawPath(path, outline);
    }
  }

  // Accessible object controls are owned by widgets around the canvas. This
  // painter emits no semantic nodes, so geometry previews must not invalidate
  // and traverse that surrounding tree on every pointer movement.
  @override
  bool shouldRebuildSemantics(covariant LayoutScenePainter oldDelegate) =>
      false;

  @override
  bool shouldRepaint(covariant LayoutScenePainter oldDelegate) =>
      emphasizeSelection != oldDelegate.emphasizeSelection ||
      !identical(scene, oldDelegate.scene) ||
      !identical(resources, oldDelegate.resources) ||
      camera != oldDelegate.camera ||
      motion != oldDelegate.motion ||
      fromScene != oldDelegate.fromScene ||
      scale != oldDelegate.scale ||
      offset != oldDelegate.offset ||
      canvasColor != oldDelegate.canvasColor ||
      selectionColor != oldDelegate.selectionColor ||
      showGrid != oldDelegate.showGrid ||
      gridStep != oldDelegate.gridStep ||
      gridOrigin != oldDelegate.gridOrigin ||
      // Geometry overlays follow live gestures. A bare, unchanged scene can
      // retain its painted layer when only a hover tooltip is rebuilt.
      seatLinks.isNotEmpty ||
      oldDelegate.seatLinks.isNotEmpty ||
      selectionHulls.isNotEmpty ||
      oldDelegate.selectionHulls.isNotEmpty ||
      blockedPlacementHulls.isNotEmpty ||
      oldDelegate.blockedPlacementHulls.isNotEmpty ||
      warningHulls.isNotEmpty ||
      oldDelegate.warningHulls.isNotEmpty ||
      snapGuides.isNotEmpty ||
      oldDelegate.snapGuides.isNotEmpty ||
      transientForegroundIds.isNotEmpty ||
      oldDelegate.transientForegroundIds.isNotEmpty;
}

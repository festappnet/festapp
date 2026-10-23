import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'layout_scene_surface.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import 'layout_template_card.dart';
import 'layout_table_selection.dart';
import 'layout_palette_drag_feedback.dart';
import 'layout_palette_thumbnail.dart';
import 'layout_inspector.dart';
import 'layout_style.dart';
import 'layout_global_style.dart';
import 'layout_paste_stub.dart'
    if (dart.library.js_interop) 'layout_paste_web.dart'
    as paste;

/// Standalone editor. Hosting apps provide persistence and optional inspector UI.
class VenueLayoutEditor extends StatefulWidget {
  const VenueLayoutEditor({
    super.key,
    required this.controller,
    this.inspectorBuilder,
    this.toolbarPrefix,
    this.toolbarLeading,
    this.toolbarTrailing,
    this.libraryActions,
    this.libraryOverride,
    this.footerTrailing,
    this.canvasBottomOverlay,
    this.canvasHeader,
    this.showGallery = true,
    this.onTemplateSelected,
    this.onImportBackground,
    this.seatPresentation = const {},
    this.capacityPresentation = const {},
    this.interactionEnabled = true,
    this.nativeTextPreview = false,
    this.onNodeActivated,
    this.onEditRequested,
    this.inspectorOverride,
    this.viewSelection,
    this.onViewSelectionChanged,
    this.viewSelectableIds,
    this.viewSelectionTarget,
    this.readOnlyLabelNodeIds = const {},
    this.onRenameNode,
    this.fontPickerBuilder,
    this.globalFontPickerBuilder,
    this.inlineTextStyleBuilder,
  });
  final VenueLayoutController controller;

  /// Optional host font catalog for object typography, built only in edit mode.
  final Widget Function(BuildContext, LayoutNode)? fontPickerBuilder;
  final Widget Function(BuildContext, String)? globalFontPickerBuilder;

  /// Native input and editor previews use the exact loaded face.
  final Future<TextStyle> Function(LayoutNode)? inlineTextStyleBuilder;

  /// Host actions share the editor toolbar. Trailing actions stay visible while
  /// tools scroll horizontally on smaller screens.
  final Widget? toolbarLeading;

  /// Stable host mode controls, preceding the shared pointer tools.
  final Widget? toolbarPrefix;
  final Widget? toolbarTrailing;
  final Widget? libraryActions, libraryOverride, footerTrailing;

  /// Host-owned operation summary, anchored within the canvas, outside tools.
  final Widget? canvasBottomOverlay;

  /// Host-owned information above the canvas, reserving space outside the scene.
  final Widget? canvasHeader;

  /// Transient host state. Does not enter document, dirty state or history.
  final Map<String, dynamic> seatPresentation, capacityPresentation;

  /// Disable geometric tools while retaining camera, selection and activation.
  final bool interactionEnabled;

  /// Preview unsaved labels with the host's loaded font while geometry tools
  /// remain disabled. Editor hosts opt in explicitly; viewers retain canonical
  /// prepared text by default. Requires [inlineTextStyleBuilder].
  final bool nativeTextPreview;

  /// Exact node hit, shared by pointer/touch and keyboard Enter/Space.
  final ValueChanged<String>? onNodeActivated;

  /// Viewing shortcut only. The host owns edit permissions and mode changes.
  final ValueChanged<Set<String>>? onEditRequested;

  /// Host-owned operational inspector, shown in viewing mode even without a selection.
  final Widget? inspectorOverride;

  /// Optional controlled, transient view selection. Geometry history is untouched.
  final Set<String>? viewSelection;
  final ValueChanged<Set<String>>? onViewSelectionChanged;

  /// Exact nodes eligible for viewing selection. Defaults to seats/capacity areas.
  final Set<String>? viewSelectableIds;

  /// Maps a physical node to its host-owned logical selection identity.
  /// For example, a table imported inside a commercial group selects that group.
  final String Function(String nodeId)? viewSelectionTarget;

  /// Names owned by a host business workflow rather than geometry editing.
  final Set<String> readOnlyLabelNodeIds;
  final void Function(LayoutNode node, String name)? onRenameNode;
  final Widget Function(BuildContext, LayoutNode)? inspectorBuilder;
  final bool showGallery;
  final ValueChanged<LayoutTemplate>? onTemplateSelected;

  /// Host-owned image picker, decoder and portable resource registration.
  final Future<void> Function()? onImportBackground;
  @override
  State<VenueLayoutEditor> createState() => _VenueLayoutEditorState();
}

class _VenueLayoutEditorState extends State<VenueLayoutEditor> {
  final _focus = FocusNode();
  String _tool = 'Select';
  final _globalStyleOpen = ValueNotifier(false);
  final _globalStyleKey = GlobalKey<LayoutGlobalStylePanelState>();

  void _closeGlobalStyle() {
    _globalStyleKey.currentState?.cancelPreview();
    _globalStyleOpen.value = false;
  }

  bool get _surfaceTool => ['Draw table', 'Draw bar'].contains(_tool);
  bool get _polygonTool => _tool == 'Polygon';
  GridSurfaceBrush? _surfaceBrush;
  LayoutAppearance? _copiedAppearance;
  Set<String>? _selectionBeforeDown;
  bool _selectionShiftDown = false;
  VenueLayoutDocument? _hitBoundsDocument;
  final Map<String, Map<String, double>> _rowHitBounds = {};
  List<LayoutNode> _hitOrder = const [];
  String? _gestureTool;
  bool _libraryOpen = false;
  Map<String, dynamic>? _previewSeating;
  Map<String, double>? _canvasResizeBounds;
  Map<String, double>? _rowResizeBounds;
  Offset? _pendingDragPoint;
  int? _dragFrameCallback;
  final Map<String, VenueLayoutDocument> _previews = {};
  final Map<String, VenueLayoutDocument> _themedPreviews = {};
  String _librarySearch = '';
  final List<List<double>> _pathPoints = [];
  String? _pathId;
  String? _drawId;
  Offset? _pathHover;
  VenueLayoutDocument? _pathBase;

  VenueLayoutDocument? _startDocument;
  VenueLayoutDocument? _dropFragment;
  VenueLayoutDocument? _dropDocument;
  final _paletteFeedbackState = ValueNotifier(
    LayoutPaletteFeedbackState.floating,
  );
  bool _dropPreviewVisible = false;
  List<List<List<double>>> _blockedPlacementHulls = const [];
  VenueLayoutDocument? _paletteDragFragment;
  Offset? _startPointer;
  Offset? _lastDragPoint;
  String? _seatTargetId;
  bool _cornerPivot = false;
  int _resizeRemovedSeats = 0;
  bool _snap = true;
  bool _showGrid = false;
  int _templateViewport = 0;
  late final _templatePeeks = [
    for (final template in VenueLayoutTemplates.recommended.take(3))
      template.create(),
  ];
  bool _canvasSelected = false;
  bool _backgroundSelected = false;
  bool get _editingBackground =>
      _backgroundSelected &&
      c.selection.isEmpty &&
      c.document.background != null;
  bool get _editingCanvas =>
      _canvasSelected && _tool == 'Select' && c.selection.isEmpty;
  double _viewportScale = 1;
  List<Map<String, dynamic>> _snapGuides = [];
  Offset? _marquee;
  Offset? _marqueeEnd;
  Set<String> _marqueeSelectionBase = {};
  String? _inlineId;
  bool _inlineInsertion = false;
  late final VoidCallback _stopPaste;

  bool get _editingText {
    final context = FocusManager.instance.primaryFocus?.context;
    return _inlineId != null ||
        context?.widget is EditableText ||
        context?.findAncestorStateOfType<EditableTextState>() != null;
  }

  // The canvas owns live geometry previews. Keep unrelated controls mounted
  // during a pointer gesture and refresh their values at commit/cancel.
  final Map<String, (Object, Widget)> _gesturePanels = {};

  Widget _gesturePanel(String name, Widget Function() build) {
    final ids = c.selection.toList()..sort();
    final key = (
      widget.controller,
      widget.interactionEnabled,
      widget.showGallery,
      _tool,
      _librarySearch,
      _canvasSelected,
      _backgroundSelected,
      _cornerPivot,
      _copiedAppearance,
      _globalStyleOpen.value,
      c.readOnly,
      c.saving,
      ids.join(','),
    );
    final previous = _gesturePanels[name];
    if (c.gestureActive && previous != null && previous.$1 == key) {
      return previous.$2;
    }
    final child = build();
    _gesturePanels[name] = (key, child);
    return child;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _gesturePanels.clear();
  }

  VenueLayoutController get c => widget.controller;
  bool get _canEdit => widget.interactionEnabled && !c.readOnly && !c.saving;
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_globalHistoryKey);
    _stopPaste = paste.listenForLayoutPaste((text) {
      if (!mounted || !_focus.hasFocus || _editingText || !_canEdit) {
        return false;
      }
      return c.pasteSelectionText(text);
    });
    if (widget.showGallery && _canEdit && c.document.nodes.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _canEdit) _gallery();
      });
    }
  }

  @override
  void didUpdateWidget(covariant VenueLayoutEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interactionEnabled != widget.interactionEnabled) {
      // Keep the surface (and camera), but never carry a drawing tool into viewing.
      _cancelGesture();
      _tool = 'Select';
      _canvasSelected = false;
      _backgroundSelected = false;
      _inlineId = null;
      _gesturePanels.clear();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_globalHistoryKey);
    _globalStyleOpen.dispose();
    _discardDragPreview();
    _stopPaste();
    _paletteFeedbackState.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _selectionTarget(String id) {
    if (HardwareKeyboard.instance.isAltPressed) return id;
    final node = c.document.nodes.firstWhere((n) => n.id == id);
    final parent = c.document.nodes
        .where((n) => n.id == node.parentId)
        .firstOrNull;
    // Sections organize the hall; they are not editable object groups.
    if (c.document.sections.any(
      (section) => section['rootId'] == node.parentId,
    )) {
      return id;
    }
    // Native imports place a table and its chairs beside each other in a group.
    // Those chairs, like direct table children, remain individually editable.
    // Specialized assemblies and ordinary groups retain atomic selection.
    if (node.kind == 'seat' && parent != null) {
      if (parent.kind == 'table') return id;
      if (parent.kind == 'group' &&
          parent.assembly?['kind'] == null &&
          c.document.nodes.any(
            (sibling) =>
                sibling.kind == 'table' && sibling.parentId == parent.id,
          )) {
        return id;
      }
    }
    return node.parentId ?? id;
  }

  // Seats use the shared spatial index. Assembly gaps additionally hit the
  // real local footprint, cached until geometry changes.
  String? _hitAt(Offset point) {
    final direct = hitTest(
      c.document,
      point.dx,
      point.dy,
      tolerance: 8 / _viewportScale,
      // Labels and decoration must not intercept reservation selection.
      accept: _canEdit ? null : _viewSelectable,
    );
    if (!identical(_hitBoundsDocument, c.document)) {
      _hitBoundsDocument = c.document;
      _rowHitBounds.clear();
      _hitOrder = orderedNodes(c.document).reversed.toList();
    }
    // Assembly interiors participate at their real layer rank. A backdrop
    // cannot steal a gap, while a foreground object and direct seat hits win.
    for (final node in _hitOrder) {
      if (node.id == direct) return direct;
      if (!isRowAssemblyNode(node)) continue;
      final bounds = _rowHitBounds.putIfAbsent(
        node.id,
        () => rowAssemblyBounds(c.document, node.id),
      );
      final local = transformPoint(
        inverseMatrix(worldMatrix(c.document, node)),
        point.dx,
        point.dy,
      );
      if (Rect.fromLTWH(
        bounds['x']!,
        bounds['y']!,
        bounds['width']!,
        bounds['height']!,
      ).contains(Offset(local[0], local[1]))) {
        return node.id;
      }
    }
    return null;
  }

  bool _hitsBackground(Offset point) {
    if (!_canEdit || c.document.background == null) return false;
    final canvas = c.document.canvas;
    return Rect.fromLTWH(
          (canvas['x'] as num).toDouble(),
          (canvas['y'] as num).toDouble(),
          (canvas['width'] as num).toDouble(),
          (canvas['height'] as num).toDouble(),
        ).contains(point) &&
        pointInPolygon(backgroundHull(c.document), point.dx, point.dy);
  }

  void _selectBackground({bool openPanel = false}) {
    if (!_canEdit) return;
    _cancelGesture();
    c.select({});
    setState(() {
      _backgroundSelected = true;
      _canvasSelected = false;
      _tool = 'Select';
    });
    if (openPanel && context.size!.width < 900) _mobilePanel();
  }

  void _selectDown(Offset point) {
    if (!_canEdit) return;
    if (_tool != 'Select') return;
    _selectionBeforeDown = {...c.selection};
    if (_canvasSelected) setState(() => _canvasSelected = false);
    _focus.requestFocus();
    final hit = _hitAt(point);
    if (hit == null && _hitsBackground(point)) {
      _selectBackground();
      return;
    }
    if (_backgroundSelected) setState(() => _backgroundSelected = false);
    final id = hit == null ? null : _selectionTarget(hit);
    final shift = _selectionShiftDown =
        HardwareKeyboard.instance.isShiftPressed;
    if (id == null) {
      if (!shift) c.select({});
    } else if (shift) {
      final next = {...c.selection};
      if (!next.add(id)) next.remove(id);
      c.select(next);
    } else if (!c.selection.contains(id)) {
      // Keep a selected set intact while a drag gesture is still possible.
      c.select({id});
    }
  }

  String get _viewHint =>
      c.document.nodes.any(
        (node) =>
            _viewSelectable(node) &&
            (node.kind == 'table' || node.kind == 'group'),
      )
      ? 'Select a table or seat. Shift-click adds to the selection. Drag to pan; scroll to zoom.'
      : 'Select a seat to view its details. Drag to pan; scroll to zoom.';

  Set<String> get _viewSelection => widget.viewSelection ?? c.selection;
  String _viewTarget(String id) => widget.viewSelectionTarget?.call(id) ?? id;

  void _selectView(Set<String> ids) {
    if (widget.viewSelection == null) c.select(ids);
    widget.onViewSelectionChanged?.call(Set.unmodifiable(ids));
  }

  bool _viewSelectable(LayoutNode node) => widget.viewSelectableIds == null
      ? node.kind == 'seat' || node.kind == 'capacityArea'
      : widget.viewSelectableIds!.contains(node.id);

  DateTime? _viewTapTime;
  Offset? _viewTapPoint;
  String? _viewTapTarget;
  int _viewTapCount = 0;
  bool _viewTapWasSelected = false;

  bool _requestEditFromTap(Offset point, String? target) {
    if (widget.onEditRequested == null ||
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      _viewTapCount = 0;
      return false;
    }
    final now = DateTime.now();
    final continues =
        _viewTapTime != null &&
        now.difference(_viewTapTime!).inMilliseconds <= 350 &&
        _viewTapPoint != null &&
        (point - _viewTapPoint!).distance * _viewportScale <= 8 &&
        target == _viewTapTarget;
    if (!continues) {
      _viewTapCount = 0;
      _viewTapWasSelected = target != null && _viewSelection.contains(target);
    }
    _viewTapTime = now;
    _viewTapPoint = point;
    _viewTapTarget = target;
    _viewTapCount++;
    if (_viewTapCount >= 3 || (_viewTapCount == 2 && _viewTapWasSelected)) {
      _viewTapCount = 0;
      widget.onEditRequested!(target == null ? {..._viewSelection} : {target});
      return true;
    }
    return false;
  }

  void _tap(Offset point) {
    var activated = _hitAt(point);
    if (!_canEdit &&
        !c.document.nodes.any(
          (node) => node.id == activated && _viewSelectable(node),
        )) {
      activated = null;
    }
    if (!_canEdit) {
      _focus.requestFocus();
      final target = activated == null ? null : _viewTarget(activated);
      if (_requestEditFromTap(point, target)) return;
      final selected = target == null
          ? <String>{}
          : HardwareKeyboard.instance.isShiftPressed
          ? {..._viewSelection}
          : <String>{};
      if (target != null && !selected.remove(target)) {
        selected.add(target);
      }
      _selectView(selected);
      if (activated != null) widget.onNodeActivated?.call(activated);
      return;
    }
    if (activated == null && _tool == 'Select' && _hitsBackground(point)) {
      _selectionBeforeDown = null;
      _selectBackground(openPanel: true);
      return;
    }
    if (_backgroundSelected) setState(() => _backgroundSelected = false);
    if (activated != null) widget.onNodeActivated?.call(activated);
    if (_canvasSelected) setState(() => _canvasSelected = false);
    _focus.requestFocus();
    if (_tool == 'Select' || _tool == 'Pan') {
      var id = _hitAt(point);
      final selectionHandled = _selectionBeforeDown != null;
      final previouslySelected = _selectionBeforeDown ?? c.selection;
      final shift = selectionHandled
          ? _selectionShiftDown
          : HardwareKeyboard.instance.isShiftPressed;
      _selectionBeforeDown = null;
      if (selectionHandled && shift) return;
      if (id != null) id = _selectionTarget(id);
      if (id != null &&
          _tool == 'Select' &&
          previouslySelected.length == 1 &&
          previouslySelected.contains(id) &&
          !shift &&
          !HardwareKeyboard.instance.isAltPressed) {
        final node = c.document.nodes.firstWhere((n) => n.id == id);
        final local = transformPoint(
          inverseMatrix(worldMatrix(c.document, node)),
          point.dx,
          point.dy,
        );
        if (node.kind == 'text' ||
            local[1].abs() <=
                math.max(
                  16,
                  (node.properties['size'] as num? ?? 16).toDouble(),
                )) {
          if (_beginInline(node)) return;
        }
      }
      c.select(
        id == null
            ? {}
            : shift
            ? (c.selection.contains(id)
                  ? ({...c.selection}..remove(id))
                  : {...c.selection, id})
            : {id},
      );
      return;
    }
    if (_surfaceTool) {
      _startSurfacePaint(point);
      _endGesture();
      setState(() {});
      return;
    }
    if (_polygonTool || ['Line', 'Arrow', 'Polyline'].contains(_tool)) {
      _addVertex(point);
      return;
    }
    _insert(_tool, point);
  }

  void _insert(String kind, [Offset point = const Offset(400, 300)]) {
    if (!_canEdit) return;
    _drop(kind, point);
  }

  bool _editable(LayoutNode node) {
    if (c.readOnly ||
        c.saving ||
        (node.kind == 'furniture' && node.assembly?['kind'] == 'couch') ||
        !['text', 'table', 'furniture', 'capacityArea'].contains(node.kind)) {
      return false;
    }
    final byId = {for (final n in c.document.nodes) n.id: n};
    LayoutNode? current = node;
    while (current != null) {
      if (current.locked) return false;
      current = byId[current.parentId];
    }
    return true;
  }

  bool _beginInline(LayoutNode node, {bool insertion = false}) {
    if (!_editable(node) || widget.readOnlyLabelNodeIds.contains(node.id)) {
      return false;
    }
    setState(() {
      _inlineId = node.id;
      _inlineInsertion = insertion;
      _tool = 'Select';
    });
    c.select({node.id});
    return true;
  }

  void _finishInline(String? value) {
    final id = _inlineId;
    if (id == null) return;
    final insertion = _inlineInsertion;
    setState(() {
      _inlineId = null;
      _inlineInsertion = false;
    });
    final nodes = c.document.nodes.where((n) => n.id == id);
    if (value != null && nodes.isNotEmpty && _editable(nodes.first)) {
      final node = nodes.first;
      if (node.kind == 'text') {
        if (value != '${node.properties['text'] ?? node.label}') {
          c.updateNode(
            node.copyWith(properties: {...node.properties, 'text': value}),
          );
        }
      } else if (value != node.label) {
        c.updateNode(node.copyWith(label: value));
      }
      if (insertion) c.commitGesture();
    } else if (insertion) {
      c.cancelGesture();
    }
    _focus.requestFocus();
  }

  void _inlineHistory(bool redo) {
    final id = _inlineId;
    if (id == null) return;
    final node = c.document.nodes.where((n) => n.id == id).firstOrNull;
    // A clean newly inserted text is still a pending gesture. Commit it before
    // undo so creation is removed in one step and remains available for redo.
    _finishInline(
      _inlineInsertion && node != null
          ? '${node.properties['text'] ?? node.label}'
          : null,
    );
    redo ? c.redo() : c.undo();
  }

  void _doubleTap(Offset point) {
    if (_pathPoints.isNotEmpty) {
      _finishPath();
      return;
    }
    final id = _hitAt(point);
    if (id == null) {
      final canvas = c.document.canvas;
      final bounds = Rect.fromLTWH(
        (canvas['x'] as num).toDouble(),
        (canvas['y'] as num).toDouble(),
        (canvas['width'] as num).toDouble(),
        (canvas['height'] as num).toDouble(),
      );
      if (!c.readOnly && !c.saving && bounds.contains(point)) {
        c.select({});
        _focus.requestFocus();
        setState(() => _canvasSelected = true);
      }
      return;
    }
    if (_canvasSelected) setState(() => _canvasSelected = false);
    if (!HardwareKeyboard.instance.isAltPressed &&
        c.document.nodes.any(
          (node) =>
              c.selection.contains(node.id) &&
              node.kind == 'group' &&
              layoutSubtree(c.document, {node.id}).contains(id),
        )) {
      return;
    }
    final target = _selectionTarget(id);
    final node = c.document.nodes.firstWhere((n) => n.id == target);
    if (node.kind == 'group' || target != id) {
      c.select({target});
      _focus.requestFocus();
      return;
    }
    _beginInline(node);
  }

  VenueLayoutDocument _fragment(String kind, Offset point) {
    final source = _rawFragment(kind, point);
    final contextual = !kind.startsWith('preset:')
        ? source.copyWith(
            styles: c.document.styles,
            seatingDefaults: c.document.seatingDefaults,
            textPolicy: c.document.textPolicy,
          )
        : source;
    return c.nameInsertedTables(
      localizeLayoutDefaultLabels(
        contextual,
        (text) => VenueLayoutStrings.text(context, text),
      ),
      defaultTablePrefix: VenueLayoutStrings.text(context, 'Table'),
    );
  }

  VenueLayoutDocument _rawFragment(String kind, Offset point) {
    if (kind == 'Draw table' || kind == 'Draw bar') {
      {
        final node = LayoutNode(
          id: newLayoutId(),
          kind: 'table',
          x: point.dx,
          y: point.dy,
          width: 220,
          height: 160,
          surface: const {'type': 'rect'},
          seating: documentSeating(c.document).record,
          properties: kind == 'Draw bar'
              ? const {'furniture': 'bar', 'guestSide': 'bottom'}
              : const {},
        );
        return VenueLayoutDocument(
          schemaVersion: 2,
          nodes: [snapTableSurfaceToGrid(node, preset: 'L')],
        );
      }
    }
    if (kind.startsWith('preset:')) {
      final preset = c.document.presets.firstWhere(
        (p) => p['id'] == kind.substring(7),
      );
      return cloneLayout(
        VenueLayoutDocument.fromJson(
          Map<String, dynamic>.from(preset['document']),
        ),
        dx: point.dx,
        dy: point.dy,
      );
    }
    if (kind == 'Table') {
      final seating = documentTableSeating(c.document),
          scale = seating.width / 40;
      return tableLayout(
        shape: 'roundedRect',
        x: point.dx,
        y: point.dy,
        width: math.max(
          180 * scale,
          2 * seating.pitch + 2 * seating.edgePadding,
        ),
        height: math.max(
          100 * seating.height / 40,
          seating.pitch + 2 * seating.edgePadding,
        ),
        seating: seating,
      );
    }
    if (kind == 'Round table') {
      return tableLayout(
        shape: 'ellipse',
        x: point.dx,
        y: point.dy,
        width: 160 * documentTableSeating(c.document).width / 40,
        height: 160 * documentTableSeating(c.document).width / 40,
        seating: documentTableSeating(c.document),
      );
    }
    if (kind == 'Bar') {
      final scale = documentTableSeating(c.document).width / 40;
      final bar = barLayout(
        seating: documentTableSeating(c.document),
        x: point.dx,
        y: point.dy,
        width: 280 * scale,
        height: 72 * scale,
      );
      return bar.copyWith(
        nodes: [
          for (final n in bar.nodes)
            isBarNode(n)
                ? snapTableSurfaceToGrid(
                    n,
                    preset: 'rectangle',
                  ).copyWith(label: 'Bar')
                : n,
        ],
      );
    }
    if (kind == 'Couch') {
      final seating = documentSeating(c.document);
      return couchLayout(
        x: point.dx,
        y: point.dy,
        width:
            2 * seating.width +
            2 * couchGeometry['sideInset']! +
            couchGeometry['gap']!,
        height:
            seating.height +
            couchGeometry['backInset']! +
            couchGeometry['frontInset']!,
      );
    }
    if (kind == 'Rows' || kind == 'Arc') {
      final seating = documentSeating(c.document);
      return rowLayout(
        x: point.dx,
        y: point.dy,
        seating: seating,
        spacing: seating.width + seating.spacing + 4,
        rowSpacing: seating.height + seating.spacing + 12,
        aisle: 2 * seating.width,
        arc: kind == 'Arc' ? 3 * seating.height / 40 : 0,
      );
    }
    if (kind == 'Compartments') {
      return compartmentLayout(
        x: point.dx,
        y: point.dy,
        seating: documentSeating(c.document),
      );
    }
    if (kind == 'Bus' || kind == 'Double-decker bus') {
      return busLayout(
        x: point.dx,
        y: point.dy,
        decks: kind == 'Bus' ? 1 : 2,
        seating: documentSeating(c.document),
      );
    }
    if (kind == 'Polyline') {
      final node = zigzagLine(point.dx - 80, point.dy, point.dx + 80, point.dy);
      return VenueLayoutDocument(
        schemaVersion: 2,
        nodes: [
          node.copyWith(
            style: {
              'fill': '#00000000',
              'stroke': '#334155FF',
              'strokeWidth': 2,
            },
            properties: {
              for (final entry in node.properties.entries)
                if (!const {
                  'fill',
                  'stroke',
                  'strokeWidth',
                  'appearanceOverrides',
                }.contains(entry.key))
                  entry.key: entry.value,
            },
          ),
        ],
      );
    }
    final node = LayoutNode(
      id: newLayoutId(),
      kind: kind == 'Seat'
          ? 'seat'
          : kind == 'Text'
          ? 'text'
          : kind == 'Standing'
          ? 'capacityArea'
          : 'shape',
      x: point.dx,
      y: point.dy,
      width: kind == 'Seat'
          ? documentSeating(c.document).width
          : kind == 'Standing'
          ? 480
          : 160,
      height: kind == 'Seat'
          ? documentSeating(c.document).height
          : ['Line', 'Arrow'].contains(kind)
          ? 1
          : kind == 'Standing'
          ? 240
          : 80,
      label: kind == 'Standing' ? 'Standing area' : '',
      style: kind == 'Text'
          ? const {
              'label': {'size': 24, 'color': '#202830FF'},
            }
          : kind == 'Seat'
          ? const {
              'label': {'size': 16, 'align': 'center'},
            }
          : {
              'fill': ['Line', 'Arrow', 'Polyline'].contains(kind)
                  ? '#00000000'
                  : '#CBD5E1FF',
              'stroke': '#334155FF',
              'strokeWidth': 2,
              if (kind == 'Standing') 'label': {'size': 32, 'align': 'center'},
            },
      properties: kind == 'Text'
          ? {'text': VenueLayoutStrings.text(context, 'Your text')}
          : kind == 'Seat'
          ? const {'symbol': 'chair'}
          : {
              'shape':
                  {
                    'Rectangle': 'rectangle',
                    'Ellipse': 'ellipse',
                    'Line': 'line',
                    'Arrow': 'arrow',
                    'Polygon': 'polygon',
                    'Polyline': 'polyline',
                  }[kind] ??
                  'rectangle',
              if (kind == 'Polygon' || kind == 'Polyline')
                'points': [
                  [-80.0, 40.0],
                  [0.0, -40.0],
                  [80.0, 40.0],
                ],
              if (kind == 'Standing') 'capacity': 100,
            },
    );
    return VenueLayoutDocument(schemaVersion: 2, nodes: [node]);
  }

  String? _tableAt(
    Offset point,
    String seatId, {
    VenueLayoutDocument? document,
    bool feasibleOnly = false,
  }) {
    final doc = document ?? c.document;
    final seat = doc.nodes.where((n) => n.id == seatId).firstOrNull;
    for (final table in orderedNodes(
      doc,
    ).reversed.where((n) => n.kind == 'table' && !isBarNode(n))) {
      if (pointInPolygon(
        worldHull(table, worldMatrix(doc, table)),
        point.dx,
        point.dy,
      )) {
        if (seat?.parentId == table.id) return null;
        return !feasibleOnly || canAttachSeatToTable(doc, seatId, table.id)
            ? table.id
            : null;
      }
    }
    return null;
  }

  void _attachDroppedChair(String seatId, Offset point) {
    final target = _tableAt(point, seatId);
    if (target != null) c.attachChairToTable(seatId, target);
  }

  double get _surfaceModuleSize =>
      _tool == 'Draw bar' ? barSurfaceModuleSize : tableSurfaceModuleSize;

  void _startSurfacePaint(Offset point) {
    _gestureTool = 'Paint surface';
    _drawId = newLayoutId();
    _startDocument = c.document;
    _startPointer = point;
    final canvas = c.document.canvas;
    double origin(double point, String axis, String extent) {
      final low = (canvas[axis] as num).toDouble();
      final high = low + (canvas[extent] as num) - _surfaceModuleSize;
      return (point - _surfaceModuleSize / 2).clamp(low, math.max(low, high));
    }

    _surfaceBrush = GridSurfaceBrush(
      clip: canvas,
      step: _surfaceModuleSize,
      originX: origin(point.dx, 'x', 'width'),
      originY: origin(point.dy, 'y', 'height'),
    );
    c.beginGesture();
    c.select({});
    _surfaceBrush!.paint(point.dx, point.dy);
    c.preview(
      _startDocument!.copyWith(
        nodes: [
          ..._startDocument!.nodes,
          _surfaceBrush!.node(id: _drawId!, bar: _tool == 'Draw bar'),
        ],
      ),
    );
  }

  void _dragStart(Offset point) {
    if (_canvasSelected) setState(() => _canvasSelected = false);
    _focus.requestFocus();
    if (!_canEdit) return;
    if (_tool == 'Select' &&
        !HardwareKeyboard.instance.isShiftPressed &&
        _hitAt(point) == null &&
        _hitsBackground(point)) {
      _selectBackground();
      _gestureTool = 'Move background';
      _startDocument = c.document;
      _startPointer = point;
      c.beginGesture();
      return;
    }
    if (_surfaceTool) {
      _startSurfacePaint(point);
      return;
    }
    if (_polygonTool) return;
    if (['Rectangle', 'Ellipse', 'Line', 'Arrow', 'Polyline'].contains(_tool)) {
      _gestureTool = 'Draw:$_tool';
      _drawId = _pathId ?? newLayoutId();
      _startDocument = _pathBase ?? c.document;
      _startPointer = _pathPoints.isEmpty
          ? _drawingPoint(point)
          : Offset(_pathPoints.first[0], _pathPoints.first[1]);
      c.beginGesture();
      return;
    }
    final id = _hitAt(point);
    if (id == null && _tool == 'Select') {
      _marqueeSelectionBase = HardwareKeyboard.instance.isShiftPressed
          ? {...?_selectionBeforeDown, ...c.selection}
          : {};
      _marquee = point;
      _marqueeEnd = point;
      return;
    }
    final target = id == null ? null : _selectionTarget(id);
    if (target != null && !c.selection.contains(target)) {
      c.select(
        HardwareKeyboard.instance.isShiftPressed
            ? {...c.selection, target}
            : {target},
      );
    }
    if (c.selection.isEmpty) return;
    if (_tool == 'Select' &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      final originalSelection = c.selection;
      c.beginGesture();
      try {
        c.duplicateSelection(dx: 0, dy: 0);
      } catch (error) {
        c.cancelGesture();
        c.error = '$error';
        return;
      }
      if (c.selection.difference(originalSelection).isEmpty) {
        c.cancelGesture();
        return;
      }
    }
    _startDocument = c.document;
    _startPointer = point;
    _lastDragPoint = point;
    c.beginGesture();
  }

  void _discardDragPreview() {
    final callback = _dragFrameCallback;
    _dragFrameCallback = null;
    _pendingDragPoint = null;
    if (callback != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(callback);
    }
  }

  void _flushDragPreview() {
    final point = _pendingDragPoint;
    _discardDragPreview();
    if (point != null && mounted) _applyDragUpdate(point);
  }

  void _dragUpdate(Offset point) {
    if (_startDocument != null && _gestureTool != 'Paint surface') {
      // Multiple mouse samples can arrive before one frame is paintable.
      // Apply only the latest sample before that frame's build and paint.
      _pendingDragPoint = point;
      _dragFrameCallback ??= SchedulerBinding.instance.scheduleFrameCallback((
        _,
      ) {
        _dragFrameCallback = null;
        _flushDragPreview();
      });
      return;
    }
    _applyDragUpdate(point);
  }

  void _applyDragUpdate(Offset point) {
    try {
      _dragUpdateUnsafe(point);
    } catch (error) {
      setState(() {
        _resizeRemovedSeats = 0;
        c.error = error is StateError ? error.message : '$error';
      });
    }
  }

  List<double> _pathEndpoint(
    VenueLayoutDocument document,
    LayoutNode node,
    int index,
    Offset pointer, {
    int? oppositeIndex,
  }) {
    final matrix = worldMatrix(document, node);
    var point = pointer;
    final points = node.properties['points'] as List?;
    if (HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        points != null &&
        points.length >= 2) {
      final other =
          points[oppositeIndex ?? (index == 0 ? 1 : index - 1)] as List;
      final anchor = transformPoint(
        matrix,
        (other[0] as num).toDouble(),
        (other[1] as num).toDouble(),
      );
      final delta = point - Offset(anchor[0], anchor[1]);
      final angle =
          (math.atan2(delta.dy, delta.dx) / (math.pi / 12)).round() *
          math.pi /
          12;
      point =
          Offset(anchor[0], anchor[1]) +
          Offset(math.cos(angle), math.sin(angle)) * delta.distance;
    }
    return transformPoint(inverseMatrix(matrix), point.dx, point.dy);
  }

  void _dragUpdateUnsafe(Offset point) {
    if (_marquee != null) {
      setState(() => _marqueeEnd = point);
      return;
    }
    final start = _startDocument, pointer = _startPointer;
    if (start == null || pointer == null) return;
    _lastDragPoint = point;
    final delta = point - pointer;
    final gesture = _gestureTool ?? _tool;
    if (gesture == 'Move background') {
      final background = start.background!;
      c.preview(
        start.copyWith(
          background: {
            ...background,
            'x': (background['x'] as num? ?? 0) + delta.dx,
            'y': (background['y'] as num? ?? 0) + delta.dy,
          },
        ),
      );
      return;
    }
    if (gesture.startsWith('Canvas resize ')) {
      final direction = gesture.substring('Canvas resize '.length);
      final canvas = start.canvas;
      var left = (canvas['x'] as num).toDouble();
      var top = (canvas['y'] as num).toDouble();
      var right = left + (canvas['width'] as num).toDouble();
      var bottom = top + (canvas['height'] as num).toDouble();
      final content = _canvasResizeBounds;
      final minimum = layoutLimits['canvasMin']!.toDouble();
      if (direction.contains('w')) {
        left = math.min(left + delta.dx, right - minimum);
        if (content != null) left = math.min(left, content['x']!);
      }
      if (direction.contains('e')) {
        right = math.max(right + delta.dx, left + minimum);
        if (content != null) {
          right = math.max(right, content['x']! + content['width']!);
        }
      }
      if (direction.contains('n')) {
        top = math.min(top + delta.dy, bottom - minimum);
        if (content != null) top = math.min(top, content['y']!);
      }
      if (direction.contains('s')) {
        bottom = math.max(bottom + delta.dy, top + minimum);
        if (content != null) {
          bottom = math.max(bottom, content['y']! + content['height']!);
        }
      }
      // Dragging uses whole schematic units and rounds outward so content
      // remains contained, including fractional imported object bounds.
      if (direction.contains('w')) left = left.floorToDouble();
      if (direction.contains('e')) right = right.ceilToDouble();
      if (direction.contains('n')) top = top.floorToDouble();
      if (direction.contains('s')) bottom = bottom.ceilToDouble();
      // The gesture bounds already clamp against the unchanged content.
      // Keep the same object nodes; controller guards still validate the draft.
      c.preview(
        start.copyWith(
          canvas: {
            ...canvas,
            'x': left,
            'y': top,
            'width': right - left,
            'height': bottom - top,
          },
        ),
      );
    } else if (gesture == 'Paint surface') {
      if (_surfaceBrush!.paint(point.dx, point.dy)) {
        final node = _surfaceBrush!.node(
          id: _drawId!,
          bar: _tool == 'Draw bar',
        );
        c.preview(start.copyWith(nodes: [...start.nodes, node]));
      }
    } else if (gesture.startsWith('Draw:')) {
      final shape = gesture.substring(5).toLowerCase();
      final end = _drawingPoint(point, anchor: pointer);
      final node = shape == 'polyline'
          ? zigzagLine(
              pointer.dx,
              pointer.dy,
              end.dx,
              end.dy,
              id: _drawId,
              style: const {
                'fill': '#00000000',
                'stroke': '#334155FF',
                'strokeWidth': 2,
              },
            )
          : shapeFromPoints(
              shape,
              [
                [pointer.dx, pointer.dy],
                [end.dx, end.dy],
              ],
              id: _drawId,
              style: {
                'fill': ['line', 'arrow', 'polyline'].contains(shape)
                    ? '#00000000'
                    : '#CBD5E1FF',
                'stroke': '#334155FF',
                'strokeWidth': 2,
              },
              properties: const {},
            );
      c.preview(start.copyWith(nodes: [...start.nodes, node]));
    } else if (gesture.startsWith('Zigzag ') && c.selection.length == 1) {
      final n = start.nodes.firstWhere((n) => c.selection.contains(n.id));
      final local = transformPoint(
        inverseMatrix(worldMatrix(start, n)),
        point.dx,
        point.dy,
      );
      final points = n.properties['points'] as List;
      final a = (points.first as List).cast<num>();
      final b = (points.last as List).cast<num>();
      if (gesture == 'Zigzag amplitude') {
        final dx = b[0].toDouble() - a[0].toDouble();
        final dy = b[1].toDouble() - a[1].toDouble();
        final length = math.sqrt(dx * dx + dy * dy);
        final amplitude =
            ((local[0] - a[0]) * -dy + (local[1] - a[1]) * dx).abs() / length;
        c.preview(updateZigzag(start, n.id, amplitude: amplitude));
      } else {
        final first = gesture == 'Zigzag endpoint 0';
        final endpoint = _pathEndpoint(
          start,
          n,
          first ? 0 : points.length - 1,
          point,
          oppositeIndex: first ? points.length - 1 : 0,
        );
        c.preview(
          updateZigzag(
            start,
            n.id,
            start: first ? endpoint : null,
            end: first ? null : endpoint,
          ),
        );
      }
    } else if (gesture.startsWith('Extend edge ') && c.selection.length == 1) {
      final selected = start.nodes.firstWhere(
        (n) => c.selection.contains(n.id),
      );
      final node = tabletopSelectionNode(start, selected);
      final local = transformPoint(
        inverseMatrix(worldMatrix(start, node)),
        point.dx,
        point.dy,
      );
      final edgeParts = gesture.substring(12).split(' cell ');
      c.preview(
        extendGridTableSurface(
          start,
          node.id,
          int.parse(edgeParts.first),
          local[0],
          local[1],
          cellIndex: edgeParts.length == 2 ? int.parse(edgeParts.last) : null,
          protectedSeatIds: c.protectedSeatIds?.call() ?? const {},
        ),
      );
    } else if (gesture.startsWith('Vertex ') && c.selection.length == 1) {
      final n = start.nodes.firstWhere((n) => c.selection.contains(n.id));
      final local = _pathEndpoint(
        start,
        n,
        int.parse(gesture.substring(7)),
        point,
      );
      c.preview(
        updatePathVertex(
          start,
          n.id,
          int.parse(gesture.substring(7)),
          local[0],
          local[1],
          protectedSeatIds: c.protectedSeatIds?.call() ?? const {},
        ),
      );
    } else if (gesture.startsWith('Resize') && c.selection.length == 1) {
      var n = start.nodes.firstWhere((n) => c.selection.contains(n.id));
      if (n.kind == 'group' && n.assembly?['kind'] == null) {
        final children = start.nodes
            .where((child) => child.parentId == n.id)
            .toList();
        // A native table wrapper is commercial grouping, not scalable furniture.
        // Resize its real desk through the same seating policy as a normal table.
        if (children.length == 1 && children.single.kind == 'table') {
          n = children.single;
        }
      }
      if (n.kind == 'group' && n.assembly?['kind'] == null) {
        final bounds = selectionBounds(start, {n.id});
        final direction = gesture == 'Resize' ? 'se' : gesture.substring(7);
        final west = direction.contains('w'), north = direction.contains('n');
        final horizontal = west || direction.contains('e');
        final vertical = north || direction.contains('s');
        var dx = (point.dx - pointer.dx) * (west ? -1 : 1);
        var dy = (point.dy - pointer.dy) * (north ? -1 : 1);
        final snapped = snapTranslation(
          start,
          c.selection,
          0,
          0,
          zoom: _viewportScale,
          grid: 8,
          disabled: !_snap || HardwareKeyboard.instance.isAltPressed,
          sourceBounds: {
            'x':
                bounds['x']! +
                (west
                    ? -dx
                    : horizontal
                    ? bounds['width']! + dx
                    : bounds['width']! / 2),
            'y':
                bounds['y']! +
                (north
                    ? -dy
                    : vertical
                    ? bounds['height']! + dy
                    : bounds['height']! / 2),
            'width': 0,
            'height': 0,
          },
        );
        if (horizontal) dx += (west ? -1 : 1) * snapped.dx;
        if (vertical) dy += (north ? -1 : 1) * snapped.dy;
        _snapGuides = snapped.guides
            .where(
              (guide) => guide['axis'] == 'x'
                  ? horizontal &&
                        (!vertical ||
                            (dx / bounds['width']!).abs() >=
                                (dy / bounds['height']!).abs())
                  : vertical &&
                        (!horizontal ||
                            (dy / bounds['height']!).abs() >
                                (dx / bounds['width']!).abs()),
            )
            .toList();
        // Scale furniture and spacing while retaining physical chair sizes.
        final change =
            horizontal &&
                (!vertical ||
                    (dx / bounds['width']!).abs() >=
                        (dy / bounds['height']!).abs())
            ? dx / bounds['width']!
            : dy / bounds['height']!;
        final scale = math.max(.01, 1 + change);
        final pivot = Offset(
          bounds['x']! +
              (west
                  ? bounds['width']!
                  : horizontal
                  ? 0
                  : bounds['width']! / 2),
          bounds['y']! +
              (north
                  ? bounds['height']!
                  : vertical
                  ? 0
                  : bounds['height']! / 2),
        );
        final matrices = worldMatrices(start), root = matrices[n.id]!;
        final x = pivot.dx + (root[4] - pivot.dx) * scale;
        final y = pivot.dy + (root[5] - pivot.dy) * scale;
        final parent = matrices[n.parentId];
        final origin = parent == null
            ? [x, y]
            : transformPoint(inverseMatrix(parent), x, y);
        final ids = layoutSubtree(start, {n.id});
        c.preview(
          start.copyWith(
            nodes: start.nodes.map((node) {
              if (!ids.contains(node.id)) return node;
              return node.copyWith(
                x: node.id == n.id ? origin[0] : node.x * scale,
                y: node.id == n.id ? origin[1] : node.y * scale,
                width: node.kind == 'seat' ? node.width : node.width * scale,
                height: node.kind == 'seat' ? node.height : node.height * scale,
                properties: {
                  ...node.properties,
                  if (node.kind != 'seat' && node.properties['points'] is List)
                    'points': [
                      for (final p in node.properties['points'] as List)
                        [(p[0] as num) * scale, (p[1] as num) * scale],
                    ],
                  if (node.kind != 'seat' && node.properties['holes'] is List)
                    'holes': [
                      for (final hole in node.properties['holes'] as List)
                        [
                          for (final p in hole as List)
                            [(p[0] as num) * scale, (p[1] as num) * scale],
                        ],
                    ],
                },
              );
            }).toList(),
          ),
        );
        return;
      }
      final inverse = inverseMatrix(worldMatrix(start, n));
      final initial = transformPoint(inverse, pointer.dx, pointer.dy),
          current = transformPoint(inverse, point.dx, point.dy);
      final direction = gesture == 'Resize' ? 'se' : gesture.substring(7);
      final sx = direction.contains('w')
          ? -1.0
          : direction.contains('e')
          ? 1.0
          : 0.0;
      final sy = direction.contains('n')
          ? -1.0
          : direction.contains('s')
          ? 1.0
          : 0.0;
      final isRows = isRowAssemblyNode(n);
      final oldBounds = isRows
          ? (_rowResizeBounds ??= rowAssemblyBounds(start, n.id))
          : null;
      final oldWidth = oldBounds?['width'] ?? n.width;
      final oldHeight = oldBounds?['height'] ?? n.height;
      var width = math.max(1.0, oldWidth + (current[0] - initial[0]) * sx);
      var height = math.max(1.0, oldHeight + (current[1] - initial[1]) * sy);
      final snappedSize = snapResize(
        start,
        n,
        width,
        height,
        sx: sx,
        sy: sy,
        zoom: _viewportScale,
        grid: 8,
        disabled: !_snap || HardwareKeyboard.instance.isAltPressed,
        localBounds: oldBounds,
      );
      width = snappedSize.width;
      height = snappedSize.height;
      _snapGuides = snappedSize.guides;
      final roundTable = n.kind == 'table' && n.surface?['type'] == 'circle';
      final shift = HardwareKeyboard.instance.isShiftPressed;
      final graphic = n.kind == 'image' || n.kind == 'vector';
      if (roundTable || (graphic ? !shift : shift)) {
        if (sx != 0 &&
            (sy == 0 ||
                ((width - oldWidth) / oldWidth).abs() >=
                    ((height - oldHeight) / oldHeight).abs())) {
          height = width * oldHeight / oldWidth;
        } else {
          width = height * oldWidth / oldHeight;
        }
      }
      final dimensions = c.constrainTableDimensions(n, width, height);
      width = dimensions.width;
      height = dimensions.height;
      if (n.kind == 'table' && n.surface?['type'] != 'grid') {
        if (c.previewTableResize(
          start,
          n.id,
          width,
          height,
          handle: direction,
        )) {
          _resizeRemovedSeats =
              start.nodes
                  .where((node) => node.kind == 'seat' && node.parentId == n.id)
                  .length -
              c.document.nodes
                  .where((node) => node.kind == 'seat' && node.parentId == n.id)
                  .length;
        }
        return;
      }
      final resizeBase = start;
      final resized = isRows
          ? resizeRowAssembly(start, n.id, width, height)
          : n.kind == 'furniture' && n.assembly?['kind'] == 'couch'
          ? resizeCouchBody(start, n.id, width, height)
          : n.kind == 'table' && n.surface?['type'] == 'grid'
          ? resizeGridTableSurface(
              resizeBase,
              n.id,
              width,
              height,
              protectedSeatIds: c.protectedSeatIds?.call() ?? const {},
            )
          : resizeNode(
              resizeBase,
              n.id,
              width,
              height,
              protectedSeatIds: c.protectedSeatIds?.call() ?? const {},
            );
      _resizeRemovedSeats = n.kind == 'table'
          ? start.nodes
                    .where(
                      (node) => node.kind == 'seat' && node.parentId == n.id,
                    )
                    .length -
                resized.nodes
                    .where(
                      (node) => node.kind == 'seat' && node.parentId == n.id,
                    )
                    .length
          : 0;
      final resizedRoot = resized.nodes.firstWhere((node) => node.id == n.id);
      width = resizedRoot.width;
      height = resizedRoot.height;
      _snapGuides = _snapGuides
          .where(
            (guide) => guide['axis'] == 'x'
                ? (width - snappedSize.width).abs() < .01
                : (height - snappedSize.height).abs() < .01,
          )
          .toList();
      final actualBounds = isRows ? rowAssemblyBounds(resized, n.id) : null;
      // Keep the opposite edge fixed even when curved chair tangents change
      // the generated footprint's local origin.
      final matrix = worldMatrix(start, n);
      final shiftX = isRows
          ? oldBounds!['x']! -
                actualBounds!['x']! +
                (sx < 0 ? oldWidth - actualBounds['width']! : 0.0)
          : (width - n.width) * sx / 2;
      final shiftY = isRows
          ? oldBounds!['y']! -
                actualBounds!['y']! +
                (sy < 0 ? oldHeight - actualBounds['height']! : 0.0)
          : (height - n.height) * sy / 2;
      // This move already resolves chair placement and canvas constraints.
      // Avoid running the same table packer again in the controller.
      c.previewMove(
        transformNodes(
          resized,
          {n.id},
          dx: matrix[0] * shiftX + matrix[2] * shiftY,
          dy: matrix[1] * shiftX + matrix[3] * shiftY,
        ),
        {n.id},
        dx: 0,
        dy: 0,
      );
    } else if (gesture == 'Rotate') {
      final nodes = start.nodes.where((n) => c.selection.contains(n.id));
      final bounds = selectionBounds(start, nodes.map((n) => n.id).toSet());
      final center = Offset(
        bounds['x']! + (_cornerPivot ? 0 : bounds['width']! / 2),
        bounds['y']! + (_cornerPivot ? 0 : bounds['height']! / 2),
      );
      final a = pointer - center, b = point - center;
      var degrees =
          (math.atan2(b.dy, b.dx) - math.atan2(a.dy, a.dx)) * 180 / math.pi;
      if ((_snap || HardwareKeyboard.instance.isShiftPressed) &&
          !HardwareKeyboard.instance.isAltPressed) {
        // Read angles directly: canonical matrices quantize trigonometric
        // components, which would turn an exact 30° snap into 29.986°.
        final byId = {for (final n in start.nodes) n.id: n};
        LayoutNode? reference = nodes.first;
        var initialAngle = 0.0;
        while (reference != null) {
          initialAngle += reference.rotation;
          reference = byId[reference.parentId];
        }
        degrees = ((initialAngle + degrees) / 15).round() * 15 - initialAngle;
      }
      c.preview(
        moveLayoutWithinCanvas(
          transformNodes(
            start,
            c.selection,
            rotation: degrees,
            cornerPivot: _cornerPivot,
          ),
          c.selection,
        ),
      );
    } else {
      final snapped = snapTranslation(
        start,
        c.selection,
        delta.dx,
        delta.dy,
        zoom: _viewportScale,
        grid: 8,
        disabled: !_snap || HardwareKeyboard.instance.isAltPressed,
      );
      if (!c.previewMove(start, c.selection, dx: snapped.dx, dy: snapped.dy)) {
        final attempted = transformNodes(
          start,
          c.selection,
          dx: snapped.dx,
          dy: snapped.dy,
        );
        final ids = layoutSubtree(attempted, c.selection);
        final matrices = worldMatrices(attempted);
        setState(() {
          _blockedPlacementHulls = [
            for (final node in attempted.nodes)
              if (ids.contains(node.id) && node.kind != 'group')
                worldHull(node, matrices[node.id]!),
          ];
          _snapGuides = [];
        });
        return;
      }
      _blockedPlacementHulls = const [];
      final next = c.document;
      _snapGuides = snapped.guides;
      final expected = selectionBounds(start, c.selection);
      final actual = selectionBounds(next, c.selection);
      if ((actual['x']! - expected['x']! - snapped.dx).abs() > .01 ||
          (actual['y']! - expected['y']! - snapped.dy).abs() > .01) {
        _snapGuides = [];
      }
      if (c.selection.length == 1 &&
          c.document.nodes.any(
            (n) => c.selection.contains(n.id) && n.kind == 'seat',
          )) {
        _seatTargetId = _tableAt(
          point,
          c.selection.single,
          document: next,
          feasibleOnly: true,
        );
      }
    }
  }

  void _nameSketchedSurface(String id) {
    final node = c.document.nodes.firstWhere((n) => n.id == id);
    final named = c
        .nameInsertedTables(
          VenueLayoutDocument(
            schemaVersion: c.document.schemaVersion,
            nodes: [node.copyWith(label: isBarNode(node) ? 'Bar' : '')],
          ),
        )
        .nodes
        .single;
    c.preview(
      c.document.copyWith(
        nodes: [for (final n in c.document.nodes) n.id == id ? named : n],
      ),
    );
  }

  void _endGesture() {
    _flushDragPreview();
    _blockedPlacementHulls = const [];
    _rowResizeBounds = null;
    _resizeRemovedSeats = 0;
    _selectionBeforeDown = null;
    if (_startDocument != null &&
        _dropFragment == null &&
        _gestureTool == null &&
        _tool == 'Select' &&
        _lastDragPoint != null &&
        c.selection.length == 1 &&
        c.document.nodes.any(
          (n) => c.selection.contains(n.id) && n.kind == 'seat',
        )) {
      final seatId = c.selection.single;
      final previousParent = c.document.nodes
          .firstWhere((n) => n.id == seatId)
          .parentId;
      _attachDroppedChair(seatId, _lastDragPoint!);
      final currentParent = c.document.nodes
          .firstWhere((n) => n.id == seatId)
          .parentId;
      // Attachment already packed the incoming chair. Only an independent
      // adjustment within its existing table becomes a manual standard slot.
      if (previousParent == currentParent &&
          c.error == null &&
          _snap &&
          !HardwareKeyboard.instance.isAltPressed) {
        c.snapChairToStandardPosition(c.selection.single);
      }
    }
    _seatTargetId = null;
    _lastDragPoint = null;
    _snapGuides = [];
    if (_marquee != null && _marqueeEnd != null) {
      final a = _marquee!, b = _marqueeEnd!;
      final hits = hitTestRect(c.document, {
        'x': math.min(a.dx, b.dx),
        'y': math.min(a.dy, b.dy),
        'width': (a.dx - b.dx).abs(),
        'height': (a.dy - b.dy).abs(),
      }).map(_selectionTarget).toSet().union(_marqueeSelectionBase);
      final nodes = {for (final n in c.document.nodes) n.id: n};
      c.select(
        hits.where((id) {
          var parent = nodes[id]?.parentId;
          while (parent != null) {
            if (hits.contains(parent)) return false;
            parent = nodes[parent]?.parentId;
          }
          return true;
        }).toSet(),
      );
      _marqueeSelectionBase = {};
      _marquee = null;
      _marqueeEnd = null;
    }
    if (_startDocument != null) {
      if (c.error == null) {
        if (_surfaceTool &&
            _drawId != null &&
            c.document.nodes.any((n) => n.id == _drawId)) {
          _nameSketchedSurface(_drawId!);
        }
        c.commitGesture();
      } else {
        final error = c.error;
        c.cancelGesture();
        c.error = error;
      }
    }
    if (_drawId != null && c.document.nodes.any((n) => n.id == _drawId)) {
      c.select({_drawId!});
      _tool = 'Select';
      _pathPoints.clear();
      _pathBase = null;
      _pathId = null;
      _pathHover = null;
    }
    _drawId = null;
    _surfaceBrush = null;
    _dropFragment = null;
    _dropDocument = null;
    _dropPreviewVisible = false;
    _startDocument = null;
    _startPointer = null;
    _gestureTool = null;
  }

  void _cancelGesture() {
    _discardDragPreview();
    _blockedPlacementHulls = const [];
    _rowResizeBounds = null;
    _surfaceBrush = null;
    _resizeRemovedSeats = 0;
    _drawId = null;
    _seatTargetId = null;
    _lastDragPoint = null;
    _snapGuides = [];
    if (_marquee != null && _selectionBeforeDown != null) {
      c.select(_selectionBeforeDown!);
    }
    _selectionBeforeDown = null;
    _marqueeSelectionBase = {};
    _marquee = null;
    _marqueeEnd = null;
    _pathPoints.clear();
    _pathHover = null;
    _pathId = null;
    _pathBase = null;
    _gestureTool = null;
    c.cancelGesture();
    _paletteFeedbackState.value = LayoutPaletteFeedbackState.floating;
    _dropFragment = null;
    _dropDocument = null;
    _dropPreviewVisible = false;
    _startDocument = null;
    _startPointer = null;
  }

  void _clearSelection() {
    _cancelGesture();
    c.select({});
    setState(() {
      _canvasSelected = false;
      _backgroundSelected = false;
      _tool = 'Select';
    });
    _focus.requestFocus();
  }

  KeyEventResult _globalHistoryKey(KeyEvent event) {
    // History belongs to the visible editor route, even when surrounding
    // controls own focus. Dialogs, inactive tabs and text inputs retain theirs.
    if (!mounted ||
        // Retain compatibility with the declared Flutter 3.32 minimum.
        // ignore: deprecated_member_use
        !TickerMode.of(context) ||
        ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    return _historyKey(event);
  }

  KeyEventResult _historyKey(KeyEvent event) {
    if (event is! KeyDownEvent || _editingText || !_canEdit) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ) {
      keyboard.isShiftPressed ? c.redo() : c.undo();
    } else if (event.logicalKey == LogicalKeyboardKey.keyY) {
      c.redo();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _editingText) return KeyEventResult.ignored;
    if (_historyKey(event) == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
    if (widget.onNodeActivated != null &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) &&
        (widget.interactionEnabled ? c.selection : _viewSelection).length ==
            1) {
      widget.onNodeActivated!(
        (widget.interactionEnabled ? c.selection : _viewSelection).single,
      );
      return KeyEventResult.handled;
    }
    if (!widget.interactionEnabled &&
        event.logicalKey == LogicalKeyboardKey.tab) {
      final ids = c.document.nodes
          .where(_viewSelectable)
          .map((n) => _viewTarget(n.id))
          .toSet()
          .toList();
      if (ids.isEmpty) return KeyEventResult.ignored;
      final current = ids.indexWhere(_viewSelection.contains);
      final direction = HardwareKeyboard.instance.isShiftPressed ? -1 : 1;
      final next = current < 0
          ? (direction > 0 ? 0 : ids.length - 1)
          : (current + direction) % ids.length;
      _selectView({ids[next]});
      return KeyEventResult.handled;
    }
    if (!_canEdit) return KeyEventResult.ignored;
    final k = event.logicalKey, keyboard = HardwareKeyboard.instance;
    final modifier = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (k == LogicalKeyboardKey.enter && _pathPoints.isNotEmpty) {
      _finishPath();
    } else if (k == LogicalKeyboardKey.backspace && _pathPoints.isNotEmpty) {
      _pathPoints.removeLast();
      if (_pathPoints.isEmpty) {
        _cancelGesture();
      } else {
        _previewPath();
      }
    } else if (k == LogicalKeyboardKey.escape) {
      _clearSelection();
    } else if (!modifier && k == LogicalKeyboardKey.keyG) {
      setState(() => _showGrid = !_showGrid);
    } else if (modifier && k == LogicalKeyboardKey.keyC) {
      c.copySelectionToClipboard();
    } else if (modifier && k == LogicalKeyboardKey.keyV) {
      if (paste.usesNativePasteEvents) return KeyEventResult.ignored;
      c.pasteFromClipboard();
    } else if (modifier && k == LogicalKeyboardKey.keyD) {
      c.duplicateSelection();
    } else if (k == LogicalKeyboardKey.delete ||
        k == LogicalKeyboardKey.backspace) {
      c.deleteSelection();
    } else if ([
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ].contains(k)) {
      final step = keyboard.isShiftPressed ? 10.0 : 1.0;
      c.moveSelection(
        k == LogicalKeyboardKey.arrowLeft
            ? -step
            : k == LogicalKeyboardKey.arrowRight
            ? step
            : 0,
        k == LogicalKeyboardKey.arrowUp
            ? -step
            : k == LogicalKeyboardKey.arrowDown
            ? step
            : 0,
      );
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _gallery() async {
    final picked = await showEditorDialog<LayoutTemplate>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 700),
          child: Column(
            children: [
              ListTile(
                title: const LayoutText('Choose a starting plan'),
                subtitle: const LayoutText(
                  'Every layout is editable. All sections stay on one plan.',
                ),
                trailing: IconButton(
                  tooltip: VenueLayoutStrings.text(context, 'Close gallery'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, size) => GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: math.max(
                        1,
                        (size.maxWidth / 260).floor(),
                      ),
                      mainAxisExtent: 250,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: VenueLayoutTemplates.recommended.length,
                    itemBuilder: (context, index) {
                      final template = VenueLayoutTemplates.recommended[index];
                      return LayoutTemplateCard(
                        key: ValueKey('layout-template-${template.id}'),
                        template: template,
                        onPressed: () => Navigator.pop(context, template),
                        preview: LayoutSceneSurface(
                          showControls: false,
                          animate: false,
                          document: template.create(),
                          resources: c.resources,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      if (c.document.nodes.isNotEmpty) {
        final replace = await showEditorDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const LayoutText('Replace the current plan?'),
            content: LayoutText(
              'Use ${picked.title}. Your current plan can be restored with Undo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const LayoutText('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const LayoutText('Replace plan'),
              ),
            ],
          ),
        );
        if (replace != true) return;
      }
      if (c.apply(
        picked.create(
          localize: (text) => VenueLayoutStrings.text(context, text),
        ),
        label: 'Choose template',
      )) {
        setState(() => _templateViewport++);
        widget.onTemplateSelected?.call(picked);
      }
    }
  }

  void _library() => setState(() => _libraryOpen = !_libraryOpen);
  VenueLayoutDocument _previewDocument(String kind) {
    final cached = _themedPreviews[kind];
    if (cached != null &&
        sameLayoutValue(cached.styles, c.document.styles) &&
        sameLayoutValue(cached.seatingDefaults, c.document.seatingDefaults) &&
        sameLayoutValue(cached.textPolicy, c.document.textPolicy)) {
      return cached;
    }
    final previous = _previews[kind];
    if (previous != null &&
        !sameLayoutValue(previous.seatingDefaults, c.document.seatingDefaults)) {
      _previews.remove(kind);
    }
    final base = _previews.putIfAbsent(kind, () {
      final fragment = _fragment(kind, Offset.zero);
      return fragment.copyWith(
        nodes: [
          for (final n in fragment.nodes)
            n.copyWith(
              label: '',
              properties: n.kind == 'text'
                  ? {...n.properties, 'text': 'Aa'}
                  : n.properties,
            ),
        ],
        canvas: {...fragment.canvas, 'fill': '#00000000'},
      );
    });
    return _themedPreviews[kind] = base.copyWith(
      styles: c.document.styles,
      seatingDefaults: c.document.seatingDefaults,
      textPolicy: c.document.textPolicy,
    );
  }

  Widget _palette() => _gesturePanel('palette', () => _buildPalette());

  Widget _buildPalette({
    ValueChanged<String>? onChoose,
    ValueChanged<String>? onSearch,
  }) {
    final seating = documentSeating(c.document).record;
    if (!sameLayoutValue(_previewSeating, seating)) {
      _previewSeating = seating;
      _previews.clear();
      _themedPreviews.clear();
    }
    final colors = Theme.of(context).colorScheme;
    final categories = <String, Map<String, String>>{
      'Seating': {
        for (final k in [
          'Seat',
          'Table',
          'Round table',
          'Rows',
          'Arc',
          'Standing',
          'Couch',
          'Bar',
          'Draw table',
          'Draw bar',
        ])
          k: k == 'Draw bar'
              ? 'Paint bar'
              : k == 'Draw table'
              ? 'Paint table'
              : k,
      },
      'Transport': {
        for (final k in ['Bus', 'Double-decker bus', 'Compartments']) k: k,
      },
      'Text & shapes': {
        for (final k in [
          'Text',
          'Rectangle',
          'Ellipse',
          'Line',
          'Arrow',
          'Polyline',
          'Polygon',
        ])
          k: k == 'Polyline' ? 'Zigzag' : k,
      },
    };
    var matches = 0;
    final sections = <Widget>[];
    for (final category in categories.entries) {
      final entries = category.value.entries
          .where(
            (e) =>
                e.key.toLowerCase().contains(_librarySearch.toLowerCase()) ||
                e.value.toLowerCase().contains(_librarySearch.toLowerCase()) ||
                VenueLayoutStrings.text(
                  context,
                  e.value,
                ).toLowerCase().contains(_librarySearch.toLowerCase()),
          )
          .toList();
      if (entries.isEmpty) continue;
      matches += entries.length;
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          child: LayoutText(
            category.key,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
              letterSpacing: .4,
            ),
          ),
        ),
      );
      sections.add(
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 68 + _paletteLabelHeight,
          children: [
            for (final entry in entries)
              if (onChoose != null ||
                  ['Draw table', 'Draw bar'].contains(entry.key))
                _paletteTile(entry.key, entry.value, onChoose: onChoose)
              else
                Draggable<String>(
                  data: entry.key,
                  // Feedback and placement share the fragment's world origin.
                  dragAnchorStrategy: (_, _, _) => Offset.zero,
                  onDragStarted: () {
                    _cancelGesture();
                    _paletteFeedbackState.value =
                        LayoutPaletteFeedbackState.floating;
                    _paletteDragFragment = _fragment(entry.key, Offset.zero);
                    _dropFragment = _paletteDragFragment;
                  },
                  onDragEnd: (details) {
                    if (!details.wasAccepted) _cancelGesture();
                    _paletteDragFragment = null;
                  },
                  feedback: LayoutPaletteDragFeedback(
                    document: () =>
                        _paletteDragFragment ??
                        _fragment(entry.key, Offset.zero),
                    scale: () => _viewportScale,
                    changes: c,
                    state: _paletteFeedbackState,
                    resources: c.resources,
                  ),
                  child: _paletteTile(entry.key, entry.value),
                ),
          ],
        ),
      );
    }
    return Material(
      key: const ValueKey('layout-palette'),
      color: layoutPanelColor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showGallery) ...[
            InkWell(
              key: const ValueKey('palette-templates'),
              onTap: _canEdit ? _gallery : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.dashboard_outlined, size: 20),
                        SizedBox(width: 8),
                        Expanded(child: LayoutText('Choose template')),
                        Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ExcludeSemantics(
                      child: SizedBox(
                        height: 42,
                        child: Row(
                          children: [
                            for (final document in _templatePeeks)
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: LayoutPaletteThumbnail(
                                    document: document,
                                    resources: c.resources,
                                    kind: 'Template',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
            child: LayoutText(
              'Objects',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: LayoutText(
              onChoose != null
                  ? 'Tap an object to add it. Drawing tools continue on the plan.'
                  : 'Drag onto the plan, or click to place',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              decoration: InputDecoration(
                labelText: VenueLayoutStrings.text(context, 'Find object'),
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onChanged: onSearch ?? (v) => setState(() => _librarySearch = v),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                const SizedBox(height: 8),
                if (widget.libraryActions != null) widget.libraryActions!,
                const Divider(),
                ...sections,
                if (matches == 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: LayoutText('No matching objects. Try another name.'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Reserve two complete lines using the same explicit line height as the
  // label, including the user's text scaling. The thumbnail keeps its space.
  double get _paletteLabelHeight =>
      (MediaQuery.textScalerOf(context).scale(12) * 1.35 * 2).ceilToDouble() +
      2;

  Widget _paletteTile(
    String kind,
    String title, {
    ValueChanged<String>? onChoose,
  }) {
    final colors = Theme.of(context).colorScheme;
    final selected = _tool == kind;
    return Semantics(
      label: VenueLayoutStrings.text(context, 'Place $title'),
      selected: selected,
      button: true,
      child: OutlinedButton(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.fromLTRB(6, 6, 6, 8),
          ),
          animationDuration: Duration(
            milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 120,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => selected
                ? colors.primary.withValues(alpha: .07)
                : states.contains(WidgetState.hovered)
                ? colors.surfaceContainerLow
                : colors.surface,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: selected || states.contains(WidgetState.focused)
                  ? colors.primary
                  : colors.outline.withValues(alpha: .8),
              width: selected || states.contains(WidgetState.focused) ? 1.5 : 1,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        onPressed: () {
          if (!_canEdit) return;
          if (onChoose != null) {
            onChoose(kind);
            return;
          }
          _cancelGesture();
          setState(() => _tool = kind);
        },
        child: Column(
          children: [
            Expanded(
              child: LayoutPaletteThumbnail(
                document: _previewDocument(kind),
                resources: c.resources,
                kind: kind,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: _paletteLabelHeight,
              child: Center(
                child: LayoutText(
                  title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: selected ? colors.primary : colors.onSurface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _insideCanvas(Offset point) {
    final canvas = c.document.canvas;
    return Rect.fromLTWH(
      (canvas['x'] as num).toDouble(),
      (canvas['y'] as num).toDouble(),
      (canvas['width'] as num).toDouble(),
      (canvas['height'] as num).toDouble(),
    ).contains(point);
  }

  bool _dropPreview(String kind, Offset point) {
    try {
      return _dropPreviewUnsafe(kind, point);
    } catch (_) {
      return _rejectDropPreview();
    }
  }

  bool _rejectDropPreview() {
    if (_dropPreviewVisible && _startDocument != null) {
      _dropPreviewVisible = false;
      c.preview(_startDocument!);
    }
    _paletteFeedbackState.value = LayoutPaletteFeedbackState.blocked;
    _snapGuides = [];
    _seatTargetId = null;
    return false;
  }

  bool _dropPreviewUnsafe(String kind, Offset point) {
    if (!_canEdit) return false;
    if (!_insideCanvas(point)) {
      _cancelGesture();
      return false;
    }
    if (_startDocument == null) {
      if (c.error != null) c.clearError();
      _startDocument = c.document;
      c.beginGesture();
    }
    final base = _startDocument!;
    _dropFragment ??= _paletteDragFragment ?? _fragment(kind, Offset.zero);
    final roots = _dropFragment!.nodes
        .where((n) => n.parentId == null)
        .map((n) => n.id)
        .toSet();
    final combined = _dropDocument ??= moveLayoutLayers(
      base.copyWith(
        nodes: [...base.nodes, ..._dropFragment!.nodes],
        selectionUnits: [
          ...base.selectionUnits,
          ..._dropFragment!.selectionUnits,
        ],
        attachments: [...base.attachments, ..._dropFragment!.attachments],
      ),
      roots,
      toFront: true,
    );
    final snapped = snapTranslation(
      combined,
      roots,
      point.dx,
      point.dy,
      zoom: _viewportScale,
      grid: 8,
      disabled: !_snap || HardwareKeyboard.instance.isAltPressed,
    );
    if (!c.previewMove(combined, roots, dx: snapped.dx, dy: snapped.dy)) {
      return _rejectDropPreview();
    }
    _dropPreviewVisible = true;
    _paletteFeedbackState.value = LayoutPaletteFeedbackState.canvas;
    final next = c.document;
    final before = selectionBounds(combined, roots),
        after = selectionBounds(next, roots);
    _snapGuides =
        (after['x']! - before['x']! - snapped.dx).abs() < .01 &&
            (after['y']! - before['y']! - snapped.dy).abs() < .01
        ? snapped.guides
        : [];
    _seatTargetId = kind == 'Seat'
        ? _tableAt(
            point,
            _dropFragment!.nodes.single.id,
            document: next,
            feasibleOnly: true,
          )
        : null;
    return true;
  }

  void _drop(String kind, Offset point) {
    if (!_canEdit) return;
    if (!_insideCanvas(point)) {
      _cancelGesture();
      return;
    }
    if (!_dropPreview(kind, point)) {
      _cancelGesture();
      setState(() {
        c.error = 'Not enough room here. Move the object to a free area.';
        _tool = 'Select';
      });
      return;
    }
    _snapGuides = [];
    if (c.error == null && _dropFragment != null) {
      c.select(
        _dropFragment!.nodes
            .where((n) => n.parentId == null)
            .map((n) => n.id)
            .toSet(),
      );
    }
    if (kind == 'Seat' && _dropFragment != null) {
      _attachDroppedChair(_dropFragment!.nodes.single.id, point);
    }
    if (kind == 'Text' && _dropFragment != null) {
      final id = _dropFragment!.nodes.single.id;
      _startDocument = null;
      _startPointer = null;
      _gestureTool = null;
      _dropFragment = null;
      _dropDocument = null;
      _dropPreviewVisible = false;
      _beginInline(
        c.document.nodes.firstWhere((n) => n.id == id),
        insertion: true,
      );
    } else {
      _endGesture();
      setState(() => _tool = 'Select');
      _focus.requestFocus();
    }
  }

  void _handleStart(String mode, Offset point) {
    _discardDragPreview();
    _rowResizeBounds = null;
    _resizeRemovedSeats = 0;
    _focus.requestFocus();
    _gestureTool = mode;
    _startDocument = c.document;
    _startPointer = point;
    _canvasResizeBounds =
        mode.startsWith('Canvas resize ') && c.document.nodes.isNotEmpty
        ? documentBounds(c.document)
        : null;
    c.beginGesture();
    if (mode.startsWith('Insert vertex ') && c.selection.length == 1) {
      final node = c.document.nodes.firstWhere(
        (n) => c.selection.contains(n.id),
      );
      final local = transformPoint(
        inverseMatrix(worldMatrix(c.document, node)),
        point.dx,
        point.dy,
      );
      final segment = int.parse(mode.substring('Insert vertex '.length));
      try {
        final next = insertPathVertex(
          c.document,
          node.id,
          segment,
          local[0],
          local[1],
          protectedSeatIds: c.protectedSeatIds?.call() ?? const {},
        );
        if (c.preview(next)) {
          _startDocument = c.document;
          _gestureTool = 'Vertex ${segment + 1}';
        }
      } catch (error) {
        c.cancelGesture();
        c.error = error.toString();
      }
    }
  }

  Offset _drawingPoint(Offset point, {Offset? anchor}) {
    final canvas = c.document.canvas;
    var next = point;
    if (HardwareKeyboard.instance.isShiftPressed && anchor != null) {
      final delta = point - anchor;
      final angle =
          (math.atan2(delta.dy, delta.dx) / (math.pi / 4)).round() *
          math.pi /
          4;
      next = anchor + Offset(math.cos(angle), math.sin(angle)) * delta.distance;
    } else if (_snap && !HardwareKeyboard.instance.isAltPressed) {
      next = Offset((point.dx / 8).round() * 8.0, (point.dy / 8).round() * 8.0);
    }
    return Offset(
      next.dx.clamp(
        (canvas['x'] as num).toDouble(),
        (canvas['x'] as num).toDouble() + (canvas['width'] as num),
      ),
      next.dy.clamp(
        (canvas['y'] as num).toDouble(),
        (canvas['y'] as num).toDouble() + (canvas['height'] as num),
      ),
    );
  }

  void _drawHover(Offset point) {
    if (_pathPoints.isEmpty) return;
    final anchor = Offset(_pathPoints.last[0], _pathPoints.last[1]);
    final next = _drawingPoint(point, anchor: anchor);
    if (_pathHover == next) return;
    _pathHover = next;
    _previewPath();
  }

  void _addVertex(Offset point) {
    if (!_canEdit) return;
    final anchor = _pathPoints.isEmpty
        ? null
        : Offset(_pathPoints.last[0], _pathPoints.last[1]);
    final next = _drawingPoint(point, anchor: anchor);
    if (anchor != null && (next - anchor).distance < 1 / _viewportScale) return;
    if (_tool == 'Polygon' &&
        _pathPoints.length >= 3 &&
        (next - Offset(_pathPoints.first[0], _pathPoints.first[1])).distance <=
            10 / _viewportScale) {
      _finishPath();
      return;
    }
    _pathBase ??= c.document;
    _pathId ??= newLayoutId();
    if (_pathPoints.isEmpty) {
      c.beginGesture();
      c.select({});
    }
    _pathPoints.add([next.dx, next.dy]);
    _pathHover = null;
    _previewPath(includeHover: false);
    if (['Line', 'Arrow', 'Polyline'].contains(_tool) &&
        _pathPoints.length == 2) {
      _finishPath();
    } else {
      setState(() {});
    }
  }

  void _previewPath({bool includeHover = true}) {
    final points = [
      ..._pathPoints,
      if (includeHover && _pathHover != null) [_pathHover!.dx, _pathHover!.dy],
    ];
    if (points.length < 2) {
      c.preview(_pathBase!);
      return;
    }
    final shape = _polygonTool && points.length >= 3
        ? 'polygon'
        : _tool == 'Line'
        ? 'line'
        : _tool == 'Arrow'
        ? 'arrow'
        : 'polyline';
    if (_tool == 'Polyline' &&
        (Offset(points.first[0], points.first[1]) -
                    Offset(points.last[0], points.last[1]))
                .distance <
            0.01) {
      return;
    }
    final node = _tool == 'Polyline'
        ? zigzagLine(
            points.first[0],
            points.first[1],
            points.last[0],
            points.last[1],
            id: _pathId,
            style: const {
              'fill': '#00000000',
              'stroke': '#334155FF',
              'strokeWidth': 2,
            },
          )
        : shapeFromPoints(
            shape,
            points,
            id: _pathId,
            style: {
              'fill': shape == 'polygon' ? '#CBD5E1FF' : '#00000000',
              'stroke': '#334155FF',
              'strokeWidth': 2,
            },
            properties: const {},
          );
    c.preview(
      moveLayoutLayers(
        _pathBase!.copyWith(nodes: [..._pathBase!.nodes, node]),
        {node.id},
        toFront: true,
      ),
    );
  }

  void _finishPath() {
    if (_pathPoints.length < (_tool == 'Polygon' ? 3 : 2)) return;
    _previewPath(includeHover: false);
    if (c.error != null) return;
    c.commitGesture();
    if (_pathId != null && c.document.nodes.any((n) => n.id == _pathId)) {
      c.select({_pathId!});
    }
    _pathPoints.clear();
    _pathHover = null;
    _pathBase = null;
    _pathId = null;
    setState(() => _tool = 'Select');
  }

  Widget _canvasNotice() {
    final error = c.error;
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Semantics(
        liveRegion: true,
        child: Material(
          key: const ValueKey('canvas-notice'),
          color: error != null ? colors.errorContainer : colors.surface,
          elevation: 2,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(
              left: 12,
              top: 4,
              bottom: 4,
              right: 4,
            ),
            child: Row(
              children: [
                Icon(
                  error != null ? Icons.info_outline : Icons.undo,
                  size: 18,
                  color: error != null
                      ? colors.onErrorContainer
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: LayoutText(
                    error ??
                        'Seats removed: $_resizeRemovedSeats. Undo restores them.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: error != null
                          ? colors.onErrorContainer
                          : colors.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: VenueLayoutStrings.text(context, 'Dismiss'),
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() {
                    if (error != null) {
                      c.clearError();
                    } else {
                      _resizeRemovedSeats = 0;
                    }
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copyStyle() {
    if (c.selection.isEmpty) return;
    setState(
      () => _copiedAppearance = captureLayoutAppearance(
        c.document,
        c.selection.first,
      ),
    );
  }

  void _pasteStyle() {
    if (_copiedAppearance == null || !_canEdit) return;
    c.apply(
      applyLayoutAppearance(c.document, c.selection, _copiedAppearance!),
      label: 'Paste style',
    );
  }

  Future<void> _contextMenu(Offset world, Offset global) async {
    if (!_canEdit || _inlineId != null) return;
    final hit = _hitAt(world);
    if (hit != null) {
      final target = _selectionTarget(hit);
      if (!c.selection.contains(target)) c.select({target});
      setState(() => _canvasSelected = false);
    } else {
      if (!_insideCanvas(world)) return;
      c.select({});
      setState(() => _canvasSelected = true);
    }
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(global);
    PopupMenuItem<String> item(
      String value,
      String label,
      IconData icon, {
      bool enabled = true,
    }) => PopupMenuItem(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 12),
          LayoutText(label),
        ],
      ),
    );
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(local.dx, local.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: hit == null
          ? [
              item('canvas', 'Canvas settings', Icons.aspect_ratio),
              if (widget.onImportBackground != null)
                item(
                  'background',
                  'Upload background image',
                  Icons.upload_file_outlined,
                ),
            ]
          : [
              if (c.automaticChairTargets.isNotEmpty)
                item(
                  'automaticChair',
                  '${VenueLayoutStrings.text(context, 'Reset placement')} (${c.automaticChairTargets.length})',
                  Icons.restart_alt,
                ),
              if (c.document.nodes.any((n) => n.id == hit && n.kind == 'seat'))
                item(
                  'selectSeat',
                  'Select this seat',
                  Icons.event_seat_outlined,
                ),
              item('style', 'Style', Icons.palette_outlined),
              item('copyStyle', 'Copy style', Icons.format_paint_outlined),
              item(
                'pasteStyle',
                'Paste style',
                Icons.content_paste,
                enabled: _copiedAppearance != null,
              ),
              const PopupMenuDivider(),
              item('duplicate', 'Duplicate', Icons.copy_outlined),
              item('front', 'Bring to front', Icons.flip_to_front),
              item('back', 'Send to back', Icons.flip_to_back),
              const PopupMenuDivider(),
              item('delete', 'Delete', Icons.delete_outline),
            ],
    );
    if (!mounted || !_canEdit) return;
    switch (action) {
      case 'selectSeat':
        if (hit != null) c.select({hit});
        _focus.requestFocus();
      case 'automaticChair':
        c.restoreAutomaticChairPositions(c.automaticChairTargets);
      case 'style':
        await showLayoutStyleDialog(context, c);
      case 'copyStyle':
        _copyStyle();
      case 'pasteStyle':
        _pasteStyle();
      case 'duplicate':
        c.duplicateSelection();
      case 'front':
        c.apply(
          moveLayoutLayers(c.document, c.selection, toFront: true),
          label: 'Bring to front',
        );
      case 'back':
        c.apply(
          moveLayoutLayers(c.document, c.selection, toFront: false),
          label: 'Send to back',
        );
      case 'delete':
        c.deleteSelection();
      case 'background':
        await widget.onImportBackground?.call();
    }
  }

  Widget _inspector() => _gesturePanel('inspector', _buildInspector);

  Widget _buildInspector() {
    if (_globalStyleOpen.value && widget.interactionEnabled) {
      return LayoutGlobalStylePanel(
        key: _globalStyleKey,
        controller: c,
        onClose: _closeGlobalStyle,
        globalFontPickerBuilder: widget.globalFontPickerBuilder,
      );
    }
    if (!widget.interactionEnabled) {
      if (widget.inspectorOverride != null) return widget.inspectorOverride!;
      final selected = c.document.nodes.where(
        (n) => _viewSelection.contains(n.id),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selected.isEmpty)
              const LayoutText('Select a seat to view its details.'),
            for (final node in selected)
              if (widget.inspectorBuilder != null)
                widget.inspectorBuilder!(context, node),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('inspector-plan-style'),
          leading: const Icon(Icons.palette_outlined),
          title: const LayoutText('Plan style'),
          onTap: !_canEdit ? null : () => (_globalStyleOpen.value = true),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutInspector(
            controller: c,
            onClearSelection: _clearSelection,
            canvasSelected: _editingCanvas,
            backgroundSelected: _editingBackground,
            onSelectBackground: () => _selectBackground(),
            cornerPivot: _cornerPivot,
            onPivotChanged: (v) => setState(() => _cornerPivot = v),
            hostBuilder: widget.inspectorBuilder,
            readOnlyLabelNodeIds: widget.readOnlyLabelNodeIds,
            onRenameNode: widget.onRenameNode,
            fontPickerBuilder: widget.fontPickerBuilder,
            globalFontPickerBuilder: widget.globalFontPickerBuilder,
            onOpenGlobalStyle: () => _globalStyleOpen.value = true,
            onImportBackground: widget.onImportBackground,
            onCopyStyle: c.selection.isEmpty ? null : _copyStyle,
            onPasteStyle: _copiedAppearance == null || !_canEdit
                ? null
                : _pasteStyle,
          ),
        ),
      ],
    );
  }

  List<Widget> _pointerTools() => [
    for (final entry in <String, IconData>{
      'Select': Icons.near_me_outlined,
      'Pan': Icons.pan_tool_outlined,
    }.entries)
      IconButton(
        key: ValueKey('layout-tool-${entry.key}'),
        tooltip: VenueLayoutStrings.text(context, entry.key),
        isSelected: _tool == entry.key,
        style: IconButton.styleFrom(
          backgroundColor: _tool == entry.key
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
        ),
        onPressed: () {
          _cancelGesture();
          setState(() => _tool = entry.key);
        },
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(entry.value, size: 20),
            const SizedBox(width: 6),
            LayoutText(entry.key),
          ],
        ),
      ),
  ];

  void _insertFromMobileLibrary(String kind) {
    if (!_canEdit) return;
    _cancelGesture();
    setState(() => _tool = kind);
    if (_surfaceTool || _polygonTool) {
      _focus.requestFocus();
      return;
    }
    // Try the centre first, then nearby positions through the normal collision
    // and history boundary. Repeated taps must not stack seats or tables.
    final canvas = c.document.canvas;
    final x = (canvas['x'] as num).toDouble();
    final y = (canvas['y'] as num).toDouble();
    final width = (canvas['width'] as num).toDouble();
    final height = (canvas['height'] as num).toDouble();
    final centre = Offset(x + width / 2, y + height / 2);
    final candidates =
        [
          for (var row = 0; row < 5; row++)
            for (var column = 0; column < 5; column++)
              Offset(
                x + width * (column + .5) / 5,
                y + height * (row + .5) / 5,
              ),
        ]..sort(
          (a, b) => (a - centre).distanceSquared.compareTo(
            (b - centre).distanceSquared,
          ),
        );
    final occupiedSeats = [
      for (final seat in c.document.nodes.where((n) => n.kind == 'seat'))
        nodeBounds(c.document, seat),
    ];
    for (final point in candidates) {
      if (occupiedSeats.any(
        (b) => Rect.fromLTWH(
          b['x']!,
          b['y']!,
          b['width']!,
          b['height']!,
        ).contains(point),
      )) {
        continue;
      }
      if (_dropPreview(kind, point)) {
        _drop(kind, point);
        return;
      }
    }
    _cancelGesture();
    setState(() {
      _tool = kind;
      c.error = 'No free space found. Tap the plan to choose a position.';
    });
  }

  Future<void> _mobilePanel({bool library = false, bool canvas = false}) async {
    if (canvas) {
      _cancelGesture();
      c.select({});
      setState(() {
        _tool = 'Select';
        _canvasSelected = true;
      });
    }
    final kind = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: StatefulBuilder(
          builder: (context, setSheetState) => AnimatedBuilder(
            animation: Listenable.merge([c, _globalStyleOpen]),
            builder: (context, _) => library
                ? widget.libraryOverride ??
                      _buildPalette(
                        onChoose: (kind) => Navigator.pop(context, kind),
                        onSearch: (value) =>
                            setSheetState(() => _librarySearch = value),
                      )
                : _inspector(),
          ),
        ),
      ),
    );
    if (mounted && kind != null) _insertFromMobileLibrary(kind);
  }

  Widget _mobileToolbar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.toolbarPrefix != null || widget.toolbarTrailing != null)
            Row(
              children: [
                Expanded(
                  child: widget.toolbarPrefix ?? const SizedBox.shrink(),
                ),
                if (widget.toolbarTrailing != null) ...[
                  const SizedBox(width: 4),
                  widget.toolbarTrailing!,
                ],
              ],
            ),
          Row(
            children: [
              if (widget.toolbarLeading != null) widget.toolbarLeading!,
              if (widget.interactionEnabled) ...[
                PopupMenuButton<String>(
                  key: const ValueKey('layout-mobile-pointer-tool'),
                  tooltip: VenueLayoutStrings.text(context, _tool),
                  icon: Icon(
                    _tool == 'Pan'
                        ? Icons.pan_tool_outlined
                        : Icons.near_me_outlined,
                  ),
                  initialValue: _tool,
                  onSelected: (tool) {
                    _cancelGesture();
                    setState(() => _tool = tool);
                  },
                  itemBuilder: (context) => [
                    for (final tool in ['Select', 'Pan'])
                      PopupMenuItem(value: tool, child: LayoutText(tool)),
                  ],
                ),
                IconButton(
                  tooltip: VenueLayoutStrings.text(context, 'Undo'),
                  onPressed: c.canUndo && _canEdit ? c.undo : null,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: VenueLayoutStrings.text(context, 'Redo'),
                  onPressed: c.canRedo && _canEdit ? c.redo : null,
                  icon: const Icon(Icons.redo),
                ),
              ],
              const Spacer(),
              if (_canEdit || widget.libraryOverride != null)
                IconButton(
                  key: const ValueKey('layout-mobile-library'),
                  tooltip: VenueLayoutStrings.text(
                    context,
                    widget.libraryOverride != null ? 'Tables' : 'Insert',
                  ),
                  onPressed: () => _mobilePanel(library: true),
                  icon: Icon(
                    widget.libraryOverride != null
                        ? Icons.table_restaurant_outlined
                        : Icons.add,
                  ),
                ),
              IconButton(
                tooltip: VenueLayoutStrings.text(
                  context,
                  widget.interactionEnabled
                      ? 'Properties and layers'
                      : 'Seat details',
                ),
                onPressed: () => _mobilePanel(),
                icon: const Icon(Icons.tune),
              ),
              if (widget.interactionEnabled)
                PopupMenuButton<String>(
                  key: const ValueKey('layout-mobile-settings'),
                  onSelected: (value) {
                    if (value == 'canvas') _mobilePanel(canvas: true);
                    if (value == 'snap') setState(() => _snap = !_snap);
                    if (value == 'grid') setState(() => _showGrid = !_showGrid);
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'canvas',
                      enabled: _canEdit,
                      child: const LayoutText('Canvas size'),
                    ),
                    if (_canEdit)
                      CheckedPopupMenuItem(
                        value: 'snap',
                        checked: _snap,
                        child: const LayoutText('Snap'),
                      ),
                    CheckedPopupMenuItem(
                      value: 'grid',
                      checked: _showGrid,
                      child: const LayoutText('Grid'),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([c, _globalStyleOpen]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, size) {
        final wide = size.maxWidth >= 900;
        final mobile = size.maxWidth < 700;
        // Unfocusing an inspector field must keep keyboard events in the
        // editor, including when the pointer lands on a non-focusable heading.
        return FocusScope(
          onKeyEvent: (_, event) {
            if (_historyKey(event) == KeyEventResult.handled) {
              return KeyEventResult.handled;
            }
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape &&
                !_editingText) {
              if (!widget.interactionEnabled) return KeyEventResult.ignored;
              if (_globalStyleOpen.value) {
                _closeGlobalStyle();
              } else {
                _clearSelection();
              }
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            children: [
              Material(
                key: const ValueKey('layout-editor-toolbar'),
                color: Theme.of(context).colorScheme.surface,
                child: mobile
                    ? _mobileToolbar()
                    : ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    if (widget.toolbarPrefix != null)
                                      widget.toolbarPrefix!,
                                    const SizedBox(width: 8),
                                    if (widget.interactionEnabled)
                                      ..._pointerTools(),
                                    const SizedBox(width: 8),
                                    if (widget.toolbarLeading != null)
                                      widget.toolbarLeading!,
                                    if (widget.interactionEnabled)
                                      IconButton(
                                        tooltip: VenueLayoutStrings.text(
                                          context,
                                          'Undo',
                                        ),
                                        onPressed: c.canUndo && _canEdit
                                            ? c.undo
                                            : null,
                                        icon: const Icon(Icons.undo),
                                      ),
                                    if (widget.interactionEnabled)
                                      IconButton(
                                        tooltip: VenueLayoutStrings.text(
                                          context,
                                          'Redo',
                                        ),
                                        onPressed: c.canRedo && _canEdit
                                            ? c.redo
                                            : null,
                                        icon: const Icon(Icons.redo),
                                      ),
                                    if (!wide &&
                                        (_canEdit ||
                                            widget.libraryOverride != null))
                                      FilledButton.tonalIcon(
                                        onPressed: _library,
                                        icon: const Icon(Icons.add),
                                        label: LayoutText(
                                          widget.libraryOverride != null
                                              ? 'Tables'
                                              : 'Insert',
                                        ),
                                      ),
                                    const SizedBox(width: 12),
                                    const SizedBox(width: 16),
                                    if (_canEdit)
                                      Tooltip(
                                        message: VenueLayoutStrings.text(
                                          context,
                                          'Snap to objects, 8-unit grid and 15° angles. Hold Alt to bypass.',
                                        ),
                                        child: FilterChip(
                                          label: const LayoutText('Snap'),
                                          selected: _snap,
                                          onSelected: (v) =>
                                              setState(() => _snap = v),
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    if (widget.interactionEnabled)
                                      Tooltip(
                                        message: VenueLayoutStrings.text(
                                          context,
                                          'Show the grid (G). Grid visibility does not change snapping.',
                                        ),
                                        child: FilterChip(
                                          avatar: const Icon(
                                            Icons.grid_4x4,
                                            size: 18,
                                          ),
                                          label: const LayoutText('Grid'),
                                          selected: _showGrid,
                                          onSelected: (v) =>
                                              setState(() => _showGrid = v),
                                        ),
                                      ),
                                    if (!wide)
                                      IconButton(
                                        tooltip: VenueLayoutStrings.text(
                                          context,
                                          widget.interactionEnabled
                                              ? 'Properties and layers'
                                              : 'Seat details',
                                        ),
                                        onPressed: () =>
                                            showModalBottomSheet<void>(
                                              context: context,
                                              isScrollControlled: true,
                                              builder: (context) => SizedBox(
                                                height:
                                                    MediaQuery.sizeOf(
                                                      context,
                                                    ).height *
                                                    .8,
                                                child: AnimatedBuilder(
                                                  animation: Listenable.merge([
                                                    c,
                                                    _globalStyleOpen,
                                                  ]),
                                                  builder: (context, _) =>
                                                      _inspector(),
                                                ),
                                              ),
                                            ),
                                        icon: const Icon(Icons.tune),
                                      ),
                                    if (widget.toolbarTrailing == null &&
                                        (widget.interactionEnabled ||
                                            c.readOnly ||
                                            c.dirty))
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: LayoutText(
                                          c.dirty
                                              ? 'Unsaved changes'
                                              : !_canEdit
                                              ? 'Read only'
                                              : 'Saved',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelMedium,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (widget.interactionEnabled)
                                TextButton.icon(
                                  key: const ValueKey('edit-canvas'),
                                  label: const LayoutText('Canvas size'),
                                  icon: const Icon(
                                    Icons.aspect_ratio,
                                    size: 20,
                                  ),
                                  onPressed: !_canEdit
                                      ? null
                                      : () {
                                          _cancelGesture();
                                          c.select({});
                                          setState(() {
                                            _tool = 'Select';
                                            _canvasSelected = true;
                                          });
                                          _focus.requestFocus();
                                          if (!wide) {
                                            showModalBottomSheet<void>(
                                              context: context,
                                              isScrollControlled: true,
                                              builder: (context) => SizedBox(
                                                height:
                                                    MediaQuery.sizeOf(
                                                      context,
                                                    ).height *
                                                    .8,
                                                child: AnimatedBuilder(
                                                  animation: Listenable.merge([
                                                    c,
                                                    _globalStyleOpen,
                                                  ]),
                                                  builder: (context, _) =>
                                                      _inspector(),
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                ),
                              if (widget.toolbarTrailing != null)
                                widget.toolbarTrailing!,
                            ],
                          ),
                        ),
                      ),
              ),
              const Divider(height: 1),
              if (!wide &&
                  !mobile &&
                  _libraryOpen &&
                  (_canEdit || widget.libraryOverride != null))
                SizedBox(
                  height: 240,
                  child: widget.libraryOverride ?? _palette(),
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide &&
                        (_canEdit || widget.libraryOverride != null)) ...[
                      Material(
                        key: const ValueKey('layout-editor-tool-sidebar'),
                        color: layoutPanelColor(context),
                        child: SizedBox(
                          width: 232,
                          child: widget.libraryOverride ?? _palette(),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.canvasHeader != null)
                            ColoredBox(
                              color: layoutWorkspaceColor(context),
                              child: widget.canvasHeader!,
                            ),
                          Expanded(
                            child: ColoredBox(
                              color: layoutWorkspaceColor(context),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Focus(
                                      focusNode: _focus,
                                      onKeyEvent: _key,
                                      // Keyboard focus can move when inspector controls
                                      // rebuild. Pointer cancellation and Escape own
                                      // gesture rollback, not incidental focus changes.
                                      child: Semantics(
                                        container: true,
                                        explicitChildNodes: true,
                                        label: VenueLayoutStrings.text(
                                          context,
                                          widget.interactionEnabled
                                              ? 'Layout canvas. Select an object, then use arrow keys to move. Shift moves ten steps. Escape cancels.'
                                              : _viewHint,
                                        ),
                                        child: LayoutSceneSurface(
                                          retainPendingTextPreview:
                                              _canEdit ||
                                              widget.nativeTextPreview,
                                          key: ValueKey(_templateViewport),
                                          document: c.document,
                                          backgroundSelected:
                                              _canEdit && _editingBackground,
                                          canvasSelected:
                                              _canEdit &&
                                              _editingCanvas &&
                                              !c.readOnly &&
                                              !c.saving,
                                          inlineNode: _inlineId == null
                                              ? null
                                              : c.document.nodes
                                                    .where(
                                                      (n) => n.id == _inlineId,
                                                    )
                                                    .firstOrNull,
                                          inlineTextStyleBuilder:
                                              widget.inlineTextStyleBuilder,
                                          onInlineSubmit: _finishInline,
                                          onInlineCancel: () =>
                                              _finishInline(null),
                                          onInlineUndo: () =>
                                              _inlineHistory(false),
                                          onInlineRedo: () =>
                                              _inlineHistory(true),
                                          onDoubleTapAt:
                                              _canEdit && _tool == 'Select'
                                              ? _doubleTap
                                              : null,
                                          animate:
                                              !c.gestureActive &&
                                              widget.inlineTextStyleBuilder ==
                                                  null,
                                          marquee:
                                              _marquee != null &&
                                                  _marqueeEnd != null
                                              ? Rect.fromPoints(
                                                  _marquee!,
                                                  _marqueeEnd!,
                                                )
                                              : null,
                                          resources: c.resources,
                                          presentation: {
                                            ...widget.seatPresentation,
                                            ...widget.capacityPresentation,
                                          },
                                          showSeatSelectionChecks: false,
                                          selected: widget.interactionEnabled
                                              ? c.selection
                                              : _viewSelection,
                                          selectableIds:
                                              widget.interactionEnabled
                                              ? null
                                              : widget.viewSelectableIds,
                                          highlightedIds: {
                                            ...c.hoveredIds,
                                            ?_seatTargetId,
                                          },
                                          warningIds: c.placementWarningIds,
                                          blockedPlacementHulls:
                                              _blockedPlacementHulls,
                                          snapGuides: _snapGuides,
                                          showGrid:
                                              _canEdit &&
                                              (_surfaceTool
                                                  ? _surfaceBrush != null
                                                  : _showGrid),
                                          gridOrigin:
                                              _surfaceTool &&
                                                  _surfaceBrush != null
                                              ? Offset(
                                                  _surfaceBrush!.originX,
                                                  _surfaceBrush!.originY,
                                                )
                                              : Offset.zero,
                                          gridStep: _surfaceTool
                                              ? _surfaceModuleSize
                                              : 8,
                                          onViewportScaleChanged: (value) =>
                                              _viewportScale = value,
                                          transientForegroundIds:
                                              c.gestureActive
                                              ? (_dropFragment != null
                                                    ? _dropFragment!.nodes
                                                          .map((n) => n.id)
                                                          .toSet()
                                                    : layoutSubtree(
                                                        c.document,
                                                        c.selection,
                                                      ))
                                              : const {},
                                          pan: _tool == 'Pan' || !_canEdit,
                                          touchPanOnEmpty: _tool == 'Select',
                                          onSelectDown: _selectDown,
                                          onContextMenu:
                                              (!_canEdit || _tool != 'Select')
                                              ? null
                                              : _contextMenu,
                                          onTap: !_canEdit && _tool == 'Pan'
                                              ? null
                                              : [
                                                  'Line',
                                                  'Arrow',
                                                  'Polyline',
                                                  'Polygon',
                                                  'Draw table',
                                                  'Draw bar',
                                                ].contains(_tool)
                                              ? null
                                              : _tap,
                                          onPointTap:
                                              [
                                                'Line',
                                                'Arrow',
                                                'Polyline',
                                                'Polygon',
                                                'Draw table',
                                                'Draw bar',
                                              ].contains(_tool)
                                              ? _tap
                                              : null,
                                          onHover: _pathPoints.isNotEmpty
                                              ? _drawHover
                                              : null,
                                          pathPoints: _pathPoints
                                              .map((p) => Offset(p[0], p[1]))
                                              .toList(),
                                          onDragStart: _canEdit
                                              ? _dragStart
                                              : null,
                                          onDragUpdate: _canEdit
                                              ? _dragUpdate
                                              : null,
                                          onDragEnd: _canEdit
                                              ? _endGesture
                                              : null,
                                          onDragCancel: () {
                                            if (_startDocument != null ||
                                                _marquee != null) {
                                              _cancelGesture();
                                            }
                                          },
                                          onHandleStart:
                                              (!_canEdit || _inlineId != null)
                                              ? null
                                              : _handleStart,
                                          onDropPreview: _canEdit
                                              ? _dropPreview
                                              : null,
                                          onDrop: !_canEdit ? null : _drop,
                                          onDropCancel: _cancelGesture,
                                          onDoubleTap: _pathPoints.isNotEmpty
                                              ? _finishPath
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_pathPoints.isNotEmpty || _surfaceTool)
                                    Positioned(
                                      top: 12,
                                      left: 16,
                                      right: 16,
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: Material(
                                          elevation: 2,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surface,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 4,
                                            ),
                                            child: Wrap(
                                              spacing: 8,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                if (_surfaceTool) ...[
                                                  LayoutText(
                                                    _tool == 'Draw bar'
                                                        ? 'Narrow bar modules'
                                                        : 'One cell = one table for 4',
                                                  ),
                                                ],
                                                if (!_surfaceTool)
                                                  LayoutText(
                                                    '${_pathPoints.length} vertices. Tap to add; Enter to finish.',
                                                  ),
                                                if (!_surfaceTool)
                                                  TextButton(
                                                    onPressed: _finishPath,
                                                    child: const LayoutText(
                                                      'Finish path',
                                                    ),
                                                  ),
                                                TextButton(
                                                  onPressed: () {
                                                    _cancelGesture();
                                                    setState(() {});
                                                  },
                                                  child: const LayoutText(
                                                    'Cancel path',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (widget.canvasBottomOverlay != null)
                                    Positioned(
                                      left: 12,
                                      right: 12,
                                      bottom: 20,
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child: widget.canvasBottomOverlay!,
                                      ),
                                    ),
                                  if (c.error != null ||
                                      _resizeRemovedSeats > 0)
                                    Positioned(
                                      left: 16,
                                      right: 16,
                                      bottom: 16,
                                      child: Align(
                                        alignment: Alignment.bottomCenter,
                                        child: _canvasNotice(),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (wide) ...[
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 280,
                        child: Material(
                          color: layoutPanelColor(context),
                          child: _inspector(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: widget.footerTrailing == null
                        ? 0
                        : (mobile ? 48 : 24),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.footerTrailing == null ? 0 : 48,
                        ),
                        child: Align(
                          alignment: Alignment.center,
                          child: LayoutText(
                            _editingBackground
                                ? 'Background image'
                                : mobile
                                ? '${widget.interactionEnabled ? c.selection.length : _viewSelection.length} selected'
                                : !widget.interactionEnabled
                                ? _viewHint
                                : _seatTargetId != null
                                ? 'Release to attach chair to table.'
                                : _editingCanvas
                                ? 'Canvas selected. Drag an edge or corner to resize. Escape exits.'
                                : _tool == 'Select' &&
                                      c.selection.length == 1 &&
                                      c.document.nodes.any(
                                        (n) =>
                                            c.selection.contains(n.id) &&
                                            n.kind == 'table' &&
                                            const [
                                              'round',
                                              'circle',
                                            ].contains(n.properties['shape']),
                                      )
                                ? 'Round table. Hold Shift to resize into an ellipse.'
                                : _tool == 'Select'
                                ? '${c.selection.length} selected · Shift-click adds · Alt-click selects a child'
                                : _tool == 'Pan'
                                ? 'Drag to pan. Pinch or scroll to zoom.'
                                : _surfaceTool
                                ? (_tool == 'Draw bar'
                                      ? 'Drag to join narrow bar modules. Release finishes. Escape cancels.'
                                      : 'Drag across cells to join table modules. One cell is a table for 4. Release finishes. Escape cancels.')
                                : ['Line', 'Arrow', 'Polyline'].contains(_tool)
                                ? 'Click start and end, or drag to draw. Shift constrains the angle. Escape cancels.'
                                : ['Polyline', 'Polygon'].contains(_tool)
                                ? 'Click to add vertices. Double-click or Enter finishes. Backspace removes the last point.'
                                : 'Tap the plan to place $_tool.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                      if (widget.footerTrailing != null)
                        Positioned(right: 0, child: widget.footerTrailing!),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

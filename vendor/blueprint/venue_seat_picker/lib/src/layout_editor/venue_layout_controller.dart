import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

enum LayoutEditKind { edit, attachSeat }

class LayoutEditIntent {
  const LayoutEditIntent({
    this.kind = LayoutEditKind.edit,
    this.nodeId,
    this.targetId,
  });
  final LayoutEditKind kind;
  final String? nodeId, targetId;
}

/// Optional host draft state included in the very same undo transaction.
abstract class LayoutHistoryParticipant {
  Object? capture();

  /// Pure preparation with current live guards. Throwing rejects the complete
  /// command before geometry, host state or history stacks are changed.
  Object? prepare(
    VenueLayoutDocument before,
    VenueLayoutDocument after,
    Object? checkpoint, {
    required bool restoring,
    required LayoutEditIntent intent,
  });

  /// Commit a previously prepared checkpoint synchronously, without validation.
  void restore(Object? checkpoint);
}

class LayoutSelectionResult {
  const LayoutSelectionResult({
    required this.accepted,
    this.message,
    this.authoritativeSeatIds,
  });
  final bool accepted;
  final String? message;

  /// Confirmed authority recovery for requested seats only.
  final Set<String>? authoritativeSeatIds;
}

class _Checkpoint {
  _Checkpoint(
    this.document,
    this.host,
    this.selection, [
    this.resources = const {},
  ]);
  final Map<String, dynamic> resources;
  late final int documentBytes = utf8
      .encode(jsonEncode(document.toJson()))
      .length;
  static final _resourceSizes = Expando<int>();
  int get resourceBytes => _resourceSizes[resources] ??= utf8
      .encode(jsonEncode({...resources}..remove('images')))
      .length;
  final VenueLayoutDocument document;
  final List<Object?> host;
  final Set<String> selection;
}

/// A placement problem is allowed in a draft, but must be resolved before save.
class LayoutPlacementIssue {
  LayoutPlacementIssue(this.code, Iterable<String> ids)
    : nodeIds = Set<String>.unmodifiable(ids);
  final String code;
  final Set<String> nodeIds;
}

// Imported SVG edges may straddle the canvas by a fraction of a layout unit.
const _canvasEdgeTolerance = .5;

double _canvasOverflow(
  VenueLayoutDocument document,
  LayoutNode node,
  List<double> matrix,
) {
  final bounds = boundsOfPoints(worldHull(node, matrix));
  final canvas = document.canvas;
  final left = (canvas['x'] as num? ?? 0).toDouble();
  final top = (canvas['y'] as num? ?? 0).toDouble();
  final right = left + (canvas['width'] as num).toDouble();
  final bottom = top + (canvas['height'] as num).toDouble();
  return math.max(0.0, left - bounds['x']!) +
      math.max(0.0, top - bounds['y']!) +
      math.max(0.0, bounds['x']! + bounds['width']! - right) +
      math.max(0.0, bounds['y']! + bounds['height']! - bottom);
}

/// Backend-independent draft, selection and transactional history.
class VenueLayoutController extends ChangeNotifier {
  VenueLayoutController(
    VenueLayoutDocument document, {
    Map<String, dynamic> resources = const {},
    this.tableLabelPrefix = 'Table',
    this.protectedSeatIds,
  }) : _document = document,
       _baseline = _validatedBaseline(document),
       _resources = _snapshotResources(resources);
  static Map<String, dynamic> _snapshotResources(Map<String, dynamic> value) {
    final portable = Map<String, dynamic>.from(value)..remove('images');
    final issues = validateLayoutResources(portable);
    if (issues.isNotEmpty) {
      throw FormatException('Invalid resources: ${issues.first.reason}');
    }
    return Map<String, dynamic>.unmodifiable({
      ...frozenMap(portable),
      if (value['images'] is Map)
        'images': Map<String, dynamic>.unmodifiable(
          Map<String, dynamic>.from(value['images'] as Map),
        ),
    });
  }

  static VenueLayoutDocument _validatedBaseline(VenueLayoutDocument document) {
    final issues = validateDocument(document);
    if (issues.isNotEmpty) {
      throw FormatException('Invalid initial layout: ${issues.first.reason}');
    }
    return document;
  }

  final String tableLabelPrefix;
  VenueLayoutDocument _document;
  VenueLayoutDocument _baseline;
  Map<String, dynamic> _resources;
  Set<String> _selection = const {};
  Set<String> _hoveredIds = const {};
  Set<String> get hoveredIds => _hoveredIds;
  void highlightObjects(Set<String> ids) {
    final next = ids.isEmpty ? const <String>{} : layoutSubtree(_document, ids);
    if (setEquals(_hoveredIds, next)) return;
    _hoveredIds = Set.unmodifiable(next);
    notifyListeners();
  }

  final Set<String> _placementWarningIds = {};
  final List<_Checkpoint> _undo = [], _redo = [];
  final List<LayoutHistoryParticipant> _participants = [];
  final List<Object?> _baselineHost = [];
  _Checkpoint? _gesture;
  String? error;
  String? _lastClipboardPayload;
  int _pasteCount = 0;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Live host-owned booked, reserved or blocked identities. Commercial state
  /// stays outside the portable geometric document, including during undo/redo.
  Set<String> Function()? protectedSeatIds;

  bool readOnly = false;
  bool saving = false;
  VenueLayoutDocument get document => _document;
  Map<String, dynamic> get resources => _resources;
  Set<String> get selection => _selection;
  bool get canUndo => _undo.isNotEmpty && !saving && !readOnly;
  bool get canRedo => _redo.isNotEmpty && !saving && !readOnly;
  bool get dirty =>
      !sameLayoutDocument(_document, _baseline) ||
      !_hostEqual(
        _baselineHost,
        _participants.map((p) => p.capture()).toList(),
      );
  bool get gestureActive => _gesture != null;
  Set<String> get placementWarningIds => Set.unmodifiable(_placementWarningIds);

  List<LayoutPlacementIssue> get placementIssues =>
      placementIssuesFor(_document);
  List<LayoutPlacementIssue> placementIssuesFor(VenueLayoutDocument document) {
    final result = [
      for (final pair in layoutCollisions(document))
        LayoutPlacementIssue('overlap', pair),
    ];
    final canvas = document.canvas;
    final left = (canvas['x'] as num? ?? 0).toDouble();
    final top = (canvas['y'] as num? ?? 0).toDouble();
    final right = left + (canvas['width'] as num).toDouble();
    final bottom = top + (canvas['height'] as num).toDouble();
    final matrices = worldMatrices(document);
    for (final node in document.nodes) {
      if (node.kind == 'group') continue;
      if (worldHull(node, matrices[node.id]!).any(
        (p) =>
            p[0] < left - _canvasEdgeTolerance ||
            p[0] > right + _canvasEdgeTolerance ||
            p[1] < top - _canvasEdgeTolerance ||
            p[1] > bottom + _canvasEdgeTolerance,
      )) {
        result.add(LayoutPlacementIssue('outside_canvas', {node.id}));
      }
    }
    return List.unmodifiable(result);
  }

  List<LayoutPlacementIssue> showPlacementWarnings() {
    final issues = placementIssues;
    _placementWarningIds
      ..clear()
      ..addAll(issues.expand((issue) => issue.nodeIds));
    notifyListeners();
    return issues;
  }

  void clearPlacementWarnings() {
    if (_placementWarningIds.isEmpty) return;
    _placementWarningIds.clear();
    notifyListeners();
  }

  List<String> Function(VenueLayoutDocument before, VenueLayoutDocument after)?
  constraints;
  void addHistoryParticipant(LayoutHistoryParticipant participant) {
    _participants.add(participant);
    _baselineHost.add(participant.capture());
  }

  void removeHistoryParticipant(LayoutHistoryParticipant participant) {
    final i = _participants.indexOf(participant);
    if (i >= 0) {
      _participants.removeAt(i);
      _baselineHost.removeAt(i);
    }
  }

  _Checkpoint _capture() => _Checkpoint(
    _document,
    _participants.map((p) => p.capture()).toList(),
    _selection,
    _resources,
  );
  List<Object?> _prepareHost(
    VenueLayoutDocument next, {
    _Checkpoint? checkpoint,
    LayoutEditIntent intent = const LayoutEditIntent(),
  }) {
    if (checkpoint != null && checkpoint.host.length != _participants.length) {
      throw StateError('history_participants_changed');
    }
    return [
      for (var i = 0; i < _participants.length; i++)
        _participants[i].prepare(
          _document,
          next,
          checkpoint?.host[i],
          restoring: checkpoint != null,
          intent: intent,
        ),
    ];
  }

  bool _restore(_Checkpoint point) {
    try {
      if (!_accept(point.document)) return false;
      final host = _prepareHost(point.document, checkpoint: point);
      _document = point.document;
      _resources = point.resources;
      for (var i = 0; i < _participants.length; i++) {
        _participants[i].restore(host[i]);
      }
      _placementWarningIds.clear();
      _selection = point.selection;
      return true;
    } catch (e) {
      error = e is StateError ? e.message : e.toString();
      notifyListeners();
      return false;
    }
  }

  void select(Set<String> ids) {
    final existing = _document.nodes.map((n) => n.id).toSet();
    final next = ids.intersection(existing);
    if (setEquals(_selection, next)) return;
    _selection = Set.unmodifiable(next);
    notifyListeners();
  }

  bool setResources(Map<String, dynamic> value) {
    try {
      _resources = _snapshotResources(value);
      error = null;
      notifyListeners();
      return true;
    } catch (e) {
      error = e is StateError ? e.message : e.toString();
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  bool _protectedSeatsRemain(VenueLayoutDocument next) {
    final protected = protectedSeatIds?.call() ?? const <String>{};
    if (protected.isEmpty) return true;
    // A booked identity must remain an actual seat, not merely another node
    // kind reusing the same UUID. Host spot bindings target seat identities.
    final nextIds = next.nodes
        .where((node) => node.kind == 'seat')
        .map((node) => node.id)
        .toSet();
    if (_document.nodes.any(
      (n) =>
          n.kind == 'seat' &&
          protected.contains(n.id) &&
          !nextIds.contains(n.id),
    )) {
      error = 'Reserved or blocked seats prevent shrinking this table.';
      notifyListeners();
      return false;
    }
    final nextUnits = {
      for (final unit in next.selectionUnits) unit['id']: unit,
    };
    for (final unit in _document.selectionUnits) {
      final members = (unit['nodeIds'] as List).cast<String>().toSet();
      if (unit['kind'] != 'atomic' || !members.any(protected.contains)) {
        continue;
      }
      final nextUnit = nextUnits[unit['id']];
      if (nextUnit == null ||
          nextUnit['kind'] != 'atomic' ||
          !setEquals(
            members,
            (nextUnit['nodeIds'] as List).cast<String>().toSet(),
          )) {
        error = 'Reserved or blocked seats prevent changing this seat group.';
        notifyListeners();
        return false;
      }
    }
    final priorUnits = {
      for (final unit in _document.selectionUnits) unit['id']: unit,
    };
    // Check additions as well as removals: a booked standalone seat cannot
    // silently acquire paired membership, nor join a previously free unit.
    for (final unit in next.selectionUnits) {
      final members = (unit['nodeIds'] as List).cast<String>().toSet();
      if (!members.any(protected.contains)) continue;
      final prior = priorUnits[unit['id']];
      if (prior == null ||
          !setEquals(
            members,
            (prior['nodeIds'] as List).cast<String>().toSet(),
          )) {
        error = 'Reserved or blocked seats prevent changing this seat group.';
        notifyListeners();
        return false;
      }
    }
    return true;
  }

  String _issueMessage(LayoutIssue issue) =>
      issue.reason == 'bar_stool_wrong_side'
      ? 'Bar stools must stay on the guest side.'
      : '${issue.reason}: ${issue.path}';

  bool _accept(VenueLayoutDocument next) {
    if (!_protectedSeatsRemain(next)) return false;
    final issues = validateDocument(next);
    final hostIssues = constraints?.call(_document, next) ?? const <String>[];
    if (issues.isNotEmpty || hostIssues.isNotEmpty) {
      error = issues.isNotEmpty
          ? _issueMessage(issues.first)
          : hostIssues.first;
      notifyListeners();
      return false;
    }
    final changed = <String>{};
    final nextById = {for (final n in next.nodes) n.id: n};
    final priorById = {for (final n in _document.nodes) n.id: n};
    final priorWorld = worldMatrices(_document),
        nextWorld = worldMatrices(next);
    for (final node in next.nodes) {
      if (node.kind == 'group') continue;
      final overflow = _canvasOverflow(next, node, nextWorld[node.id]!);
      if (overflow <= _canvasEdgeTolerance) continue;
      final prior = priorById[node.id];
      // Old drafts can be repaired progressively, but no new or worsened
      // placement may leave the canvas, including rotation/resize/insert.
      if (prior == null ||
          overflow >
              _canvasOverflow(_document, prior, priorWorld[node.id]!) + .02) {
        error = 'Object must stay inside the canvas. Enlarge the canvas first.';
        notifyListeners();
        return false;
      }
    }
    for (final old in _document.nodes) {
      final n = nextById[old.id];
      if (n == null || !sameLayoutNode(n, old)) {
        changed.add(old.id);
      }
    }
    final oldById = {for (final n in _document.nodes) n.id: n};
    final lockedSubtrees = <String>{};
    bool? layerReindexSafe;
    for (final n in _document.nodes.where((n) => n.locked)) {
      for (LayoutNode? p = n; p != null; p = oldById[p.parentId]) {
        lockedSubtrees.add(p.id);
      }
    }
    for (final id in changed) {
      final node = oldById[id]!;
      var guarded = lockedSubtrees.contains(id);
      for (var p = oldById[node.parentId]; p != null; p = oldById[p.parentId]) {
        guarded = guarded || p.locked;
      }
      if (!guarded) continue;
      final unlocked = nextById[id];
      final onlyUnlock =
          unlocked != null &&
          node.locked &&
          !unlocked.locked &&
          jsonEncode(node.copyWith(locked: false).toJson()) ==
              jsonEncode(unlocked.toJson());
      // Layer commands can renumber sibling ranks mechanically. A locked
      // object keeps all content and its order against every unselected node.
      final selectionSubtree = layoutSubtree(_document, _selection);
      final onlyLayerReindex =
          unlocked != null &&
          !selectionSubtree.contains(id) &&
          node.z != unlocked.z &&
          jsonEncode(node.copyWith(z: 0).toJson()) ==
              jsonEncode(unlocked.copyWith(z: 0).toJson()) &&
          (layerReindexSafe ??= listEquals(
            orderedNodes(_document)
                .where((n) => !selectionSubtree.contains(n.id))
                .map((n) => n.id)
                .toList(),
            orderedNodes(next)
                .where((n) => !selectionSubtree.contains(n.id))
                .map((n) => n.id)
                .toList(),
          ));
      if (!onlyUnlock && !onlyLayerReindex) {
        error = 'Locked object: ${node.label.isEmpty ? node.kind : node.label}';
        notifyListeners();
        return false;
      }
    }
    error = null;
    return true;
  }

  // A chair edited on its own keeps its attachment and identity, but becomes
  // a manual placement so table reflow does not undo the user's adjustment.
  VenueLayoutDocument _retainManualChairPositions(VenueLayoutDocument next) {
    return next;
  }

  bool apply(
    VenueLayoutDocument next, {
    String label = 'Edit',
    Map<String, dynamic>? preparedResources,
    List<Object?>? participantCheckpoints,
    LayoutEditIntent intent = const LayoutEditIntent(),
  }) => _apply(
    next,
    label: label,
    preparedResources: preparedResources,
    participantCheckpoints: participantCheckpoints,
    intent: intent,
  );

  bool moveChairToTableSide(String seatId, String side) => _apply(
    moveTableSeatToSide(_document, seatId, side),
    label: 'Change chair side',
    retainManualChairs: false,
  );

  bool _apply(
    VenueLayoutDocument next, {
    String label = 'Edit',
    Map<String, dynamic>? preparedResources,
    bool reflowTables = true,
    bool retainManualChairs = true,
    List<Object?>? participantCheckpoints,
    LayoutEditIntent intent = const LayoutEditIntent(),
  }) {
    if (readOnly || saving) return false;
    if (retainManualChairs) next = _retainManualChairPositions(next);
    final issues = validateDocument(next);
    if (issues.isNotEmpty) {
      error = _issueMessage(issues.first);
      notifyListeners();
      return false;
    }
    late VenueLayoutDocument accepted;
    late List<Object?> preparedHost;
    Map<String, dynamic>? acceptedResources;
    try {
      if (preparedResources != null) {
        acceptedResources = _snapshotResources(preparedResources);
      }
      accepted = next;
      {}
      if (!_accept(accepted)) return false;
      preparedHost = _prepareHost(
        accepted,
        checkpoint: participantCheckpoints == null
            ? null
            : _Checkpoint(accepted, participantCheckpoints, _selection),
        intent: intent,
      );
    } catch (e) {
      error = e is StateError ? e.message : e.toString();
      notifyListeners();
      return false;
    }
    if (sameLayoutDocument(accepted, _document) &&
        _hostEqual(
          preparedHost,
          _participants.map((p) => p.capture()).toList(),
        )) {
      if (acceptedResources != null) {
        _resources = acceptedResources;
        notifyListeners();
      }
      return true;
    }
    if (_gesture == null) {
      _undo.add(_capture());
      _trimHistory();
      _redo.clear();
    }
    _document = accepted;
    if (acceptedResources != null) _resources = acceptedResources;
    for (var i = 0; i < _participants.length; i++) {
      _participants[i].restore(preparedHost[i]);
    }
    _placementWarningIds.clear();
    if (_selection.isNotEmpty) {
      final existing = _document.nodes.map((node) => node.id).toSet();
      if (!_selection.every(existing.contains)) {
        _selection = Set.unmodifiable(_selection.where(existing.contains));
      }
    }
    notifyListeners();
    return true;
  }

  void _trimHistory() {
    while (_undo.length > layoutLimits['historyCommandsMax']!) {
      _undo.removeAt(0);
    }
    var bytes = 0;
    final resourceSnapshots = Set<Map<String, dynamic>>.identity();
    for (var i = _undo.length - 1; i >= 0; i--) {
      final point = _undo[i];
      bytes += point.documentBytes;
      if (resourceSnapshots.add(point.resources)) bytes += point.resourceBytes;
      if (bytes > layoutLimits['historyBytesMax']!) {
        _undo.removeRange(0, i + 1);
        break;
      }
    }
  }

  void beginGesture() {
    if (!readOnly && !saving) {
      _gesture ??= _capture();
    }
  }

  bool preview(VenueLayoutDocument next) {
    if (_gesture == null) beginGesture();
    return _gesture != null && apply(next);
  }

  /// A constrained translation has already resolved its table chairs. Do not
  /// reflow it a second time, or replace the last valid preview with the
  /// baseline returned by an infeasible placement.
  bool previewMove(
    VenueLayoutDocument baseline,
    Set<String> ids, {
    required double dx,
    required double dy,
  }) {
    if (_gesture == null) beginGesture();
    if (_gesture == null) return false;
    final next = translateLayoutWithinCanvas(baseline, ids, dx: dx, dy: dy);
    if (identical(next, baseline) && (dx != 0 || dy != 0)) return false;
    return _apply(next, reflowTables: false);
  }

  void commitGesture() {
    final original = _gesture;
    if (original == null) return;
    _gesture = null;
    if (jsonEncode(original.document.toJson()) !=
            jsonEncode(_document.toJson()) ||
        !_hostEqual(
          original.host,
          _participants.map((p) => p.capture()).toList(),
        )) {
      _undo.add(original);
      _trimHistory();
      _redo.clear();
    }
    notifyListeners();
  }

  bool _hostEqual(List<Object?> a, List<Object?> b) {
    try {
      return jsonEncode(a) == jsonEncode(b);
    } catch (_) {
      return listEquals(a, b);
    }
  }

  void cancelGesture() {
    if (_disposed) return;
    final point = _gesture;
    if (point != null) {
      if (!_restore(point)) return;
      _gesture = null;
      error = null;
      notifyListeners();
    }
  }

  void undo() {
    if (!canUndo) return;
    cancelGesture();
    if (_gesture != null) return;
    final current = _capture(), target = _undo.last;
    if (!_restore(target)) return;
    _undo.removeLast();
    _redo.add(current);
    error = null;
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    cancelGesture();
    if (_gesture != null) return;
    final current = _capture(), target = _redo.last;
    if (!_restore(target)) return;
    _redo.removeLast();
    _undo.add(current);
    error = null;
    notifyListeners();
  }

  /// Restores an already-confirmed host baseline without replacing the draft.
  void setSavedBaseline(
    VenueLayoutDocument baseline, {
    List<Object?>? participantCheckpoints,
  }) {
    if (validateDocument(baseline).isNotEmpty) {
      throw const FormatException('Invalid saved baseline');
    }
    if (participantCheckpoints != null &&
        participantCheckpoints.length != _participants.length) {
      throw ArgumentError(
        'Baseline host checkpoint count does not match participants',
      );
    }
    _baseline = baseline;
    _baselineHost
      ..clear()
      ..addAll(participantCheckpoints ?? _participants.map((p) => p.capture()));
    notifyListeners();
  }

  void markSaved() {
    _baseline = _document;
    _baselineHost
      ..clear()
      ..addAll(_participants.map((p) => p.capture()));
    _undo.clear();
    _redo.clear();
    _gesture = null;
    notifyListeners();
  }

  /// Allocates new table names without changing existing table identities.
  VenueLayoutDocument nameInsertedTables(
    VenueLayoutDocument fragment, {
    String? defaultTablePrefix,
  }) {
    final used = _document.nodes
        .where((n) => n.kind == 'table')
        .map((n) => n.label.trim())
        .toSet();
    String allocate(String label) {
      label = label.trim();
      final numbered = RegExp(r'^(.*?)(\d+)$').firstMatch(label);
      var prefix =
          numbered?.group(1) ?? '${defaultTablePrefix ?? tableLabelPrefix} ';
      if (label.isNotEmpty && numbered == null) {
        if (used.add(label)) return label;
        prefix = '$label ';
      }
      if (prefix.trim() == 'Table' && tableLabelPrefix != 'Table') {
        prefix = '$tableLabelPrefix ';
      }
      var highest = 0;
      for (final name in used) {
        if (!name.startsWith(prefix)) continue;
        final suffix = name.substring(prefix.length);
        if (RegExp(r'^\d+$').hasMatch(suffix)) {
          highest = math.max(highest, int.parse(suffix));
        }
      }
      if (numbered != null && used.add('$prefix${numbered.group(2)}')) {
        return '$prefix${numbered.group(2)}';
      }
      var index = highest + 1;
      if (index < 2 && label.isNotEmpty && numbered == null) index = 2;
      while (!used.add('$prefix$index')) {
        index++;
      }
      return '$prefix$index';
    }

    // Document arrays are serialized by UUID, not visual order. Allocate a
    // multi-table insertion from top to bottom, then left to right.
    final matrices = worldMatrices(fragment);
    final tables = fragment.nodes.where((n) => n.kind == 'table').toList()
      ..sort((a, b) {
        final am = matrices[a.id]!, bm = matrices[b.id]!;
        final row = am[5].compareTo(bm[5]);
        if (row != 0) return row;
        final column = am[4].compareTo(bm[4]);
        return column != 0 ? column : a.id.compareTo(b.id);
      });
    final names = {for (final table in tables) table.id: allocate(table.label)};
    return fragment.copyWith(
      nodes: fragment.nodes
          .map(
            (n) => names.containsKey(n.id) ? n.copyWith(label: names[n.id]) : n,
          )
          .toList(),
    );
  }

  /// SVG import is converted once into the shared path/paint display list.
  /// The same insertion/transform/history command owns vector and bitmap nodes.
  bool insertVectorGraphic(
    LayoutVectorGraphic graphic, {
    Map<String, dynamic>? originalSource,
    String label = '',
    double? x,
    double? y,
    double? width,
    double? height,
  }) => _insertGraphic(
    'vector',
    {'type': 'vector', ...graphic.toJson()},
    graphic.width,
    graphic.height,
    originalSource: originalSource,
    label: label,
    x: x,
    y: y,
    width: width,
    height: height,
  );

  bool insertBitmapAsset(
    String assetRef, {
    String label = '',
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    final asset = (_resources['assets'] as Map?)?[assetRef];
    if (asset is! Map ||
        asset['hash'] is! String ||
        asset['width'] is! num ||
        asset['height'] is! num) {
      error = 'asset_unavailable';
      notifyListeners();
      return false;
    }
    return _insertGraphic(
      'image',
      {
        'type': 'bitmap',
        'assetRef': assetRef,
        'hash': asset['hash'],
        'crop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
      },
      (asset['width'] as num).toDouble(),
      (asset['height'] as num).toDouble(),
      label: label,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }

  bool _insertGraphic(
    String kind,
    Map<String, dynamic> graphic,
    double nativeWidth,
    double nativeHeight, {
    required String label,
    Map<String, dynamic>? originalSource,
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    {}
    final canvas = _document.canvas;
    final scale = math.min(
      1.0,
      math.min(
        (canvas['width'] as num) * .6 / nativeWidth,
        (canvas['height'] as num) * .6 / nativeHeight,
      ),
    );
    final node = LayoutNode(
      id: newLayoutId(),
      kind: kind,
      label: label,
      graphic: graphic,
      originalSource: originalSource,
      x: x ?? (canvas['x'] as num).toDouble() + (canvas['width'] as num) / 2,
      y: y ?? (canvas['y'] as num).toDouble() + (canvas['height'] as num) / 2,
      width: width ?? nativeWidth * scale,
      height: height ?? nativeHeight * scale,
    );
    final next = moveLayoutLayers(
      _document.copyWith(nodes: [..._document.nodes, node]),
      {node.id},
      toFront: true,
    );
    if (!apply(next, label: 'Insert graphic')) return false;
    select({node.id});
    return true;
  }

  void insert(
    VenueLayoutDocument fragment, {
    double dx = 0,
    double dy = 0,
    bool fitWithinCanvas = false,
  }) {
    final contextual =
        (!sameLayoutValue(fragment.styles, _document.styles) ||
            !sameLayoutValue(
              fragment.seatingDefaults,
              _document.seatingDefaults,
            ) ||
            !sameLayoutValue(fragment.textPolicy, _document.textPolicy))
        ? materializeFragmentContext(fragment)
        : fragment;
    final fresh = cloneLayout(nameInsertedTables(contextual), dx: dx, dy: dy);
    final raw = _document.toJson();
    raw['nodes'] = [
      ..._document.nodes.map((n) => n.toJson()),
      ...fresh.nodes.map((n) => n.toJson()),
    ];
    for (final key in ['attachments', 'sections', 'selectionUnits']) {
      raw[key] = [
        ...(raw[key] as List? ?? []),
        ...(fresh.toJson()[key] as List? ?? []),
      ];
    }
    final roots = fresh.nodes
        .where((n) => n.parentId == null)
        .map((n) => n.id)
        .toSet();
    var candidate = moveLayoutLayers(
      VenueLayoutDocument.fromJson(raw),
      roots,
      toFront: true,
    );
    if (fitWithinCanvas) {
      candidate = moveLayoutWithinCanvas(candidate, roots);
    }
    if (apply(candidate, label: 'Insert')) {
      select(
        fresh.nodes.where((n) => n.parentId == null).map((n) => n.id).toSet(),
      );
    }
  }

  Set<String> _subtree(Set<String> roots) {
    final ids = Set<String>.of(roots);
    var count = -1;
    while (count != ids.length) {
      count = ids.length;
      ids.addAll(
        _document.nodes.where((n) => ids.contains(n.parentId)).map((n) => n.id),
      );
    }
    return ids;
  }

  void deleteSelection() {
    final ids = _subtree(_selection), raw = _document.toJson();
    for (final unit in _document.selectionUnits) {
      final members = (unit['nodeIds'] as List).cast<String>();
      if (members.any(ids.contains) && !members.every(ids.contains)) {
        error = 'Select the entire shared object before deleting its places.';
        notifyListeners();
        return;
      }
    }
    raw['nodes'] = _document.nodes
        .where((n) => !ids.contains(n.id))
        .map((n) => n.toJson())
        .toList();
    raw['attachments'] = _document.attachments
        .where(
          (a) => !ids.contains(a['seatId']) && !ids.contains(a['targetId']),
        )
        .toList();
    raw['sections'] = _document.sections
        .where((s) => !ids.contains(s['rootId']))
        .toList();
    {}
    raw['selectionUnits'] = _document.selectionUnits
        .where((u) => !(u['nodeIds'] as List).any(ids.contains))
        .toList();
    apply(VenueLayoutDocument.fromJson(raw), label: 'Delete');
  }

  VenueLayoutDocument _selectionFragment() {
    final ids = _subtree(_selection), raw = _document.toJson();
    raw['nodes'] = _document.nodes.where((n) => ids.contains(n.id)).map((n) {
      final m = n.toJson();
      if (!ids.contains(n.parentId)) {
        if (n.kind == 'seat' && n.parentId != null)
          m['style'] = materializedNodeStyle(_document, n);
        final world = worldMatrix(_document, n);
        m['parentId'] = null;
        m['transform'] = {
          'x': world[4],
          'y': world[5],
          'rotation': math.atan2(world[1], world[0]) * 180 / math.pi,
        };
      }
      return m;
    }).toList();
    raw['attachments'] = _document.attachments
        .where((a) => ids.contains(a['seatId']) && ids.contains(a['targetId']))
        .toList();
    raw['sections'] = [];
    {}
    raw['selectionUnits'] = _document.selectionUnits
        .where((u) => (u['nodeIds'] as List).every(ids.contains))
        .toList();
    raw['presets'] = [];
    raw['background'] = null;
    return VenueLayoutDocument.fromJson(raw);
  }

  void duplicateSelection({double dx = 40, double dy = 40}) {
    if (_selection.isEmpty || readOnly || saving) return;
    final before = _document;
    insert(_selectionFragment(), dx: dx, dy: dy, fitWithinCanvas: true);
    if (identical(before, _document)) return;
    final copied = layoutSubtree(_document, _selection);
    _placementWarningIds.addAll(
      placementIssues.expand((issue) => issue.nodeIds).where(copied.contains),
    );
    notifyListeners();
  }

  /// Portable geometry only: host order, inventory and payment data never enter
  /// the system clipboard. Every insertion regenerates node and attachment IDs.
  Future<void> copySelectionToClipboard() async {
    if (_selection.isEmpty || saving) return;
    try {
      final payload = jsonEncode({
        'format': 'venue-layout-selection',
        'version': 1,
        'document': _selectionFragment().toJson(),
      });
      await Clipboard.setData(ClipboardData(text: payload));
      _lastClipboardPayload = payload;
      _pasteCount = 0;
    } catch (_) {
      if (_disposed) return;
      error = 'Unable to copy selection to the clipboard.';
      notifyListeners();
    }
  }

  void _clipboardError() {
    if (_disposed) return;
    error =
        'Clipboard does not contain a valid layout selection, or access was denied.';
    notifyListeners();
  }

  Future<void> pasteFromClipboard() async {
    if (_disposed || readOnly || saving || gestureActive) return;
    final baseline = _document;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      // An asynchronous clipboard read must not overwrite intervening edits.
      if (_disposed ||
          readOnly ||
          saving ||
          gestureActive ||
          !identical(baseline, _document)) {
        return;
      }
      final text = data?.text;
      if (text != null && text.isNotEmpty) pasteSelectionText(text);
    } catch (_) {
      _clipboardError();
    }
  }

  /// Consumes text delivered by the browser's native paste event, which does
  /// not require the separate clipboard-read permission. Returns true for a
  /// recognized selection, even if placement constraints reject its insertion.
  bool pasteSelectionText(String text) {
    if (_disposed || readOnly || saving || gestureActive || text.isEmpty) {
      return false;
    }
    final baseline = _document;
    try {
      if (utf8.encode(text).length > layoutMaxBytes) {
        throw const FormatException('Clipboard selection is too large');
      }
      final raw = jsonDecode(text);
      if (raw is! Map ||
          raw['format'] != 'venue-layout-selection' ||
          raw['version'] != 1 ||
          raw['document'] is! Map) {
        throw const FormatException('Unsupported clipboard content');
      }
      final fragment = VenueLayoutDocument.fromJson(
        Map<String, dynamic>.from(raw['document'] as Map),
      );
      final count = text == _lastClipboardPayload ? _pasteCount + 1 : 1;
      insert(
        fragment,
        dx: 40.0 * count,
        dy: 40.0 * count,
        fitWithinCanvas: true,
      );
      if (!identical(baseline, _document)) {
        _lastClipboardPayload = text;
        _pasteCount = count;
      }
      return true;
    } catch (_) {
      _clipboardError();
      return false;
    }
  }

  /// Adds/reassigns the same seat identity to an existing table assembly.
  bool attachChairToTable(String seatId, String tableId) {
    if (readOnly || saving) return false;
    try {
      final table = _document.nodes.firstWhere((n) => n.id == tableId);
      final count = _document.nodes
          .where(
            (n) => n.parentId == tableId && n.kind == 'seat' && n.id != seatId,
          )
          .length;
      if (count >= tableCapacity(table)) {
        error = 'This table has no free chair positions.';
        notifyListeners();
        return false;
      }
      final next = reflowTablesAtCanvasEdges(
        attachSeat(_document, seatId, tableId),
        {tableId},
      );
      return apply(
        next,
        label: 'Attach chair to table',
        intent: LayoutEditIntent(
          kind: LayoutEditKind.attachSeat,
          nodeId: seatId,
          targetId: tableId,
        ),
      );
    } catch (e) {
      error = e is StateError ? e.message : e.toString();
      notifyListeners();
      return false;
    }
  }

  void moveSelection(double dx, double dy) {
    try {
      _apply(
        translateLayoutWithinCanvas(_document, _selection, dx: dx, dy: dy),
        label: 'Move',
        reflowTables: false,
      );
    } catch (e) {
      error = e is StateError ? e.message : e.toString();
      notifyListeners();
    }
  }

  void rotateSelection(double degrees, {bool cornerPivot = false}) {
    try {
      apply(
        moveLayoutWithinCanvas(
          transformNodes(
            _document,
            _selection,
            rotation: degrees,
            cornerPivot: cornerPivot,
          ),
          _selection,
        ),
        label: 'Rotate',
      );
    } catch (e) {
      error = e is StateError ? e.message : e.toString();
      notifyListeners();
    }
  }

  void updateNode(LayoutNode node) {
    final previous = _document.nodes.firstWhere((n) => n.id == node.id);
    apply(
      _document.copyWith(
        nodes: [for (final n in _document.nodes) n.id == node.id ? node : n],
        attachments: node.kind != 'seat'
            ? _document.attachments
            : [
                for (final attachment in _document.attachments)
                  if (attachment['seatId'] == node.id)
                    {
                      ...attachment,
                      if (node.x != previous.x || node.y != previous.y)
                        'placement': {'mode': 'free'},
                      if (node.rotation != previous.rotation)
                        'rotationMode': 'manual',
                    }
                  else
                    attachment,
              ],
      ),
    );
  }

  /// Keep authored table labels readable using the same font advances and
  /// line-height as the portable renderer. Chair dimensions are independent.
  ({double width, double height}) constrainTableDimensions(
    LayoutNode node,
    double width,
    double height,
  ) {
    {
      return (width: width, height: height);
    }
  }

  bool resizeObject(String id, double width, double height) {
    try {
      final node = _document.nodes.firstWhere((n) => n.id == id);
      final dimensions = constrainTableDimensions(node, width, height);
      width = dimensions.width;
      height = dimensions.height;
      return apply(
        isRowAssemblyNode(node)
            ? resizeRowAssembly(_document, id, width, height)
            : isCouchNode(node)
            ? resizeCouchBody(
                _document,
                id,
                width,
                height,
                protectedSeatIds: protectedSeatIds?.call() ?? const {},
              )
            : resizeNode(
                _document,
                id,
                width,
                height,
                protectedSeatIds: protectedSeatIds?.call() ?? const {},
              ),
        label: 'Resize',
      );
    } catch (e) {
      error = e is StateError ? e.message : e.toString();
      notifyListeners();
      return false;
    }
  }

  void restoreAutomaticChairPosition(String seatId) {
    if (readOnly || saving) return;
    try {
      final protected = protectedSeatIds?.call() ?? const <String>{};
      if (protected.contains(seatId)) throw StateError('protected_spot');
      final next = setTableSeatPlacement(_document, seatId, const {
        'mode': 'automatic',
      }, protectedSeatIds: protected);
      _apply(
        next,
        label: 'Restore automatic position',
        retainManualChairs: false,
      );
    } catch (e) {
      error = e is StateError ? e.message : e.toString();
      notifyListeners();
    }
  }

  void snapChairToStandardPosition(String seatId) {
    try {
      final next = snapAttachedChairPosition(_document, seatId);
      if (!identical(next, _document)) apply(next, label: 'Move chair');
    } catch (e) {
      error = e is StateError ? e.message : e.toString();
      notifyListeners();
    }
  }

  void setTableSeating(String id, TableSeating seating) {
    try {
      apply(
        configureTableSeating(
          _document,
          id,
          seating,
          protectedSeatIds: protectedSeatIds?.call() ?? const {},
        ),
        label: 'Adjust chair layout',
      );
    } catch (e) {
      error = e is StateError ? e.message : e.toString();
      notifyListeners();
    }
  }

  void setSeatCount(String tableId, int count) {
    try {
      apply(
        isCouchNode(_document.nodes.firstWhere((n) => n.id == tableId))
            ? resizeCouchSeats(
                _document,
                tableId,
                count,
                protectedSeatIds: protectedSeatIds?.call() ?? const {},
              )
            : reflowTable(
                _document,
                tableId,
                count,
                protectedSeatIds: protectedSeatIds?.call() ?? const {},
              ),
        label: 'Seats',
      );
    } catch (e) {
      error = e is StateError ? e.message : e.toString();
      notifyListeners();
    }
  }
}

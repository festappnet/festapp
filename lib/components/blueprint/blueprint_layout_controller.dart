import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:festapp_core/eshop.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../forms/db_forms.dart';
import '../eshop/db_tickets.dart';
import 'blueprint_layout_adapter.dart';
import 'blueprint_layout_contract.dart';
import 'blueprint_layout_saver.dart';
import 'blueprint_model.dart';
import 'blueprint_seat_naming.dart';
import 'blueprint_group_binding.dart';

/// Owns only undoable commercial metadata. Live bookings and catalog stay outside
/// checkpoints; their updates never replace the portable geometry session.
class BlueprintLayoutController extends ChangeNotifier
    implements LayoutHistoryParticipant {
  BlueprintLayoutController(
      {required BlueprintModel source, BlueprintLayoutSaver? saver})
      : adapter = BlueprintLayoutAdapter(source),
        _baseline = source.layoutSnapshot ??
            (throw StateError('blueprint_layout_unavailable')),
        _draft = source.layoutSnapshot!,
        saver = saver ?? BlueprintLayoutSaver(DbForms.blueprintCommands()) {
    layout = VenueLayoutController(_draft.document,
        resources: source.layoutResources,
        protectedSeatIds: () => adapter.protectedIds(snapshot));
    layout.constraints = (before, after) {
      final previous = {for (final n in before.nodes) n.id: n};
      for (final n in after.nodes.where((n) => n.kind == 'seat')) {
        if (previous.containsKey(n.id) &&
            previous[n.id]!.label != n.label &&
            isProtected(n.id)) return ['protected_spot'];
        if (previous.containsKey(n.id) &&
            previous[n.id]?.parentId != n.parentId &&
            _commercialGroupFor(n, after) != null &&
            _commercialGroupFor(n, after) !=
                _draft.seatBindings[n.id]?.groupNodeId) {
          if (isProtected(n.id)) return ['protected_spot'];
          if (!_draft.groupProducts.containsKey(_commercialGroupFor(n, after)))
            return ['group_product_required'];
        }
      }
      return [];
    };
    _observedDocument = layout.document;
    layout.addHistoryParticipant(this);
    layout.addListener(_geometryChanged);
  }
  final BlueprintLayoutAdapter adapter;
  final BlueprintLayoutSaver saver;
  late final VenueLayoutController layout;
  late VenueLayoutDocument _observedDocument;
  BlueprintLayoutSnapshot _baseline, _draft;
  BlueprintLayoutMode mode = BlueprintLayoutMode.manage;
  final Set<String> _operationSelection = {};
  bool isBusy = false;
  Object? error;
  Map<int, ProductModel> get products => Map.unmodifiable(adapter.products);
  BlueprintLayoutSnapshot get snapshot =>
      _draft.copyWith(document: layout.document);
  Set<String> get operationSelection => Set.unmodifiable(_operationSelection);
  List<int> get selectedSpotIds => [
        for (final id in _operationSelection)
          if (_draft.seatBindings[id]?.spotId != null)
            _draft.seatBindings[id]!.spotId!
      ];
  bool get isDirty => layout.dirty;
  int? effectiveProductId(String nodeId) =>
      _draft.seatBindings[nodeId]?.productId;
  bool isProtected(String nodeId) =>
      _draft.seatBindings[nodeId] != null &&
      adapter.protected(_draft.seatBindings[nodeId]!);
  void upsertCatalogProduct(ProductModel product) {
    if (product.id == null) throw ArgumentError('catalog_product_id_required');
    adapter.products = {...adapter.products, product.id!: product};
    for (final spot in adapter.spots.values) {
      if (spot.product?.id == product.id) spot.product = product;
    }
    notifyListeners();
  }

  void refreshLive(BlueprintModel source) {
    adapter.refresh(source);
    _operationSelection.clear();
    notifyListeners();
  }

  void setMode(BlueprintLayoutMode value) {
    mode = value;
    _operationSelection.clear();
    notifyListeners();
  }

  void activateNode(String id) {
    final binding = _draft.seatBindings[id];
    if (mode == BlueprintLayoutMode.manage ||
        binding?.spotId == null ||
        binding!.blocked ||
        isBusy) return;
    if (mode == BlueprintLayoutMode.order) {
      final unit = layout.document.selectionUnits
          .where((u) => (u['nodeIds'] as List? ?? const []).contains(id));
      final ids = unit.isEmpty
          ? <String>{id}
          : Set<String>.from(unit.first['nodeIds'] as List);
      if (_operationSelection.contains(id)) {
        _operationSelection.removeAll(ids);
      } else {
        if (ids.any((node) =>
            _draft.seatBindings[node]?.spotId == null ||
            _draft.seatBindings[node]!.blocked)) return;
        _operationSelection.addAll(ids);
      }
    } else if (!_operationSelection.remove(id)) {
      if (_operationSelection.length == 2) _operationSelection.clear();
      _operationSelection.add(id);
    }
    notifyListeners();
  }

  void _requireProduct(int id) {
    final product = adapter.products[id];
    if (product == null || product.productTypeString != ProductModel.spotType)
      throw StateError('invalid_spot_product');
  }

  void _mutate(void Function() action) {
    if (layout.readOnly || isBusy) throw StateError('blueprint_read_only');
    layout.beginGesture();
    try {
      action();
      layout.commitGesture();
    } catch (_) {
      layout.cancelGesture();
      rethrow;
    }
    notifyListeners();
  }

  void assignSeatProduct(String nodeId, int productId) =>
      assignProducts({nodeId}, productId);
  void assignProducts(Set<String> nodeIds, int productId,
      {bool freeOnly = false}) {
    _requireProduct(productId);
    final bindings = nodeIds
        .map((id) =>
            _draft.seatBindings[id] ??
            (throw StateError('seat_binding_missing')))
        .toList();
    if (!freeOnly && bindings.any(adapter.protected))
      throw StateError('protected_spot');
    _mutate(() => _draft = _draft.copyWith(seatBindings: {
          ..._draft.seatBindings,
          for (final binding in bindings)
            if (!adapter.protected(binding))
              binding.nodeId: binding.copyWith(productId: productId)
        }));
  }

  void applyGroupProduct(String groupId, int productId,
          {bool freeOnly = false}) =>
      applyGroupsProduct({groupId}, productId, freeOnly: freeOnly);

  /// Update defaults and inherited assignments in one undo step. A seat whose
  /// product differs from its old table default keeps that explicit override.
  void applyGroupsProduct(Set<String> groupIds, int productId,
      {bool freeOnly = false, Set<String> additionalSeatIds = const {}}) {
    _requireProduct(productId);
    if (groupIds.isEmpty) return;
    final members = _draft.seatBindings.values
        .where((s) =>
            additionalSeatIds.contains(s.nodeId) ||
            (groupIds.contains(s.groupNodeId) &&
                s.productId == _draft.groupProducts[s.groupNodeId]))
        .toList();
    if (!freeOnly && members.any(adapter.protected))
      throw StateError('protected_spot');
    _mutate(() => _draft = _draft.copyWith(groupProducts: {
          ..._draft.groupProducts,
          for (final id in groupIds) id: productId
        }, seatBindings: {
          ..._draft.seatBindings,
          for (final s in members)
            if (!adapter.protected(s))
              s.nodeId: s.copyWith(productId: productId)
        }));
  }

  void renameCommercialNode(String nodeId, String title) {
    if (layout.readOnly || isBusy) throw StateError('blueprint_read_only');
    final value = title.trim();
    if (value.isEmpty) throw ArgumentError('name_required');
    final node = layout.document.nodes.firstWhere((n) => n.id == nodeId);
    if (!const {'seat', 'table', 'group', 'capacityArea'}.contains(node.kind))
      throw ArgumentError('not_commercial_node');
    if (node.kind == 'seat' && isProtected(nodeId))
      throw StateError('protected_spot');
    if (!layout.apply(
        layout.document.copyWith(nodes: [
          for (final n in layout.document.nodes)
            n.id == nodeId ||
                    (node.kind == 'group' &&
                        n.kind == 'table' &&
                        blueprintCommercialGroupFor(n, layout.document,
                                groupProducts: _draft.groupProducts) ==
                            nodeId)
                ? n.copyWith(label: value)
                : n
        ]),
        label: 'Rename commercial item')) {
      throw StateError(layout.error ?? 'invalid_name');
    }
  }

  void setBlocked(String nodeId, bool blocked) {
    if (isProtected(nodeId)) throw StateError('protected_spot');
    final binding = _draft.seatBindings[nodeId] ??
        (throw StateError('seat_binding_missing'));
    _mutate(() => _draft = _draft.copyWith(seatBindings: {
          ..._draft.seatBindings,
          nodeId: binding.copyWith(blocked: blocked)
        }));
  }

  void assignGroup(String nodeId, String groupId) {
    if (isProtected(nodeId)) throw StateError('protected_spot');
    final product = _draft.groupProducts[groupId] ??
        (throw StateError('group_product_required'));
    final binding = _draft.seatBindings[nodeId] ??
        (throw StateError('seat_binding_missing'));
    _mutate(() => _draft = _draft.copyWith(seatBindings: {
          ..._draft.seatBindings,
          nodeId: binding.copyWith(groupNodeId: groupId, productId: product)
        }));
  }

  String? _commercialGroupFor(LayoutNode seat, VenueLayoutDocument document) =>
      blueprintCommercialGroupFor(seat, document,
          groupProducts: _draft.groupProducts,
          currentGroupId: _draft.seatBindings[seat.id]?.groupNodeId);

  void _geometryChanged() {
    // Selection/live presentation notifications do not reconcile draft metadata.
    if (identical(_observedDocument, layout.document)) {
      notifyListeners();
      return;
    }
    final previous = {
      for (final node in _observedDocument.nodes) node.id: node
    };
    final seats = {
      for (final n in layout.document.nodes)
        if (n.kind == 'seat') n.id: n
    };
    // Geometry previews retain commercial identities. Reconcile only when the
    // seat membership, naming, ancestry or paired-selection contract changes.
    final metadataUnchanged = seats.length == _draft.seatBindings.length &&
        const DeepCollectionEquality().equals(
            _observedDocument.selectionUnits, layout.document.selectionUnits) &&
        layout.document.nodes.length == _observedDocument.nodes.length &&
        layout.document.nodes.every((node) {
          final old = previous[node.id];
          return old != null &&
              old.kind == node.kind &&
              old.parentId == node.parentId &&
              (node.kind != 'seat' || old.label == node.label);
        });
    if (metadataUnchanged) {
      _observedDocument = layout.document;
      // The public editor listens to geometry directly. Keep commercial host
      // controls stable during a gesture; commit notifies them once so dirty
      // state and draft actions become current before the next interaction.
      if (!layout.gestureActive) notifyListeners();
      return;
    }
    final bindings = <String, BlueprintSeatBinding>{};
    final groupCounts = <String, int>{};
    for (final binding in _draft.seatBindings.values) {
      final id = binding.groupNodeId;
      if (id != null && seats.containsKey(binding.nodeId))
        groupCounts[id] = (groupCounts[id] ?? 0) + 1;
    }
    for (final entry in seats.entries) {
      final current = _draft.seatBindings[entry.key];
      final parent = entry.value.parentId;
      final parentChanged = previous.containsKey(entry.key) &&
          previous[entry.key]!.parentId != parent;
      final labelChanged = previous.containsKey(entry.key) &&
          previous[entry.key]!.label != entry.value.label;
      final commercialGroup = _commercialGroupFor(entry.value, layout.document);
      final groupChanged = parentChanged &&
          commercialGroup != null &&
          commercialGroup != current?.groupNodeId;
      final unit = layout.document.selectionUnits.where(
          (u) => (u['nodeIds'] as List? ?? const []).contains(entry.key));
      final unitId = unit.isEmpty ? null : unit.first['id'] as String?;
      var newTitle = entry.value.label;
      if (current == null && commercialGroup != null) {
        final groupNode = layout.document.nodes
            .firstWhere((node) => node.id == commercialGroup);
        final nextIndex = groupCounts[commercialGroup] ?? 0;
        newTitle = blueprintSeatTitle(groupNode.label, nextIndex);
        groupCounts[commercialGroup] = nextIndex + 1;
      }
      bindings[entry.key] = current == null
          ? BlueprintSeatBinding(
              nodeId: entry.key,
              title: newTitle,
              groupNodeId: commercialGroup,
              productId: _draft.groupProducts[commercialGroup],
              selectionUnitId: unitId)
          : current.copyWith(
              title: labelChanged ? entry.value.label : current.title,
              // Visual detach preserves commercial membership. Explicit attach
              // adopts the target default, guarded before geometry is committed.
              groupNodeId: groupChanged ? commercialGroup : current.groupNodeId,
              productId: groupChanged
                  ? _draft.groupProducts[commercialGroup]
                  : current.productId,
              selectionUnitId: unitId,
              clearUnit: unitId == null);
    }
    _observedDocument = layout.document;
    _draft = _draft.copyWith(seatBindings: bindings);
    notifyListeners();
  }

  @override
  Object capture() {
    // Readers need not order bindings like the document. History compares a
    // canonical checkpoint so selection/undo cannot manufacture dirty state.
    final seats = _draft.seatBindings.keys.toList()..sort();
    final groups = _draft.groupProducts.keys.toList()..sort();
    final areas = _draft.areaBindings.keys.toList()..sort();
    return {
      'seats': [for (final id in seats) _draft.seatBindings[id]!.toJson()],
      'groups': {for (final id in groups) id: _draft.groupProducts[id]},
      'areas': [for (final id in areas) _draft.areaBindings[id]!.toJson()],
    };
  }

  @override
  void restore(Object? checkpoint) {
    _observedDocument = layout.document;
    final map = checkpoint as Map;
    _draft = _draft.copyWith(
        seatBindings: {
          for (final raw in map['seats'] as List)
            (raw as Map)['nodeId'] as String:
                BlueprintSeatBinding.fromJson(Map<String, dynamic>.from(raw))
        },
        groupProducts: Map<String, int>.from(map['groups'] as Map),
        areaBindings: {
          for (final raw in map['areas'] as List)
            (raw as Map)['nodeId'] as String:
                BlueprintAreaBinding.fromJson(Map<String, dynamic>.from(raw))
        });
    _draft = _draft.copyWith(seatBindings: {
      for (final binding in _draft.seatBindings.values)
        binding.nodeId: binding.spotId == null &&
                _baseline.seatBindings[binding.nodeId]?.spotId != null
            ? binding.copyWith(
                spotId: _baseline.seatBindings[binding.nodeId]!.spotId)
            : binding,
    });
  }

  void cancel() {
    if (isBusy || saver.pending != null) throw StateError('save_unresolved');
    layout.beginGesture();
    _draft = _baseline;
    layout.apply(_baseline.document);
    layout.commitGesture();
    layout.markSaved();
    _operationSelection.clear();
    error = null;
    notifyListeners();
  }

  Future<BlueprintLayoutSaveResult> save() async {
    if (isBusy) throw StateError('save_in_progress');
    final submitted = saver.pending?.snapshot ?? snapshot;
    if (submitted.seatBindings.values
        .any((s) => s.spotId == null && !s.blocked && s.productId == null))
      throw StateError('seat_product_required');
    if (layout.showPlacementWarnings().isNotEmpty)
      throw StateError('layout_placement_invalid');
    final request = saver.pending ??
        BlueprintLayoutSaveRequest(snapshot: submitted, baseline: _baseline);
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      final result = await saver.save(request);
      if (!result.accepted) return result;
      final confirmed = submitted.copyWith(
          blueprintId: result.blueprintId,
          revision: result.revision,
          seatBindings: {for (final s in result.seatBindings) s.nodeId: s},
          groupProducts: result.groupProducts,
          areaBindings: {for (final a in result.areaBindings) a.nodeId: a});
      final current = snapshot;
      final sameDraft =
          jsonEncode(current.toJson()) == jsonEncode(submitted.toJson());
      _baseline = confirmed;
      // Stable server-created spot IDs must join later edits without overwriting them.
      _draft = sameDraft
          ? confirmed
          : current.copyWith(
              blueprintId: result.blueprintId,
              revision: result.revision,
              seatBindings: {
                  for (final s in current.seatBindings.values)
                    s.nodeId: s.spotId == null &&
                            confirmed.seatBindings[s.nodeId]?.spotId != null
                        ? s.copyWith(
                            spotId: confirmed.seatBindings[s.nodeId]!.spotId)
                        : s
                });
      final currentDraft = _draft;
      _draft = confirmed;
      final checkpoint = capture();
      _draft = currentDraft;
      layout.setSavedBaseline(confirmed.document,
          participantCheckpoints: [checkpoint]);
      return result;
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> previewSwap() {
    final spots = selectedSpotIds;
    if (spots.length != 2) throw StateError('swap_requires_two_spots');
    return DbForms.previewBlueprintSwap(spots[0], spots[1]);
  }

  Future<void> swapSelected() async {
    final spots = selectedSpotIds;
    if (spots.length != 2 || isBusy)
      throw StateError('swap_requires_two_spots');
    isBusy = true;
    error = null;
    notifyListeners();
    try {
      await DbTickets.swapBlueprintSpots(spots[0], spots[1]);
      _operationSelection.clear();
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    layout.removeListener(_geometryChanged);
    layout.removeHistoryParticipant(this);
    layout.dispose();
    super.dispose();
  }
}

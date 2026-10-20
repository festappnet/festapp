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
      }
      return [];
    };
    _areaCapacities = {
      for (final id in _draft.areaBindings.keys)
        id: (source.areaAvailability[id]?['capacity'] as num?)?.toInt() ??
            (_draft.document.nodes
                        .firstWhere((n) => n.id == id)
                        .properties['capacity'] as num? ??
                    0)
                .toInt(),
    };
    _baselineAreaCapacities = {..._areaCapacities};
    layout.addHistoryParticipant(this);
    layout.addListener(_geometryChanged);
  }
  Map<String, int> _areaCapacities = {};
  Map<String, int> _baselineAreaCapacities = {};
  Map<String, int> get areaCapacities => Map.unmodifiable(_areaCapacities);
  int areaCapacity(String id) =>
      _areaCapacities[id] ??
      (adapter.areaAvailability[id]?['capacity'] as num?)?.toInt() ??
      (layout.document.nodes
                  .firstWhere((n) => n.id == id)
                  .properties['capacity'] as num? ??
              0)
          .toInt();

  void setAreaCapacity(String id, int capacity) {
    if (isBusy || layout.readOnly) throw StateError('blueprint_read_only');
    if (capacity < 0 ||
        capacity > 1000000 ||
        !_draft.areaBindings.containsKey(id)) {
      throw StateError('invalid_area_capacity');
    }
    final node = layout.document.nodes.firstWhere((n) => n.id == id);
    if (node.kind != 'capacityArea') throw StateError('invalid_area_capacity');
    final next = layout.document.copyWith(nodes: [
      for (final n in layout.document.nodes)
        n.id == id
            ? n.copyWith(properties: {...n.properties, 'capacity': capacity})
            : n
    ]);
    if (!layout
        .apply(next, label: 'Standing capacity', participantCheckpoints: [
      _captureSnapshot(_draft,
          areaCapacities: {..._areaCapacities, id: capacity})
    ])) throw StateError(layout.error ?? 'area_capacity_rejected');
  }

  final BlueprintLayoutAdapter adapter;
  final BlueprintLayoutSaver saver;
  late final VenueLayoutController layout;
  BlueprintLayoutSnapshot _baseline, _draft;
  BlueprintLayoutMode mode = BlueprintLayoutMode.manage;
  final Set<String> _operationSelection = {};
  bool isBusy = false;
  Object? error;
  int? _preferredSeatProductId;
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

  /// Prefer the last explicit choice, then the most-used priced seat product.
  /// Catalog creation time/ID breaks ties; suggestions never rewrite existing seats.
  int? get suggestedSeatProductId {
    final eligible = products.values
        .where((p) =>
            p.id != null &&
            p.productTypeString == ProductModel.spotType &&
            p.price != null &&
            p.isHidden != true)
        .toList();
    if (eligible.any((p) => p.id == _preferredSeatProductId))
      return _preferredSeatProductId;
    final counts = <int, int>{};
    for (final seat in _draft.seatBindings.values) {
      if (seat.productId != null)
        counts.update(seat.productId!, (v) => v + 1, ifAbsent: () => 1);
    }
    eligible.sort((a, b) {
      final usage = (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
      if (usage != 0) return usage;
      final created = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      return created != 0 ? created : b.id!.compareTo(a.id!);
    });
    return eligible.firstOrNull?.id;
  }

  void upsertCatalogProduct(ProductModel product) {
    if (product.id == null) throw ArgumentError('catalog_product_id_required');
    adapter.products = {...adapter.products, product.id!: product};
    if (product.productTypeString == ProductModel.spotType &&
        product.price != null) _preferredSeatProductId = product.id;
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

  void _mutate(BlueprintLayoutSnapshot Function() prepare) {
    if (layout.readOnly || isBusy) throw StateError('blueprint_read_only');
    final candidate = prepare();
    if (!layout.apply(layout.document,
        participantCheckpoints: [_captureSnapshot(candidate)]))
      throw StateError(layout.error ?? 'business_command_rejected');
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
    _mutate(() => _draft.copyWith(seatBindings: {
          ..._draft.seatBindings,
          for (final binding in bindings)
            if (!adapter.protected(binding))
              binding.nodeId: binding.copyWith(
                  productId: productId, productAssignmentMode: 'override')
        }));
    _preferredSeatProductId = productId;
  }

  void applyGroupProduct(String groupId, int productId,
          {bool freeOnly = false, bool replaceOverrides = false}) =>
      applyGroupsProduct({groupId}, productId,
          freeOnly: freeOnly, replaceOverrides: replaceOverrides);

  /// Update defaults and inherited assignments in one undo step. A seat whose
  /// explicit product assignment keeps that override, even at an equal value.
  /// Explicit whole-table UI assignments opt into [replaceOverrides].
  void applyGroupsProduct(Set<String> groupIds, int productId,
      {bool freeOnly = false,
      bool replaceOverrides = false,
      Set<String> additionalSeatIds = const {}}) {
    _requireProduct(productId);
    if (groupIds.isEmpty) return;
    final members = _draft.seatBindings.values
        .where((s) =>
            additionalSeatIds.contains(s.nodeId) ||
            (groupIds.contains(s.groupNodeId) &&
                (replaceOverrides || s.productAssignmentMode == 'inherit')))
        .toList();
    if (!freeOnly && members.any(adapter.protected))
      throw StateError('protected_spot');
    _mutate(() => _draft.copyWith(groupProducts: {
          ..._draft.groupProducts,
          for (final id in groupIds) id: productId
        }, seatBindings: {
          ..._draft.seatBindings,
          for (final s in members)
            if (!adapter.protected(s))
              s.nodeId: s.copyWith(
                  productId: productId,
                  productAssignmentMode: additionalSeatIds.contains(s.nodeId)
                      ? 'override'
                      : replaceOverrides
                          ? 'inherit'
                          : s.productAssignmentMode)
        }));
    _preferredSeatProductId = productId;
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

  void setBlocked(String nodeId, bool blocked) =>
      setBlockedForSeats({nodeId}, blocked);

  void setBlockedForSeats(Set<String> nodeIds, bool blocked) {
    final ids = Set<String>.from(nodeIds);
    for (final unit in layout.document.selectionUnits) {
      final members = Set<String>.from(unit['nodeIds'] as List? ?? const []);
      if (members.any(ids.contains)) ids.addAll(members);
    }
    if (ids.any(isProtected)) throw StateError('protected_spot');
    if (ids.any((id) => !_draft.seatBindings.containsKey(id))) {
      throw StateError('seat_binding_missing');
    }
    _mutate(() => _draft.copyWith(seatBindings: {
          ..._draft.seatBindings,
          for (final id in ids)
            id: _draft.seatBindings[id]!.copyWith(blocked: blocked),
        }));
  }

  void assignGroup(String nodeId, String groupId) {
    if (isProtected(nodeId)) throw StateError('protected_spot');
    final product = _draft.groupProducts[groupId] ??
        (throw StateError('group_product_required'));
    final binding = _draft.seatBindings[nodeId] ??
        (throw StateError('seat_binding_missing'));
    _mutate(() => _draft.copyWith(seatBindings: {
          ..._draft.seatBindings,
          nodeId: binding.copyWith(
              groupNodeId: groupId,
              productId: product,
              productAssignmentMode: 'inherit')
        }));
  }

  String? _commercialGroupFor(LayoutNode seat, VenueLayoutDocument document) =>
      blueprintCommercialGroupFor(seat, document,
          groupProducts: _draft.groupProducts,
          currentGroupId: _draft.seatBindings[seat.id]?.groupNodeId);

  void _geometryChanged() {
    // Business reconciliation commits inside the package transaction. A render
    // or selection notification cannot modify commercial state afterward.
    if (!layout.gestureActive) notifyListeners();
  }

  BlueprintLayoutSnapshot _prepareGeometry(VenueLayoutDocument before,
      VenueLayoutDocument after, LayoutEditIntent intent) {
    final previous = {for (final node in before.nodes) node.id: node};
    final seats = {
      for (final n in after.nodes)
        if (n.kind == 'seat') n.id: n
    };
    // Geometry previews retain commercial identities. Reconcile only when the
    // seat membership, naming, ancestry or paired-selection contract changes.
    final metadataUnchanged = seats.length == _draft.seatBindings.length &&
        const DeepCollectionEquality()
            .equals(before.selectionUnits, after.selectionUnits) &&
        after.nodes.length == before.nodes.length &&
        after.nodes.every((node) {
          final old = previous[node.id];
          return old != null &&
              old.kind == node.kind &&
              old.parentId == node.parentId &&
              (node.kind != 'seat' || old.label == node.label);
        });
    if (metadataUnchanged) return _draft;
    final groupProducts = Map<String, int>.from(_draft.groupProducts);
    final suggestedProduct = suggestedSeatProductId;
    if (suggestedProduct != null) {
      for (final table in after.nodes
          .where((n) => n.kind == 'table' && !previous.containsKey(n.id))) {
        final owner = blueprintCommercialGroupFor(
            LayoutNode(id: table.id, kind: 'seat', parentId: table.id), after,
            groupProducts: _draft.groupProducts);
        if (owner != null && !previous.containsKey(owner))
          groupProducts.putIfAbsent(owner, () => suggestedProduct);
      }
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

      final labelChanged = previous.containsKey(entry.key) &&
          previous[entry.key]!.label != entry.value.label;
      final commercialGroup = _commercialGroupFor(entry.value, after);
      if (current == null &&
          commercialGroup != null &&
          !previous.containsKey(commercialGroup) &&
          !groupProducts.containsKey(commercialGroup) &&
          suggestedProduct != null) {
        groupProducts[commercialGroup] = suggestedProduct;
      }
      final explicitAttach = intent.kind == LayoutEditKind.attachSeat &&
          intent.nodeId == entry.key;
      final groupChanged =
          explicitAttach && commercialGroup != current?.groupNodeId;
      if (explicitAttach &&
          (commercialGroup == null ||
              !_draft.groupProducts.containsKey(commercialGroup)))
        throw StateError('group_product_required');
      final unit = after.selectionUnits.where(
          (u) => (u['nodeIds'] as List? ?? const []).contains(entry.key));
      final unitId = unit.isEmpty ? null : unit.first['id'] as String?;
      var newTitle = entry.value.label;
      if (current == null &&
          commercialGroup != null &&
          !after.nodes.any((n) =>
              n.id == entry.value.parentId && n.assembly?['kind'] == 'rows')) {
        final groupNode =
            after.nodes.firstWhere((node) => node.id == commercialGroup);
        final nextIndex = groupCounts[commercialGroup] ?? 0;
        newTitle = blueprintSeatTitle(groupNode.label, nextIndex);
        groupCounts[commercialGroup] = nextIndex + 1;
      }
      bindings[entry.key] = current == null
          ? BlueprintSeatBinding(
              nodeId: entry.key,
              title: newTitle,
              groupNodeId: commercialGroup,
              productId: groupProducts[commercialGroup] ?? suggestedProduct,
              productAssignmentMode: groupProducts[commercialGroup] == null
                  ? 'override'
                  : 'inherit',
              selectionUnitId: unitId)
          : current.copyWith(
              title: labelChanged ? entry.value.label : current.title,
              // Visual detach preserves commercial membership. Explicit attach
              // adopts the target default, guarded before geometry is committed.
              groupNodeId: groupChanged ? commercialGroup : current.groupNodeId,
              productId: explicitAttach
                  ? _draft.groupProducts[commercialGroup]
                  : current.productId,
              productAssignmentMode:
                  explicitAttach ? 'inherit' : current.productAssignmentMode,
              selectionUnitId: unitId,
              clearUnit: unitId == null);
    }
    final ids = after.nodes.map((n) => n.id).toSet();
    return _draft.copyWith(seatBindings: bindings, groupProducts: {
      for (final e in groupProducts.entries)
        if (ids.contains(e.key)) e.key: e.value
    }, areaBindings: {
      for (final e in _draft.areaBindings.entries)
        if (after.nodes.any((n) => n.id == e.key && n.kind == 'capacityArea'))
          e.key: e.value
    });
  }

  @override
  Object prepare(
      VenueLayoutDocument before, VenueLayoutDocument after, Object? checkpoint,
      {required bool restoring, required LayoutEditIntent intent}) {
    final candidate = restoring
        ? _checkpointSnapshot(checkpoint)
        : _prepareGeometry(before, after, intent);
    final ids = after.nodes.map((n) => n.id).toSet();
    for (final binding in candidate.seatBindings.values) {
      if (binding.groupNodeId != null && !ids.contains(binding.groupNodeId))
        throw StateError('commercial_group_required');
      if (binding.productAssignmentMode == 'inherit' &&
          (binding.groupNodeId == null ||
              candidate.groupProducts[binding.groupNodeId] == null))
        throw StateError('inherited_product_mismatch');
    }
    for (final current in _draft.seatBindings.values.where(adapter.protected)) {
      final target = candidate.seatBindings[current.nodeId];
      if (target == null ||
          target.productId != current.productId ||
          target.title != current.title ||
          target.groupNodeId != current.groupNodeId ||
          target.selectionUnitId != current.selectionUnitId ||
          target.blocked != current.blocked ||
          target.productAssignmentMode != current.productAssignmentMode)
        throw StateError('protected_spot');
    }
    final capacities = checkpoint == null
        ? {..._areaCapacities}
        : Map<String, int>.from(
            (checkpoint as Map)['areaCapacities'] as Map? ?? {});
    if (checkpoint == null) {
      final previous = {for (final n in before.nodes) n.id: n};
      for (final n in after.nodes.where((n) =>
          n.kind == 'capacityArea' &&
          candidate.areaBindings.containsKey(n.id))) {
        if (previous[n.id]?.properties['capacity'] !=
            n.properties['capacity']) {
          capacities[n.id] = (n.properties['capacity'] as num? ?? 0).toInt();
        }
      }
    }
    capacities.removeWhere((id, _) => !candidate.areaBindings.containsKey(id));
    return _captureSnapshot(candidate, areaCapacities: capacities);
  }

  @override
  Object capture() => _captureSnapshot(_draft);

  Object _captureSnapshot(BlueprintLayoutSnapshot snapshot,
      {Map<String, int>? areaCapacities}) {
    // Readers need not order bindings like the document. History compares a
    // canonical checkpoint so selection/undo cannot manufacture dirty state.
    final seats = snapshot.seatBindings.keys.toList()..sort();
    final groups = snapshot.groupProducts.keys.toList()..sort();
    final areas = snapshot.areaBindings.keys.toList()..sort();
    return {
      'areaCapacities': {
        for (final id
            in (areaCapacities ?? _areaCapacities).keys.toList()..sort())
          id: (areaCapacities ?? _areaCapacities)[id]
      },
      'seats': [for (final id in seats) snapshot.seatBindings[id]!.toJson()],
      'groups': {for (final id in groups) id: snapshot.groupProducts[id]},
      'areas': [for (final id in areas) snapshot.areaBindings[id]!.toJson()],
    };
  }

  BlueprintLayoutSnapshot _checkpointSnapshot(Object? checkpoint) {
    final map = checkpoint as Map;
    var candidate = _draft.copyWith(
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
    candidate = candidate.copyWith(seatBindings: {
      for (final binding in candidate.seatBindings.values)
        binding.nodeId: binding.spotId == null &&
                _baseline.seatBindings[binding.nodeId]?.spotId != null
            ? binding.copyWith(
                spotId: _baseline.seatBindings[binding.nodeId]!.spotId)
            : binding,
    });
    candidate = candidate.copyWith(seatBindings: {
      for (final e in candidate.seatBindings.entries)
        e.key: _draft.seatBindings[e.key] != null &&
                const DeepCollectionEquality().equals(
                    _draft.seatBindings[e.key]!.toJson(), e.value.toJson())
            ? _draft.seatBindings[e.key]!
            : e.value
    });
    return candidate;
  }

  @override
  void restore(Object? checkpoint) {
    _draft = _checkpointSnapshot(checkpoint);
    _areaCapacities = Map<String, int>.from(
        (checkpoint as Map)['areaCapacities'] as Map? ?? {});
  }

  void cancel() {
    if (isBusy || saver.pending != null) throw StateError('save_unresolved');
    if (!layout.apply(_baseline.document, participantCheckpoints: [
      _captureSnapshot(_baseline, areaCapacities: _baselineAreaCapacities)
    ])) throw StateError(layout.error ?? 'cancel_rejected');
    layout.markSaved();
    _operationSelection.clear();
    error = null;
    notifyListeners();
  }

  bool validatePlacementForReservations() =>
      layout.showPlacementWarnings().isEmpty;

  Future<BlueprintLayoutSaveResult> save(
      {BlueprintLayoutSnapshot? captured,
      Map<String, int>? capturedAreaCapacities,
      Map<String, dynamic>? preparedResources}) async {
    if (layout.readOnly) throw StateError('blueprint_read_only');
    if (isBusy) throw StateError('save_in_progress');
    final submitted = saver.pending?.snapshot ?? captured ?? snapshot;
    if (layout.placementIssuesFor(submitted.document).isNotEmpty) {
      if (identical(submitted.document, layout.document))
        layout.showPlacementWarnings();
      throw StateError('layout_placement_invalid');
    }
    if (submitted.seatBindings.values
        .any((s) => s.spotId == null && !s.blocked && s.productId == null))
      throw StateError('seat_product_required');
    final request = saver.pending ??
        BlueprintLayoutSaveRequest(
            snapshot: submitted,
            baseline: _baseline,
            areaCapacities: {
              for (final e
                  in (capturedAreaCapacities ?? _areaCapacities).entries)
                if (_baselineAreaCapacities[e.key] != e.value) e.key: e.value
            },
            resources: preparedResources ?? layout.resources);
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
      final savedCapacities = {
        for (final change in request.toJson()['areaBindingChanges'] as List)
          if ((change as Map).containsKey('capacity'))
            change['nodeId'] as String: change['capacity'] as int
      };
      _baselineAreaCapacities = {
        ..._baselineAreaCapacities,
        ...savedCapacities
      };
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
      final checkpoint =
          _captureSnapshot(confirmed, areaCapacities: _baselineAreaCapacities);
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

import 'dart:convert';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import '../../blueprint/blueprint_layout_contract.dart';
import '../../blueprint/blueprint_group_binding.dart';

/// Private setup configuration. Product IDs are provisional form references;
/// physical spot IDs, reservations and catalog prices never enter this draft.
class BlueprintSetupLayoutDraft {
  BlueprintSetupLayoutDraft._(
      this.document,
      this.resources,
      Map<String, BlueprintSeatBinding> seats,
      Map<String, int> groups,
      List<Map<String, dynamic>> areas)
      : seatBindings = Map.unmodifiable(seats),
        groupProducts = Map.unmodifiable(groups),
        areaBindings =
            List.unmodifiable(areas.map(Map<String, dynamic>.unmodifiable));
  factory BlueprintSetupLayoutDraft.empty(
          {required VenueLayoutDocument document,
          required Map<String, dynamic> resources}) =>
      BlueprintSetupLayoutDraft._(document,
          Map.unmodifiable(resources), {}, {}, []);
  factory BlueprintSetupLayoutDraft.fromJson(Map<String, dynamic> json,
      {Map<String, dynamic> resources = const {}}) {
    final portable =
        Map<String, dynamic>.from(jsonDecode(jsonEncode(json)) as Map);
    return BlueprintSetupLayoutDraft._(
        VenueLayoutDocument.fromJson(
            Map<String, dynamic>.from(portable['layout'] as Map)),
        Map.unmodifiable(resources),
        {
          for (final raw in portable['seatBindings'] as List? ?? const [])
            (raw as Map)['nodeId'] as String: BlueprintSeatBinding.fromJson(
                Map<String, dynamic>.from(raw)..remove('spotId')),
        },
        {
          for (final raw in portable['groupProducts'] as List? ?? const [])
            if ((raw as Map)['productId'] != null)
              raw['groupNodeId'] as String: (raw['productId'] as num).toInt(),
        },
        [
          for (final raw in portable['areaBindings'] as List? ?? const [])
            Map<String, dynamic>.from(raw as Map)
        ]);
  }
  final VenueLayoutDocument document;
  final Map<String, dynamic> resources;
  final Map<String, BlueprintSeatBinding> seatBindings;
  final Map<String, int> groupProducts;
  final List<Map<String, dynamic>> areaBindings;
  Map<String, dynamic> toJson() => {
        'layout': document.toJson(),
        'seatBindings': [
          for (final seat in seatBindings.values)
            Map<String, dynamic>.from(seat.toJson())..remove('spotId')
        ],
        'groupProducts': [
          for (final group in groupProducts.entries)
            {'groupNodeId': group.key, 'productId': group.value}
        ],
        'areaBindings': areaBindings,
      };
  BlueprintSetupLayoutDraft reconcile(VenueLayoutDocument next,
      {required int? defaultProductId}) {
    final nodes = {for (final node in next.nodes) node.id: node};
    final previousNodes = {for (final node in document.nodes) node.id: node};
    final groups = {...groupProducts};
    final seats = <String, BlueprintSeatBinding>{};
    for (final node in next.nodes.where((node) => node.kind == 'seat')) {
      final previous = seatBindings[node.id];
      final parentChanged = previousNodes[node.id]?.parentId != node.parentId;
      final group = previous == null || parentChanged
          ? blueprintCommercialGroupFor(node, next,
              groupProducts: groups, currentGroupId: previous?.groupNodeId)
          : previous.groupNodeId;
      final groupChanged = parentChanged && group != previous?.groupNodeId;
      final unit = next.selectionUnits.where(
          (unit) => (unit['nodeIds'] as List? ?? const []).contains(node.id));
      final previousGroupProducts = seatBindings.values
          .where((binding) => binding.groupNodeId == group)
          .map((binding) => binding.productId)
          .toSet();
      final unknownGroupDefault = group != null &&
          !groups.containsKey(group) &&
          (previousGroupProducts.length > 1 ||
              previousGroupProducts.contains(null));
      if (previous == null &&
          group != null &&
          !groups.containsKey(group) &&
          !unknownGroupDefault &&
          defaultProductId != null) {
        groups[group] = defaultProductId;
      }
      seats[node.id] = BlueprintSeatBinding(
          nodeId: node.id,
          productId: previous != null && !groupChanged
              ? previous.productId
              : unknownGroupDefault
                  ? null
                  : groups[group] ?? defaultProductId,
          title: node.label.isEmpty ? previous?.title ?? '' : node.label,
          groupNodeId: group,
          selectionUnitId: unit.isEmpty ? null : unit.first['id'] as String,
          blocked: previous?.blocked ?? false);
    }
    return BlueprintSetupLayoutDraft._(next, resources, seats, {
      for (final group in groups.entries)
        if (nodes.containsKey(group.key)) group.key: group.value
    }, [
      for (final area in areaBindings)
        if (nodes[area['nodeId']]?.kind == 'capacityArea') area
    ]);
  }

  /// An explicit group choice fills empty draft seats while retaining overrides.
  BlueprintSetupLayoutDraft withGroupProduct(String groupNodeId, int productId,
      {bool assignUnassigned = true, Set<String>? assignNodeIds}) {
    if (!document.nodes.any((node) =>
        node.id == groupNodeId &&
        const {'table', 'group', 'furniture'}.contains(node.kind))) {
      throw StateError('invalid_group_draft');
    }
    return BlueprintSetupLayoutDraft._(
        document,
        resources,
        {
          for (final binding in seatBindings.values)
            binding.nodeId: assignUnassigned &&
                    binding.groupNodeId == groupNodeId &&
                    binding.productId == null &&
                    (assignNodeIds == null ||
                        assignNodeIds.contains(binding.nodeId))
                ? binding.copyWith(productId: productId)
                : binding,
        },
        {...groupProducts, groupNodeId: productId},
        areaBindings);
  }

  BlueprintSetupLayoutDraft withArea(
      {required String nodeId, required int productId, required int capacity}) {
    if (capacity < 0 ||
        !document.nodes
            .any((node) => node.id == nodeId && node.kind == 'capacityArea')) {
      throw StateError('invalid_area_draft');
    }
    return BlueprintSetupLayoutDraft._(
        document, resources, seatBindings, groupProducts, [
      ...areaBindings.where((area) => area['nodeId'] != nodeId),
      {'nodeId': nodeId, 'productId': productId, 'capacity': capacity}
    ]);
  }
}

import 'dart:convert';
import 'package:venue_seat_picker/venue_seat_picker.dart';

// Host-only commercial contract. No product, spot or order identity enters core.
enum BlueprintLayoutMode { manage, order, swap }

enum BlueprintSeatOperation { upsert, delete }

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);
int? _id(Object? value) => value == null ? null : (value as num).toInt();

class BlueprintSeatBinding {
  const BlueprintSeatBinding(
      {required this.nodeId,
      this.spotId,
      this.productId,
      this.title = '',
      this.groupNodeId,
      this.selectionUnitId,
      this.blocked = false});
  final String nodeId;
  final int? spotId, productId;
  final String title;
  final String? groupNodeId, selectionUnitId;
  final bool blocked;
  factory BlueprintSeatBinding.fromJson(Map<String, dynamic> json) =>
      BlueprintSeatBinding(
          nodeId: json['nodeId'] as String,
          spotId: _id(json['spotId']),
          productId: _id(json['productId']),
          title: json['title'] as String? ?? '',
          groupNodeId: json['groupNodeId'] as String?,
          selectionUnitId: json['selectionUnitId'] as String?,
          blocked: json['blocked'] == true);
  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'spotId': spotId,
        'productId': productId,
        'title': title,
        'groupNodeId': groupNodeId,
        'selectionUnitId': selectionUnitId,
        'blocked': blocked
      };
  BlueprintSeatBinding copyWith(
          {int? spotId,
          int? productId,
          String? title,
          String? groupNodeId,
          String? selectionUnitId,
          bool? blocked,
          bool clearProduct = false,
          bool clearGroup = false,
          bool clearUnit = false}) =>
      BlueprintSeatBinding(
          nodeId: nodeId,
          spotId: spotId ?? this.spotId,
          productId: clearProduct ? null : productId ?? this.productId,
          title: title ?? this.title,
          groupNodeId: clearGroup ? null : groupNodeId ?? this.groupNodeId,
          selectionUnitId:
              clearUnit ? null : selectionUnitId ?? this.selectionUnitId,
          blocked: blocked ?? this.blocked);
}

class BlueprintGroupProduct {
  const BlueprintGroupProduct({required this.groupNodeId, this.productId});
  final String groupNodeId;
  final int? productId;
  Map<String, dynamic> toJson() =>
      {'groupNodeId': groupNodeId, 'productId': productId};
}

class BlueprintAreaBinding {
  const BlueprintAreaBinding(
      {required this.nodeId,
      required this.inventoryContextId,
      required this.productId});
  final String nodeId;
  // Public projection deliberately omits the internal inventory context.
  final int? inventoryContextId;
  final int productId;
  factory BlueprintAreaBinding.fromJson(Map<String, dynamic> json) =>
      BlueprintAreaBinding(
          nodeId: json['nodeId'] as String,
          inventoryContextId: _id(json['inventoryContextId']),
          productId: _id(json['productId'])!);
  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'inventoryContextId': inventoryContextId,
        'productId': productId
      };
}

class BlueprintLayoutSnapshot {
  BlueprintLayoutSnapshot(
      {required this.blueprintId,
      required this.occasionId,
      this.organizationId,
      required this.title,
      required this.revision,
      required this.document,
      Map<String, BlueprintSeatBinding> seatBindings = const {},
      Map<String, int> groupProducts = const {},
      Map<String, BlueprintAreaBinding> areaBindings = const {}})
      : seatBindings = Map.unmodifiable(seatBindings),
        groupProducts = Map.unmodifiable(groupProducts),
        areaBindings = Map.unmodifiable(areaBindings);
  final int? blueprintId;
  final int occasionId;
  final int? organizationId;
  final String title;
  final int revision;
  final VenueLayoutDocument document;
  final Map<String, BlueprintSeatBinding> seatBindings;
  final Map<String, int> groupProducts;
  final Map<String, BlueprintAreaBinding> areaBindings;
  factory BlueprintLayoutSnapshot.fromJson(Map<String, dynamic> json) =>
      BlueprintLayoutSnapshot(
          blueprintId: _id(json['blueprint_id'] ?? json['id']),
          occasionId: _id(json['occasion'])!,
          organizationId: _id(json['organization']),
          title: json['title'] as String? ?? '',
          revision: _id(json['layout_revision']) ?? 0,
          document: VenueLayoutDocument.fromJson(_map(json['layout'])),
          seatBindings: {
            for (final v in json['seatBindings'] as List? ?? const [])
              (v as Map)['nodeId'] as String:
                  BlueprintSeatBinding.fromJson(_map(v))
          },
          groupProducts: {
            for (final v in json['groupProducts'] as List? ?? const [])
              if ((v as Map)['productId'] != null)
                v['groupNodeId'] as String: _id(v['productId'])!
          },
          areaBindings: {
            for (final v in json['areaBindings'] as List? ?? const [])
              (v as Map)['nodeId'] as String:
                  BlueprintAreaBinding.fromJson(_map(v))
          });
  Map<String, dynamic> toJson() => {
        'id': blueprintId,
        'occasion': occasionId,
        'organization': organizationId,
        'title': title,
        'layout_revision': revision,
        'layout': document.toJson(),
        'seatBindings': seatBindings.values.map((v) => v.toJson()).toList(),
        'groupProducts': groupProducts.entries
            .map((v) =>
                BlueprintGroupProduct(groupNodeId: v.key, productId: v.value)
                    .toJson())
            .toList(),
        'areaBindings': areaBindings.values.map((v) => v.toJson()).toList()
      };
  BlueprintLayoutSnapshot copyWith(
          {int? blueprintId,
          int? revision,
          VenueLayoutDocument? document,
          Map<String, BlueprintSeatBinding>? seatBindings,
          Map<String, int>? groupProducts,
          Map<String, BlueprintAreaBinding>? areaBindings}) =>
      BlueprintLayoutSnapshot(
          blueprintId: blueprintId ?? this.blueprintId,
          occasionId: occasionId,
          organizationId: organizationId,
          title: title,
          revision: revision ?? this.revision,
          document: document ?? this.document,
          seatBindings: seatBindings ?? this.seatBindings,
          groupProducts: groupProducts ?? this.groupProducts,
          areaBindings: areaBindings ?? this.areaBindings);
}

class BlueprintSeatChange {
  const BlueprintSeatChange(this.binding,
      {this.operation = BlueprintSeatOperation.upsert});
  final BlueprintSeatBinding binding;
  final BlueprintSeatOperation operation;
  Map<String, dynamic> toJson() =>
      {...binding.toJson(), 'operation': operation.name};
}

class BlueprintAreaBindingChange {
  const BlueprintAreaBindingChange(this.binding,
      {this.operation = BlueprintSeatOperation.upsert, this.capacity});
  final BlueprintAreaBinding binding;
  final BlueprintSeatOperation operation;

  /// Explicit inventory capacity intent; geometric resize never populates it.
  final int? capacity;
  Map<String, dynamic> toJson() => {
        ...binding.toJson(),
        'operation': operation.name,
        if (capacity != null) 'capacity': capacity
      };
}

/// Frozen payload for one command intent. Retry must reuse its ID and these bytes.
class BlueprintLayoutSaveRequest {
  BlueprintLayoutSaveRequest(
      {required this.snapshot,
      required this.baseline,
      Map<String, int> areaCapacities = const {}})
      : expectedRevision = baseline.revision {
    if ([...snapshot.areaBindings.values, ...baseline.areaBindings.values]
        .any((binding) => binding.inventoryContextId == null)) {
      throw StateError('public_blueprint_cannot_be_saved');
    }
    _payload = jsonEncode(_build(areaCapacities));
  }
  final BlueprintLayoutSnapshot snapshot, baseline;
  final int expectedRevision;
  late final String _payload;
  Map<String, dynamic> _build(Map<String, int> areaCapacities) => {
        'id': snapshot.blueprintId,
        'occasion': snapshot.occasionId,
        'organization': snapshot.organizationId,
        'title': snapshot.title,
        'expected_layout_revision': expectedRevision,
        'layout': snapshot.document.toJson(),
        'seatChanges': [
          for (final binding in snapshot.seatBindings.values)
            BlueprintSeatChange(binding).toJson(),
          for (final binding in baseline.seatBindings.values)
            if (!snapshot.seatBindings.containsKey(binding.nodeId))
              BlueprintSeatChange(binding,
                      operation: BlueprintSeatOperation.delete)
                  .toJson()
        ],
        'groupProductChanges': [
          for (final id in {
            ...baseline.groupProducts.keys,
            ...snapshot.groupProducts.keys
          })
            BlueprintGroupProduct(
                    groupNodeId: id, productId: snapshot.groupProducts[id])
                .toJson()
        ],
        'areaBindingChanges': [
          for (final binding in snapshot.areaBindings.values)
            BlueprintAreaBindingChange(binding,
                    capacity: areaCapacities[binding.nodeId])
                .toJson(),
          for (final binding in baseline.areaBindings.values)
            if (!snapshot.areaBindings.containsKey(binding.nodeId))
              BlueprintAreaBindingChange(binding,
                      operation: BlueprintSeatOperation.delete)
                  .toJson()
        ]
      };
  Map<String, dynamic> toJson() => _map(jsonDecode(_payload));
}

class BlueprintLayoutIssue {
  const BlueprintLayoutIssue({required this.reason, this.nodeId, this.spotId});
  final String reason;
  final String? nodeId;
  final int? spotId;
  factory BlueprintLayoutIssue.fromJson(Map<String, dynamic> json) =>
      BlueprintLayoutIssue(
          reason: json['reason'] as String,
          nodeId: json['nodeId'] as String?,
          spotId: _id(json['spotId']));
}

class BlueprintLayoutSaveResult {
  BlueprintLayoutSaveResult(
      {required this.code,
      this.blueprintId,
      this.revision,
      this.documentHash,
      this.reason,
      Iterable<BlueprintLayoutIssue> issues = const [],
      Iterable<BlueprintSeatBinding> seatBindings = const [],
      Map<String, int> groupProducts = const {},
      Iterable<BlueprintAreaBinding> areaBindings = const []})
      : issues = List.unmodifiable(issues),
        seatBindings = List.unmodifiable(seatBindings),
        groupProducts = Map.unmodifiable(groupProducts),
        areaBindings = List.unmodifiable(areaBindings);
  final int code;
  final int? blueprintId, revision;
  final String? documentHash, reason;
  final List<BlueprintLayoutIssue> issues;
  final List<BlueprintSeatBinding> seatBindings;
  final Map<String, int> groupProducts;
  final List<BlueprintAreaBinding> areaBindings;
  bool get accepted => code == 200;
  factory BlueprintLayoutSaveResult.fromJson(Map<String, dynamic> json) =>
      BlueprintLayoutSaveResult(
          code: _id(json['code']) ?? 200,
          blueprintId: _id(json['blueprint_id']),
          revision: _id(json['layout_revision']),
          documentHash: json['document_hash'] as String?,
          reason: json['reason'] as String?,
          issues: (json['issues'] as List? ?? const [])
              .map((v) => BlueprintLayoutIssue.fromJson(_map(v))),
          seatBindings: (json['seatBindings'] as List? ?? const [])
              .map((v) => BlueprintSeatBinding.fromJson(_map(v))),
          groupProducts: {
            for (final v in json['groupProducts'] as List? ?? const [])
              if ((v as Map)['productId'] != null)
                v['groupNodeId'] as String: _id(v['productId'])!
          },
          areaBindings: (json['areaBindings'] as List? ?? const [])
              .map((v) => BlueprintAreaBinding.fromJson(_map(v))));
}

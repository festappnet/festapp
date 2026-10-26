import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'package:fstapp/database_tables/tb.dart';

import 'package:festapp_core/map.dart';

enum InventoryPoolType {
  accommodation,
  food,
  other,
}

/// Pool types the current occasion's ServicesFeature permits, in display order.
///
/// Falls back to all types when the feature config is unavailable. Never
/// returns an empty list.
List<InventoryPoolType> allowedInventoryPoolTypes() {
  final feature = FeatureService.getServicesFeature();
  if (feature == null) return InventoryPoolType.values;
  if (feature.allowsCapacityGroups) return const [InventoryPoolType.other];
  final types = <InventoryPoolType>[];
  if (feature.allowsAccommodation) types.add(InventoryPoolType.accommodation);
  if (feature.allowsFood) types.add(InventoryPoolType.food);
  return types.isEmpty ? const [InventoryPoolType.accommodation] : types;
}

extension InventoryPoolTypeUI on InventoryPoolType {
  IconData get icon {
    switch (this) {
      case InventoryPoolType.accommodation:
        return Icons.hotel;
      case InventoryPoolType.food:
        return Icons.restaurant_rounded;
      case InventoryPoolType.other:
        return Icons.category_rounded;
    }
  }

  String get displayName {
    switch (this) {
      case InventoryPoolType.accommodation:
        return InventoryStrings.typeAccommodation;
      case InventoryPoolType.food:
        return InventoryStrings.typeFood;
      case InventoryPoolType.other:
        return InventoryStrings.typeOther;
    }
  }
}

String? _inventoryPoolTypeToString(InventoryPoolType type) {
  switch (type) {
    case InventoryPoolType.accommodation:
      return 'accommodation';
    case InventoryPoolType.food:
      return 'food';
    case InventoryPoolType.other:
      return null;
  }
}

InventoryPoolType _stringToInventoryPoolType(String? s) {
  switch (s) {
    case 'accommodation':
      return InventoryPoolType.accommodation;
    case 'food':
      return InventoryPoolType.food;
    default:
      return InventoryPoolType.other;
  }
}

class InventoryPoolModel {
  int? id;
  String? title;
  int? sellableCapacity;

  /// Read-only resource supply from the shared administration projection.
  final int? resourceCapacity;
  int? occasionId;
  bool isAutoResourceAssignment;
  String? description;
  InventoryPoolType type;
  bool isEditableByUser;
  int? placeId;
  PlaceModel? place;

  InventoryPoolModel({
    this.id,
    this.title,
    this.sellableCapacity,
    this.resourceCapacity,
    this.occasionId,
    this.isAutoResourceAssignment = true,
    this.description,
    this.type = InventoryPoolType.other,
    this.isEditableByUser = false,
    this.placeId,
    this.place,
  });

  factory InventoryPoolModel.fromJson(Map<String, dynamic> json) {
    final t = Tb.inventory_pools;
    final data = json[t.data] as Map<String, dynamic>? ?? {};

    return InventoryPoolModel(
      id: json[t.id],
      title: json[t.title],
      sellableCapacity: json[t.sellable_capacity],
      resourceCapacity: json['resource_capacity'],
      occasionId: json[t.occasion],
      isAutoResourceAssignment:
          data[t.data_is_auto_resource_assignment] as bool? ?? true,
      description: json[t.description],
      type: _stringToInventoryPoolType(json[t.type]),
      placeId: data[t.data_place_id] as int?, // ADDED
    );
  }

  Map<String, dynamic> toJson() {
    final t = Tb.inventory_pools;
    return {
      t.id: id,
      t.title: title,
      t.sellable_capacity: sellableCapacity,
      t.occasion: occasionId,
      t.description: description,
      t.type: _inventoryPoolTypeToString(type),
      t.data: {
        t.data_is_auto_resource_assignment: isAutoResourceAssignment,
        t.data_place_id: place?.id ?? placeId,
      },
    };
  }
}

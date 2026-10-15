import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/inventory/models/resource_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';

import 'package:festapp_core/map.dart';
import 'inventory_context_model.dart';
import 'inventory_pool_model.dart';

class InventoryPoolBundle {
  final InventoryPoolModel pool;
  final OccasionModel? occasion;
  List<ResourceModel>? resources;
  List<InventoryContextModel>? contexts;
  List<PlaceModel>? places;
  List<ProductModel>? products;
  List<ProductInventoryContextModel>? productInventoryContexts;
  int aggregateVersion;

  InventoryPoolBundle({
    required this.pool,
    this.occasion,
    this.resources,
    this.contexts,
    this.places,
    this.products,
    this.productInventoryContexts,
    this.aggregateVersion = 0,
  });

  factory InventoryPoolBundle.fromJson(Map<String, dynamic> json) {
    // Helper to safely parse lists from JSON.
    List<T>? parseList<T>(
        String key, T Function(Map<String, dynamic>) fromJson) {
      if (json[key] is! List) return null;
      return (json[key] as List)
          .map((item) => fromJson(item as Map<String, dynamic>))
          .toList();
    }

    // 1. Parse all relevant lists from the JSON bundle.
    final List<InventoryContextModel>? contexts =
        parseList('contexts', (c) => InventoryContextModel.fromJson(c));
    final List<ProductModel>? products =
        parseList('products', (p) => ProductModel.fromJson(p));
    final List<ProductInventoryContextModel>? productContextLinks = parseList(
        'product_inventory_contexts',
        (pic) => ProductInventoryContextModel.fromJson(pic));

    if (products != null && contexts != null && productContextLinks != null) {
      for (var index = 0; index < products.length; index++) {
        final product = products[index];
        products[index] = product.copyWith(includedInventories: [
          ...product.includedInventories,
          ...productContextLinks.where((link) => link.productId == product.id),
        ]);
      }
    }

    // 3. Return the fully constructed and linked bundle.
    return InventoryPoolBundle(
      pool: InventoryPoolModel.fromJson(json['pool']),
      occasion: json['occasion'] != null
          ? OccasionModel.fromJson(json['occasion'])
          : null,
      resources: parseList('resources', (r) => ResourceModel.fromJson(r)),
      places: parseList('places', (p) => PlaceModel.fromJson(p)),
      contexts: contexts,
      products: products,
      productInventoryContexts: productContextLinks,
      aggregateVersion: (json['aggregate_version'] as num?)?.toInt() ?? 0,
    );
  }

  /// Converts the bundle to a JSON object for updating data.
  Map<String, dynamic> toJson() {
    return {
      'pool': pool.toJson(),
      'contexts': contexts?.map((c) => c.toJson()).toList(),
    };
  }
}

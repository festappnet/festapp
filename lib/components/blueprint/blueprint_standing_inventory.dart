import 'package:festapp_core/eshop.dart';

import '../eshop/db_eshop.dart';
import '../inventory/db_inventory_pools.dart';
import '../inventory/models/inventory_context_model.dart';
import '../inventory/models/inventory_pool_bundle.dart';
import '../inventory/models/inventory_pool_model.dart';
import '../inventory/models/resource_model.dart';

/// Prepares existing inventory domain entities; never maintains sale counters.
/// Retains successful steps if a later command is rejected and the dialog retries.
class BlueprintStandingInventory {
  BlueprintStandingInventory({
    Future<InventoryPoolBundle> Function(InventoryPoolBundle)? savePool,
    Future<void> Function(ResourceModel)? saveResource,
    Future<void> Function(ProductModel, int)? linkProduct,
  })  : _savePool = savePool ?? DbInventoryPools.updateInventoryPoolBundle,
        _saveResource = saveResource ?? DbInventoryPools.updateResource,
        _linkProduct = linkProduct ??
            ((product, context) =>
                DbEshop.commands.updateProductInventoryContexts(
                    product.id!,
                    [
                      {'inventory_context_id': context, 'quantity': 1},
                    ],
                    expectedVersion: product.aggregateVersion));

  final Future<InventoryPoolBundle> Function(InventoryPoolBundle) _savePool;
  final Future<void> Function(ResourceModel) _saveResource;
  final Future<void> Function(ProductModel, int) _linkProduct;
  InventoryPoolBundle? _pool;
  ResourceModel? _resource;
  ProductModel? _linked;
  int? _productId;
  int? _capacity;
  int? get preparedCapacity => _capacity;

  Future<ProductModel> prepare(ProductModel product, int capacity) async {
    if (product.id == null ||
        product.occasion == null ||
        product.productTypeString != ProductModel.spotType ||
        product.includedInventories.isNotEmpty ||
        capacity < 0 ||
        capacity > 1000000) {
      throw StateError('invalid_standing_inventory');
    }
    if (_productId != null &&
        (_productId != product.id || _capacity != capacity)) {
      throw StateError('standing_preparation_changed');
    }
    _productId = product.id;
    _capacity = capacity;
    if (_linked != null) return _linked!;
    _pool ??= await _savePool(
      InventoryPoolBundle(
        pool: InventoryPoolModel(
          title: product.title,
          occasionId: product.occasion,
          sellableCapacity: capacity,
          isAutoResourceAssignment: false,
        ),
        contexts: [
          InventoryContextModel(inventoryPoolId: 0, title: product.title),
        ],
      ),
    );
    // sellableCapacity is a ceiling. Actual supply is owned by resources.
    _resource ??= ResourceModel(
      title: product.title,
      capacity: capacity,
      inventoryPoolId: _pool!.pool.id!,
    );
    if (_resource!.id == null) await _saveResource(_resource!);
    final contextId = _pool!.contexts!.single.id!;
    // The canonical command validates capacity and reallocates existing order
    // items atomically; an existing sale does not make the product ineligible.
    await _linkProduct(product, contextId);
    return _linked = product.copyWith(
      includedInventories: [
        ProductInventoryContextModel(
          productId: product.id!,
          inventoryContextId: contextId,
          quantity: 1,
        ),
      ],
    );
  }
}

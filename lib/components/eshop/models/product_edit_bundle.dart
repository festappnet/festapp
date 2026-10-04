import 'product_price_wave.dart';
import 'package:fstapp/components/inventory/models/inventory_context_model.dart';
import 'package:fstapp/components/inventory/models/inventory_pool_model.dart';
import 'package:fstapp/components/forms/models/form_model.dart';

import 'product_model.dart';
import 'product_type_model.dart';

class ProductsEditBundle {
  final List<ProductModel> products;
  final List<ProductPriceWave> priceWaves;
  final List<ProductTypeModel> productTypes;
  final List<InventoryPoolModel> inventoryPools;
  final List<InventoryContextModel> inventoryContexts;
  final List<FormModel> forms;

  ProductsEditBundle({
    required this.products,
    this.priceWaves = const [],
    required this.productTypes,
    required this.inventoryPools,
    required this.inventoryContexts,
    required this.forms,
  });
}

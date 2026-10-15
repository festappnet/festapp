import 'product_model.dart';
import 'product_type_model.dart';

/// One owner for flat endpoint products and type relations. Products never
/// contain parent objects, and every relation uses the same immutable values.
class ProductCatalog {
  factory ProductCatalog({
    required List<ProductModel> products,
    required List<ProductTypeModel> types,
  }) {
    final byType = <int?, List<ProductModel>>{};
    for (final product in products) {
      byType.putIfAbsent(product.productTypeId, () => []).add(product);
    }
    return ProductCatalog._(
      List.unmodifiable(products),
      List.unmodifiable([
        for (final type in types)
          type.copyWith(products: byType[type.id] ?? const <ProductModel>[]),
      ]),
    );
  }
  ProductCatalog._(this.products, this.types);

  final List<ProductModel> products;
  final List<ProductTypeModel> types;
}

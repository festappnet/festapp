class ProductInventoryContextModel {
  final int? id;
  final int productId;
  final int inventoryContextId;
  final int quantity;

  ProductInventoryContextModel({
    this.id,
    required this.productId,
    required this.inventoryContextId,
    required this.quantity,
  });

  /// **Creates a `ProductInventoryContextModel` from a JSON object.**
  ///
  /// This factory uses constants from `TbEshop` to map the JSON keys
  /// to the class properties, ensuring consistency with the database schema.
  factory ProductInventoryContextModel.fromJson(Map<String, dynamic> json) {
    return ProductInventoryContextModel(
      id: json['id'],
      productId: json['product'],
      inventoryContextId: json['inventory_context'],
      quantity: json['quantity'],
    );
  }

  /// **Converts the `ProductInventoryContextModel` to a JSON object.**
  ///
  /// This method serializes the object into a map, using the `TbEshop`
  /// constants for the keys. The `inventoryContext` object is intentionally
  /// excluded to prevent data duplication and circular references, as only
  /// the `inventoryContextId` is needed for serialization.
  Map<String, dynamic> toJson() {
    return {
      // The ID is included if it exists, crucial for update operations.
      if (id != null) 'id': id,
      'product': productId,
      'inventory_context': inventoryContextId,
      'quantity': quantity,
    };
  }

  ProductInventoryContextModel copyWith({int? quantity}) =>
      ProductInventoryContextModel(
        id: id,
        productId: productId,
        inventoryContextId: inventoryContextId,
        quantity: quantity ?? this.quantity,
      );
}

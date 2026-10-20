class SavedProduct {
  const SavedProduct(this.id, this.aggregateVersion);
  final int id;
  final int aggregateVersion;
}

abstract interface class EshopCommands {
  Future<void> deleteProduct(int productId, {required int expectedVersion});
  Future<SavedProduct> saveProduct(Map<String, dynamic> product);
  Future<Map<String, dynamic>> updateTicketProducts(
    int ticketId,
    List<Map<String, dynamic>> products,
  );
  Future<void> updateProductInventoryContexts(
      int productId, List<Map<String, dynamic>> contexts,
      {required int expectedVersion});
}

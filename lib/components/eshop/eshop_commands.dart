abstract interface class EshopCommands {
  Future<void> deleteProduct(int productId);
  Future<int> saveProduct(Map<String, dynamic> product);
  Future<Map<String, dynamic>> updateTicketProducts(
    int ticketId,
    List<Map<String, dynamic>> products,
  );
  Future<void> updateProductInventoryContexts(
    int productId,
    List<Map<String, dynamic>> contexts,
  );
}

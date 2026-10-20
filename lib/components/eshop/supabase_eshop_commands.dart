import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/eshop/eshop_commands.dart';

class SupabaseEshopCommands implements EshopCommands {
  SupabaseEshopCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client, durable: true);
  SupabaseEshopCommands.withTransport(this._transport);
  final ClientCommandTransport _transport;

  @override
  Future<void> deleteProduct(int productId, {required int expectedVersion}) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'delete_product_client_sync_v1',
      {'p_product_id': productId, 'p_expected_version': expectedVersion},
    ));
    if (response.code != 200) {
      throw StateError(
        response.data['message']?.toString() ?? 'Product deletion was rejected',
      );
    }
    await applyClientCommandReplacements(response);
  }

  @override
  Future<Map<String, dynamic>> updateTicketProducts(
    int ticketId,
    List<Map<String, dynamic>> products,
  ) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'update_ticket_products_client_sync_v1',
      {'p_ticket': ticketId, 'p_products': products},
    ));
    if (response.code != 200) {
      throw StateError('Ticket product update was rejected');
    }
    await applyClientCommandReplacements(response);
    return response.data;
  }

  @override
  Future<SavedProduct> saveProduct(Map<String, dynamic> product) async {
    if (product['id'] != null &&
        product['expected_aggregate_version'] is! int) {
      throw ArgumentError('Product save requires its original version');
    }
    if (product['inventory_contexts'] is List) {
      final contexts =
          List<Map<String, dynamic>>.from(product['inventory_contexts'] as List)
            ..sort((a, b) => (a['inventory_context_id'] as int)
                .compareTo(b['inventory_context_id'] as int));
      product = {...product, 'inventory_contexts': contexts};
    }
    final response = ClientCommandResponse.from(await _transport.invoke(
      'update_product_client_sync_v1',
      {'p_product': product},
    ));
    if (response.status == 'conflict') {
      throw StateError('Product was changed by another editor');
    }
    if (response.code != 200 ||
        response.data['productId'] is! num ||
        response.data['aggregate_version'] is! num) {
      throw StateError('Product save was rejected');
    }
    await applyClientCommandReplacements(response);
    return SavedProduct((response.data['productId'] as num).toInt(),
        (response.data['aggregate_version'] as num).toInt());
  }

  @override
  Future<void> updateProductInventoryContexts(
      int productId, List<Map<String, dynamic>> contexts,
      {required int expectedVersion}) async {
    final normalized = List<Map<String, dynamic>>.of(contexts)
      ..sort((a, b) => (a['inventory_context_id'] as int)
          .compareTo(b['inventory_context_id'] as int));
    final response = ClientCommandResponse.from(await _transport.invoke(
      'update_product_inventory_contexts_client_sync_v1',
      {
        'p_product_id': productId,
        'p_contexts': {
          'expected_aggregate_version': expectedVersion,
          'contexts': normalized
        }
      },
    ));
    if (response.code != 200) {
      throw StateError('Product inventory context update was rejected');
    }
    await applyClientCommandReplacements(response);
  }
}

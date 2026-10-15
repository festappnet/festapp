import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/eshop/eshop_commands.dart';

class SupabaseEshopCommands implements EshopCommands {
  SupabaseEshopCommands(SupabaseClient client, {bool Function()? useClientSync})
      : _transport = ClientCommandTransport.supabase(client),
        _legacyRpc = ((name, params) => client.rpc(name, params: params)),
        _useClientSync = useClientSync ?? (() => true);

  SupabaseEshopCommands.withTransport(this._transport)
      : _legacyRpc = null,
        _useClientSync = (() => true);

  final ClientCommandTransport _transport;
  final ClientCommandRpc? _legacyRpc;
  final bool Function() _useClientSync;

  @override
  Future<void> deleteProduct(int productId) async {
    if (!_useClientSync()) {
      await _legacyRpc!('delete_product', {'p_product_id': productId});
      return;
    }
    final response = ClientCommandResponse.from(await _transport.invoke(
      'delete_product_client_sync_v1',
      {'p_product_id': productId},
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
  Future<int> saveProduct(Map<String, dynamic> product) async {
    if (!_useClientSync()) {
      return await _legacyRpc!('update_product', {'p_input': product}) as int;
    }
    final response = ClientCommandResponse.from(await _transport.invoke(
      'update_product_client_sync_v1',
      {'p_product': product},
    ));
    if (response.code != 200 || response.data['productId'] is! num) {
      throw StateError('Product save was rejected');
    }
    await applyClientCommandReplacements(response);
    return (response.data['productId'] as num).toInt();
  }

  @override
  Future<void> updateProductInventoryContexts(
    int productId,
    List<Map<String, dynamic>> contexts,
  ) async {
    if (!_useClientSync()) {
      await _legacyRpc!('update_product_inventory_contexts', {
        'p_product_id': productId,
        'p_contexts': contexts,
      });
      return;
    }
    final response = ClientCommandResponse.from(await _transport.invoke(
      'update_product_inventory_contexts_client_sync_v1',
      {'p_product_id': productId, 'p_contexts': contexts},
    ));
    if (response.code != 200) {
      throw StateError('Product inventory context update was rejected');
    }
    await applyClientCommandReplacements(response);
  }
}

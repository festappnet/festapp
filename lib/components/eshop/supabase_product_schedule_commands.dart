import 'package:festapp_core/eshop.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Typed adapter for the same receipted product-schedule owner used by MCP.
class SupabaseProductScheduleCommands {
  SupabaseProductScheduleCommands(SupabaseClient client,
      {required Map<String, dynamic> Function() productScope})
      : this.withTransport(
            ClientCommandTransport.supabase(client, durable: true),
            productScope: productScope);
  SupabaseProductScheduleCommands.withTransport(this._transport,
      {required Map<String, dynamic> Function() productScope})
      : _scope = productScope;
  final ClientCommandTransport _transport;
  final Map<String, dynamic> Function() _scope;

  Future<Map<String, dynamic>> _change(
      String action, Map<String, dynamic> payload) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
        'manage_product_schedule',
        {..._scope(), 'p_action': action, 'p_payload': payload}));
    if (response.code == 409) {
      throw StateError('PRICE_CHANGE_CONFLICT');
    }
    if (response.code != 200) {
      throw StateError(response.data['reason']?.toString() ??
          'Product schedule was rejected');
    }
    await applyClientCommandReplacements(response);
    return response.data;
  }

  Future<ProductPriceWave> ensureWave(DateTime time) async =>
      ProductPriceWave.fromJson(
          Map<String, dynamic>.from((await _change('ensure_wave', {
        'change_time': time.toUtc().toIso8601String(),
      }))['wave']));

  Future<void> saveTarget(ProductPriceWave wave, int productId, double? price,
      bool? hidden, int? priceRevision, int? visibilityRevision) async {
    await _change('save_target', {
      'product_id': productId,
      if (wave.id == null)
        'change_time': wave.time.toUtc().toIso8601String()
      else ...{
        'wave_id': wave.id,
        'expected_wave_revision': wave.revision,
      },
      'price': price?.toString(),
      'is_hidden': hidden,
      'expected_price_revision': priceRevision,
      'expected_visibility_revision': visibilityRevision,
    });
  }

  Future<void> moveWave(ProductPriceWave wave, DateTime time) async {
    await _change('move_wave', {
      'wave_id': wave.id,
      'expected_wave_revision': wave.revision,
      'change_time': time.toUtc().toIso8601String(),
    });
  }

  Future<void> cancelWave(ProductPriceWave wave) async {
    await _change('cancel_wave', {
      'wave_id': wave.id,
      'expected_wave_revision': wave.revision,
    });
  }

  Future<void> savePriceChange(int productId, double price, DateTime time,
      {int? changeId, int? revision}) async {
    await _change('save_price_change', {
      'product_id': productId,
      'price': price.toString(),
      'change_time': time.toUtc().toIso8601String(),
      if (changeId != null) 'change_id': changeId,
      if (revision != null) 'expected_revision': revision,
    });
  }

  Future<void> cancelPriceChange(
      int productId, int changeId, int revision) async {
    await _change('cancel_price_change', {
      'product_id': productId,
      'change_id': changeId,
      'expected_revision': revision,
    });
  }
}

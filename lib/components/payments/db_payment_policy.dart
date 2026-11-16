import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'payment_policy.dart';

/// JSON/RPC boundary; the settings widget only handles typed policy decisions.
class DbPaymentPolicy {
  DbPaymentPolicy([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<PaymentPolicy> load(int organizationId, int? unitId) async {
    final policy = PaymentPolicy.fromJson(
      await _client.rpc(
        'get_payment_method_policy',
        params: {'p_organization': organizationId, 'p_unit': unitId},
      ),
    );
    if (policy.organizationId != organizationId || policy.unitId != unitId) {
      throw const FormatException('Payment policy scope mismatch');
    }
    return policy;
  }

  Future<PaymentPolicyPreview> preview(PaymentPolicyChange change) async =>
      PaymentPolicyPreview.fromJson(
        change,
        await _client.rpc(
          'preview_payment_method_policy',
          params: {'input_data': change.toJson()},
        ),
      );

  Future<void> command(PaymentPolicyPreview preview) async {
    await _client.rpc(
      'command_payment_method_policy',
      params: {
        'input_data': preview.change.toJson(),
        'p_command_id': const Uuid().v4(),
        'p_confirmation': preview.confirmation,
      },
    );
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerOrderChangeException implements Exception {
  const CustomerOrderChangeException(this.key);
  final String key;
}

abstract interface class CustomerOrderChangesApi {
  Future<Map<String, dynamic>> call(Map<String, dynamic> body);
}

class CustomerOrderChangesClient implements CustomerOrderChangesApi {
  CustomerOrderChangesClient([SupabaseClient? client])
    : client = client ?? Supabase.instance.client;
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> call(Map<String, dynamic> body) async {
    try {
      final response = await client.functions
          .invoke('customer-order-changes', body: body)
          .timeout(const Duration(seconds: 20));
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['code'] != 200 && data['code'] != 202) {
        throw CustomerOrderChangeException(
          data['code'] == 409
              ? 'conflict'
              : data['code'] == 422
              ? 'invalid'
              : 'unavailable',
        );
      }
      return data;
    } on FunctionException catch (error) {
      throw CustomerOrderChangeException(
        error.status == 409
            ? 'conflict'
            : error.status == 422
            ? 'invalid'
            : error.status == 403
            ? 'unavailable'
            : 'failed',
      );
    }
  }
}

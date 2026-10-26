import 'package:supabase_flutter/supabase_flutter.dart';

typedef AccountDeletionInvoker = Future<Map<String, dynamic>> Function();

class AccountDeletionRequestResult {
  const AccountDeletionRequestResult({
    required this.maskedEmail,
    required this.expiresAt,
  });

  final String maskedEmail;
  final DateTime expiresAt;
}

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.code);
  final String code;
}

class AccountDeletionService {
  AccountDeletionService({AccountDeletionInvoker? invoke})
      : _invoke = invoke ?? _invokeEdgeFunction;

  final AccountDeletionInvoker _invoke;

  static Future<Map<String, dynamic>> _invokeEdgeFunction() async {
    final response = await Supabase.instance.client.functions
        .invoke('request-account-deletion', body: <String, dynamic>{});
    final data = response.data;
    if (data is! Map) throw const AccountDeletionException('request_failed');
    return data.cast<String, dynamic>();
  }

  Future<AccountDeletionRequestResult> request() async {
    final data = await _invoke();
    if (data['status'] != 'email_sent') {
      throw AccountDeletionException(
          data['error']?.toString() ?? 'request_failed');
    }
    final expiresAt = DateTime.tryParse(data['expiresAt']?.toString() ?? '');
    final maskedEmail = data['maskedEmail']?.toString();
    if (expiresAt == null || maskedEmail == null || maskedEmail.isEmpty) {
      throw const AccountDeletionException('invalid_response');
    }
    return AccountDeletionRequestResult(
        maskedEmail: maskedEmail, expiresAt: expiresAt);
  }
}

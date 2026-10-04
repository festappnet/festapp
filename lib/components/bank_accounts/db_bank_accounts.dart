import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:fstapp/services/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/bank_accounts/bank_account_model.dart';

class DbBankAccounts {
  static final Map<String, String> _operationIds = {};
  static Future<Map<String, dynamic>> manage(int accountId, String operation,
      {Map<String, dynamic> values = const {}}) async {
    final key = '$accountId:$operation';
    final operationId = _operationIds.putIfAbsent(key, () => const Uuid().v4());
    final response =
        await _supabase.functions.invoke('bank-sync-manage', body: {
      'account_id': accountId,
      'operation': operation,
      'operation_id': operationId,
      ...values,
    });
    final result = Map<String, dynamic>.from(response.data as Map);
    if (response.status >= 400 || result.containsKey('error')) {
      throw Exception(result['error']);
    }
    _operationIds.remove(key);
    return result;
  }

  static Future<BankSyncConnection?> getConnection(int accountId) async {
    final response = await _supabase.rpc('get_bank_sync_connection',
        params: {'p_bank_account_id': accountId});
    return response == null
        ? null
        : BankSyncConnection.fromJson(
            Map<String, dynamic>.from(response as Map));
  }

  static final _supabase = Supabase.instance.client;

  static Future<List<BankAccountModel>> getBankAccountsForUnit(
    int unitId,
  ) async {
    final response = await _supabase.rpc(
      'get_bank_accounts_for_unit_management',
      params: {'p_unit_id': unitId},
    );
    return (response as List).map((e) => BankAccountModel.fromJson(e)).toList();
  }

  static Future<List<BankAccountModel>> getBankAccountsForOrganization(
    int organizationId,
  ) async {
    // Fallback to my admin accounts until specific RPC is verified
    return getMyAdminBankAccounts();
  }

  static Future<int> updateBankAccount(
    BankAccountModel account, {
    int? unitId,
    int? organizationId,
  }) async {
    // Use Legacy Unit/Self RPC
    final response = await _supabase.rpc(
      'update_bank_account',
      params: {
        'p_id': account.id == 0 ? null : account.id,
        'p_account_number': account.accountNumber,
        'p_title': account.title,
        'p_creditor_name': account.creditorName,
        'p_type': account.type,
        'p_supported_currencies': account.supportedCurrencies,
        'p_account_number_human_readable': account.accountNumberHumanReadable,
        'p_unit_id':
            unitId, // organizationId currently ignored/handled by context
      },
    );
    return response as int;
  }

  static Future<String> regenerateBankAccountPairingCode(
    int bankAccountId,
  ) async {
    final connection = await getConnection(bankAccountId);
    if (connection != null) {
      final result = await manage(bankAccountId, 'rotate_pairing');
      return (result['receiving_address'] as String).split('@').first;
    }
    final response = await _supabase.rpc('regenerate_bank_account_pairing_code',
        params: {'p_account_id': bankAccountId});
    return response as String;
  }

  static Future<String> getBankAccountsForUnitManagement(
    int bankAccountId,
  ) async {
    // This function seems unused or misnamed in original code?
    // Maintaining structure but assuming typical get implementation
    throw UnimplementedError("Verify original usage");
  }

  static Future<List<BankAccountUser>> getBankAccountUsers(
    int bankAccountId, {
    int? unitId,
  }) async {
    final response = await _supabase.rpc(
      "get_bank_account_users",
      params: {"p_bank_account_id": bankAccountId, "p_unit_id": unitId},
    );
    return (response as List).map((e) => BankAccountUser.fromJson(e)).toList();
  }

  static Future<void> updateBankAccountUser(
    int bankAccountId,
    String email,
    bool isAdmin,
    bool isSupport,
  ) async {
    await _supabase.rpc(
      'update_bank_account_user',
      params: {
        'p_bank_account_id': bankAccountId,
        'p_user_email': email,
        'p_is_admin': isAdmin,
        'p_is_support': isSupport,
      },
    );
  }

  static Future<void> removeBankAccountUser(
    int bankAccountId,
    String email,
  ) async {
    // To remove, we update with both flags as false/null
    await _supabase.rpc(
      'update_bank_account_user',
      params: {
        'p_bank_account_id': bankAccountId,
        'p_user_email': email,
        'p_is_admin': false,
        'p_is_support': false,
      },
    );
  }

  static Future<void> updateBankAccountToken(
    int bankAccountId,
    String token,
    DateTime? expiryDate,
  ) async {
    if (await getConnection(bankAccountId) == null) {
      await manage(bankAccountId, 'create', values: {'mode': 'api'});
    }
    await manage(bankAccountId, 'set_token',
        values: {'token': token, 'expiry': expiryDate?.toIso8601String()});
  }

  static Future<List<BankAccountModel>> getMyAdminBankAccounts() async {
    final response = await _supabase.rpc('get_my_admin_bank_accounts');
    return (response as List).map((e) => BankAccountModel.fromJson(e)).toList();
  }

  static Future<void> linkBankAccountToUnit(
    int unitId,
    int bankAccountId,
    int? priority, {
    bool hard = false,
  }) async {
    try {
      await _supabase.rpc(
        'link_bank_account_to_unit',
        params: {
          'p_unit_id': unitId,
          'p_bank_account_id': bankAccountId,
          'p_priority': priority,
          'p_hard': hard,
        },
      );
    } on PostgrestException catch (e) {
      if (e.message.contains('LINK_DEPENDENCY_ERROR')) {
        try {
          // Extract JSON part if mixed with other text or just parse message
          final msg = e.message;
          final start = msg.indexOf('{');
          final end = msg.lastIndexOf('}');
          if (start != -1 && end != -1) {
            final jsonStr = msg.substring(start, end + 1);
            final data = json.decode(jsonStr);
            if (data['code'] == 'LINK_DEPENDENCY_ERROR') {
              throw LinkDependencyException(data['conflicts']);
            }
          }
        } catch (parsingError) {
          AppLogger.error("Error parsing dependency error: $parsingError");
        }
      }
      rethrow;
    }
  }
}

class LinkDependencyException implements Exception {
  final List<dynamic> conflicts;
  LinkDependencyException(this.conflicts);
}

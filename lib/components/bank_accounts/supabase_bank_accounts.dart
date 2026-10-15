import 'package:flutter/foundation.dart';
import 'package:festapp_core/eshop.dart';
import 'package:uuid/uuid.dart';

import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:fstapp/services/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseBankAccounts {
  SupabaseBankAccounts(this._supabase);
  final SupabaseClient _supabase;
  final connectionChanges = ValueNotifier<({int accountId, int revision})>(
      (accountId: 0, revision: 0));
  final Map<int, String> _connectionSnapshots = {};

  void _connectionChanged(int accountId) {
    connectionChanges.value = (
      accountId: accountId,
      revision: connectionChanges.value.revision + 1,
    );
  }

  final Map<String, String> _operationIds = {};
  Future<Map<String, dynamic>> manage(
    int accountId,
    String operation, {
    Map<String, dynamic> values = const {},
  }) async {
    final payloadHash = sha256.convert(utf8.encode(jsonEncode(values)));
    final key = '$accountId:$operation:$payloadHash';
    final operationId = _operationIds.putIfAbsent(key, () => const Uuid().v4());
    late final FunctionResponse response;
    try {
      response = await _supabase.functions.invoke(
        'bank-sync-manage',
        body: {
          'account_id': accountId,
          'operation': operation,
          'operation_id': operationId,
          ...values,
        },
      );
    } on FunctionException catch (error) {
      throw BankSyncError.fromResponse(
        error.details is Map ? error.details as Map : const {},
      );
    }
    final result = Map<String, dynamic>.from(response.data as Map);
    if (response.status >= 400 || result.containsKey('error')) {
      throw BankSyncError.fromResponse(result);
    }
    _operationIds.remove(key);
    if (['resume', 'suspend', 'sync', 'set_token', 'create']
        .contains(operation)) {
      _connectionChanged(accountId);
    }
    if (result.containsKey('verification_error')) {
      throw BankSyncError.fromResponse(result);
    }
    return result;
  }

  Future<BankSyncConnection?> getConnection(int accountId) async {
    final response = await _supabase.functions.invoke(
      'bank-sync-manage',
      body: {'account_id': accountId, 'operation': 'status'},
    );
    if (response.data == null) return null;
    final connection = BankSyncConnection.fromJson(
        Map<String, dynamic>.from(response.data as Map));
    final snapshot = jsonEncode(connection.toJson());
    final previous = _connectionSnapshots[accountId];
    _connectionSnapshots[accountId] = snapshot;
    if (previous != null && previous != snapshot) _connectionChanged(accountId);
    return connection;
  }

  Future<List<BankAccountModel>> getBankAccountsForUnit(
    int unitId,
  ) async {
    final response = await _supabase.rpc(
      'get_bank_accounts_for_unit_management',
      params: {'p_unit_id': unitId},
    );
    return (response as List).map((e) => BankAccountModel.fromJson(e)).toList();
  }

  Future<List<BankAccountModel>> getBankAccountsForOrganization(
    int organizationId,
  ) async {
    // Fallback to my admin accounts until specific RPC is verified
    return getMyAdminBankAccounts();
  }

  Future<int> updateBankAccount(
    BankAccountModel account, {
    int? unitId,
    int? organizationId,
  }) async {
    // Account details remain owned by Festapp; SQL queues the BankSync update.
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
    final id = response as int;
    if (account.id != 0) await manage(id, 'update_details');
    return id;
  }

  Future<String> regenerateBankAccountPairingCode(
    int bankAccountId,
  ) async {
    final result = await manage(bankAccountId, 'rotate_pairing');
    return (result['receiving_address'] as String).split('@').first;
  }

  Future<List<BankAccountUser>> getBankAccountUsers(
    int bankAccountId, {
    int? unitId,
  }) async {
    final response = await _supabase.rpc(
      "get_bank_account_users",
      params: {"p_bank_account_id": bankAccountId, "p_unit_id": unitId},
    );
    return (response as List).map((e) => BankAccountUser.fromJson(e)).toList();
  }

  Future<void> updateBankAccountUser(
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

  Future<void> removeBankAccountUser(
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

  Future<void> updateBankAccountToken(
    int bankAccountId,
    String token,
    DateTime? expiryDate,
  ) async {
    if (await getConnection(bankAccountId) == null) {
      await manage(bankAccountId, 'create', values: {'mode': 'api'});
    }
    await manage(
      bankAccountId,
      'set_token',
      values: {'token': token, 'expiry': expiryDate?.toIso8601String()},
    );
  }

  Future<List<BankAccountModel>> getMyAdminBankAccounts() async {
    final response = await _supabase.rpc('get_my_admin_bank_accounts');
    return (response as List).map((e) => BankAccountModel.fromJson(e)).toList();
  }

  Future<void> linkBankAccountToUnit(
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

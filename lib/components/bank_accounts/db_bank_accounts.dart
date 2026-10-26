import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_bank_accounts.dart';

/// Production composition owns operation intents for the lifetime of its client.
class DbBankAccounts {
  static final _clients = Expando<SupabaseBankAccounts>();
  static SupabaseBankAccounts get current {
    final client = Supabase.instance.client;
    return _clients[client] ??= SupabaseBankAccounts(client);
  }
}

class BankSyncError implements Exception {
  final String code;
  final bool tokenSaved;
  const BankSyncError(this.code, {this.tokenSaved = false});

  factory BankSyncError.fromResponse(Map<dynamic, dynamic> response) {
    final value = response['verification_error'] ?? response['error'];
    return BankSyncError(
      const ['fio_token_invalid_or_inactive', 'fio_receiving_account_mismatch']
              .contains(value)
          ? value as String
          : 'bank_sync_retry_required',
      tokenSaved: response['token_saved'] == true,
    );
  }

  @override
  String toString() => code;
}

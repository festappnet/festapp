/// Safe operational details supplied by the order bundle, never credentials.
class BankSyncWarning {
  final int? bankAccountId;
  final bool isAdmin;
  final String code;
  final String bankAccountTitle;
  final List<BankSyncContact> contacts;

  const BankSyncWarning({
    this.bankAccountId,
    this.isAdmin = false,
    required this.code,
    required this.bankAccountTitle,
    this.contacts = const [],
  });

  /// Migrated identities may represent the same administrator more than once.
  /// Delivery addresses are canonical; keep distinct people without an address.
  List<BankSyncContact> get uniqueContacts {
    final result = <String, BankSyncContact>{};
    for (final contact in contacts) {
      final email = contact.email?.trim();
      final name = contact.name.trim();
      if (name.isEmpty && (email == null || email.isEmpty)) continue;
      final key = email?.isNotEmpty == true
          ? 'email:${email!.toLowerCase()}'
          : 'name:${name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}';
      final previous = result[key];
      if (previous == null || (previous.name.isEmpty && name.isNotEmpty)) {
        result[key] = BankSyncContact(name: name, email: email);
      }
    }
    return result.values.toList(growable: false);
  }

  Map<String, dynamic> toJson() => {
    'bank_account_id': bankAccountId,
    'is_admin': isAdmin,
    'code': code,
    'bank_account_title': bankAccountTitle,
    'contacts': uniqueContacts
        .map((contact) => {'name': contact.name, 'email': contact.email})
        .toList(),
  };

  factory BankSyncWarning.fromJson(Map<String, dynamic> json) =>
      BankSyncWarning(
        bankAccountId: json['bank_account_id'] as int?,
        isAdmin: json['is_admin'] == true,
        code: json['code'] as String? ?? 'not_configured',
        bankAccountTitle: json['bank_account_title'] as String? ?? '',
        contacts: (json['contacts'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(
              (contact) => BankSyncContact(
                name: contact['name'] as String? ?? '',
                email: contact['email'] as String?,
              ),
            )
            .toList(),
      );
}

class BankSyncContact {
  final String name;
  final String? email;
  const BankSyncContact({required this.name, this.email});
}

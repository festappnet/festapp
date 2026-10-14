/// Safe operational details supplied by the order bundle, never credentials.
class BankSyncWarning {
  final String code;
  final String bankAccountTitle;
  final List<BankSyncContact> contacts;

  const BankSyncWarning({
    required this.code,
    required this.bankAccountTitle,
    this.contacts = const [],
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'bank_account_title': bankAccountTitle,
        'contacts': contacts
            .map((contact) => {
                  'name': contact.name,
                  'email': contact.email,
                })
            .toList(),
      };

  factory BankSyncWarning.fromJson(Map<String, dynamic> json) =>
      BankSyncWarning(
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

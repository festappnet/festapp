class BankAccountModel {
  final int id;
  // force cache invalidation
  final String? accountNumber;
  final String? title;
  final String? creditorName;
  final String type;
  final bool isAdmin;
  final int priority;

  final String? tokenMasked;
  final DateTime? tokenExpiryDate;
  final List<String> supportedCurrencies;
  final List<String> linkedUnits;
  final String? pairingCode;
  final String? accountNumberHumanReadable;
  final DateTime? lastFetchTime;
  final DateTime? lastFioFetchTime;

  BankAccountModel({
    required this.id,
    this.accountNumber,
    this.title,
    this.creditorName,
    this.priority = 0,
    this.type = 'FIO',
    this.isAdmin = false,
    this.tokenMasked,
    this.tokenExpiryDate,
    this.supportedCurrencies = const [],
    this.linkedUnits = const [],
    this.accountNumberHumanReadable,
    this.lastFetchTime,
    this.lastFioFetchTime,
    this.pairingCode,
  });

  factory BankAccountModel.fromJson(Map<String, dynamic> json) {
    return BankAccountModel(
      id: json['id'],
      accountNumber: json['account_number'],
      title: json['title'],
      creditorName: json['creditor_name'],
      priority: json['priority'] ?? 0,
      type: json['type'] ?? 'FIO',
      isAdmin: json['is_admin'] ?? false,
      tokenMasked: json['token_masked'],
      tokenExpiryDate: json['token_expiry_date'] != null
          ? DateTime.parse(json['token_expiry_date'])
          : null,
      supportedCurrencies:
          (json['supported_currencies'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      linkedUnits:
          (json['linked_units'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      accountNumberHumanReadable: json['account_number_human_readable'],
      lastFioFetchTime: json['last_fio_fetch_time'] != null
          ? DateTime.parse(json['last_fio_fetch_time'])
          : null,
      lastFetchTime: json['last_fetch_time'] != null
          ? DateTime.parse(json['last_fetch_time'])
          : null,
      pairingCode: json['pairing_code'] == '************'
          ? null
          : json['pairing_code'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'account_number': accountNumber,
      'title': title,
      'creditor_name': creditorName,
      'priority': priority,
      'type': type,
      'is_admin': isAdmin,
      'token_masked': tokenMasked,
      'token_expiry_date': tokenExpiryDate?.toIso8601String(),
      'supported_currencies': supportedCurrencies,
      'account_number_human_readable': accountNumberHumanReadable,
      'last_fio_fetch_time': lastFioFetchTime?.toIso8601String(),
      'last_fetch_time': lastFetchTime?.toIso8601String(),
      'pairing_code': pairingCode,
    };
  }

  BankAccountModel copyWith({
    int? id,
    String? accountNumber,
    String? title,
    String? creditorName,
    String? type,
    bool? isAdmin,
    int? priority,
    String? tokenMasked,
    DateTime? tokenExpiryDate,
    List<String>? supportedCurrencies,
    List<String>? linkedUnits,
    String? accountNumberHumanReadable,
    DateTime? lastFetchTime,
    DateTime? lastFioFetchTime,
    String? pairingCode,
  }) {
    return BankAccountModel(
      id: id ?? this.id,
      accountNumber: accountNumber ?? this.accountNumber,
      title: title ?? this.title,
      creditorName: creditorName ?? this.creditorName,
      type: type ?? this.type,
      isAdmin: isAdmin ?? this.isAdmin,
      priority: priority ?? this.priority,
      tokenMasked: tokenMasked ?? this.tokenMasked,
      tokenExpiryDate: tokenExpiryDate ?? this.tokenExpiryDate,
      supportedCurrencies: supportedCurrencies ?? this.supportedCurrencies,
      linkedUnits: linkedUnits ?? this.linkedUnits,
      accountNumberHumanReadable:
          accountNumberHumanReadable ?? this.accountNumberHumanReadable,
      lastFetchTime: lastFetchTime ?? this.lastFetchTime,
      lastFioFetchTime: lastFioFetchTime ?? this.lastFioFetchTime,
      pairingCode: pairingCode ?? this.pairingCode,
    );
  }
}

class BankAccountUser {
  final String userId;
  final String? email;
  final String? name;
  final String? surname;
  final bool isAdmin;
  final bool isSupport;

  BankAccountUser({
    required this.userId,
    this.email,
    this.name,
    this.surname,
    this.isAdmin = false,
    this.isSupport = false,
  });

  factory BankAccountUser.fromJson(Map<String, dynamic> json) {
    return BankAccountUser(
      userId: json['user_id'],
      email: json['email'],
      name: json['name'],
      surname: json['surname'],
      isAdmin: json['is_admin'] ?? false,
      isSupport: json['is_support'] ?? false,
    );
  }
}

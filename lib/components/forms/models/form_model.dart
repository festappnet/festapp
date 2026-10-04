import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/bank_accounts/bank_account_model.dart';
import 'package:fstapp/services/time_helper.dart';

/// Represents the statistics for a form's responses.
class FormStatsModel {
  final int total;
  final int storno;
  final int paidOrSent;
  final int ordered;

  FormStatsModel({
    this.total = 0,
    this.storno = 0,
    this.paidOrSent = 0,
    this.ordered = 0,
  });

  /// Creates an instance from a JSON map.
  factory FormStatsModel.fromJson(Map<String, dynamic> json) {
    return FormStatsModel(
      total: json['total'] ?? 0,
      storno: json['storno'] ?? 0,
      paidOrSent: json['paid_or_sent'] ?? 0,
      ordered: json['ordered'] ?? 0,
    );
  }
}

class FormModel {
  int? id;
  DateTime? createdAt;
  String? title;
  Map<String, dynamic>? data;
  String? key;
  int? occasionId;
  OccasionModel? occasionModel;
  int? blueprint;
  String? type;
  BankAccountModel? bankAccount;
  int? bankAccountId;
  int? deadlineDurationSeconds;
  bool? isOpen;
  String? accountNumber;
  String? secret;
  String? header;
  String? headerOff;
  String? link;
  // UPDATED: Now non-nullable.
  List<FormFieldModel> relatedFields;
  bool get usesSeatSelection => relatedFields.any((field) =>
      field.isTicketField == true &&
      field.type == FormHelper.fieldTypeSpot &&
      field.isHidden != true);

  final Set<int> deletedFieldIds = {};
  final Set<int> deletedProductIds = {};

  void removeField(FormFieldModel field) {
    final removed = [
      field,
      if (field.type == 'ticket')
        ...relatedFields.where((f) => f.isTicketField == true)
    ];
    for (final item in removed) {
      if (item.id != null) deletedFieldIds.add(item.id!);
      relatedFields.remove(item);
    }
  }

  List<BankAccountModel>? availableBankAccounts;
  FormStatsModel? stats;
  bool? isReminderEnabled;
  bool? canDelete;

  static const String metaIsCardDesign = "is_card_design";
  static const String metaIsReminderEnabled = "is_reminder_enabled";
  static const String metaFields = "fields";
  static const String metaVariableSymbol = "variable_symbol";
  static const String metaPaymentMessage = "payment_message";
  static const String metaType = "type";
  static const String metaStartingNumber = "starting_number";
  static const String metaStartTime = "start_time";
  static const String metaEndTime = "end_time";
  static const String metaEnableCountdown = "enable_countdown";
  static const String metaCountdownStyle = "countdown_style";
  static const String metaCountdownTitle = "countdown_title";
  static const String metaPrimaryColor = "primary_color";
  static const String metaSecondaryColor = "secondary_color";
  static const String metaFontFamily = "font_family";
  static const String metaDesign = "design";
  static const String metaSchedule = "schedule";

  FormModel({
    this.id,
    this.createdAt,
    this.title,
    this.data,
    this.key,
    this.occasionId,
    this.occasionModel,
    this.blueprint,
    this.type,
    this.bankAccount,
    this.bankAccountId,
    this.deadlineDurationSeconds,
    this.isOpen,
    this.accountNumber,
    this.secret,
    this.header,
    this.headerOff,
    this.link,
    List<FormFieldModel>? relatedFields,
    this.availableBankAccounts,
    this.stats,
    this.isReminderEnabled,
    this.canDelete,
  }) : relatedFields = relatedFields ?? [];

  factory FormModel.fromJson(Map<String, dynamic> json) {
    OccasionModel? parsedOccasionModel;
    int? parsedOccasionId;

    final occasionData = json[Tb.forms.occasion];
    if (occasionData is Map<String, dynamic>) {
      parsedOccasionModel = OccasionModel.fromJson(occasionData);
      parsedOccasionId = parsedOccasionModel.id;
    } else if (occasionData is int) {
      parsedOccasionId = occasionData;
    }

    return FormModel(
      id: json[Tb.forms.id],
      createdAt: json[Tb.forms.created_at] != null
          ? DateTime.parse(json[Tb.forms.created_at])
          : null,
      title: json[Tb.forms.title],
      data: _parseMetadata(json[Tb.forms.data]),
      key: json[Tb.forms.key],
      occasionId: parsedOccasionId,
      occasionModel: parsedOccasionModel,
      blueprint: json[Tb.forms.blueprint],
      type: json[Tb.forms.type],
      bankAccountId: json[Tb.forms.bank_account],
      deadlineDurationSeconds: json[Tb.forms.deadline_duration_seconds],
      isOpen: json[Tb.forms.is_open],
      accountNumber: json['account_number'],
      secret: json['secret'],
      header: json[Tb.forms.header],
      headerOff: json[Tb.forms.header_off],
      link: json[Tb.forms.link],
      relatedFields: json['fields'] != null
          ? (json['fields'] as List)
              .map((field) => FormFieldModel.fromJson(field))
              .toList()
          : [],
      availableBankAccounts: json['available_bank_accounts'] != null
          ? (json['available_bank_accounts'] as List)
              .map((account) => BankAccountModel.fromJson(account))
              .toList()
          : null,
      stats:
          json['stats'] != null ? FormStatsModel.fromJson(json['stats']) : null,
      isReminderEnabled: json['is_reminder_feature_enabled'],
      canDelete: json['can_delete'] ??
          true, // Default to true if not present to avoid breaking existing clients slightly, but realistically it comes from DB.
    );
  }

  // Older JSONB concatenations can produce [null, {settings}] instead of an
  // object. Normalize once at the read boundary; all writes remain objects.
  static Map<String, dynamic>? _parseMetadata(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return Map.of(value);
    if (value is List) {
      final metadata = <String, dynamic>{};
      for (final entry in value) {
        if (entry == null) continue;
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Form metadata must contain objects');
        }
        metadata.addAll(entry);
      }
      return metadata;
    }
    throw const FormatException('Form metadata must be an object');
  }

  Map<String, dynamic> toJson() => {
        Tb.forms.id: id,
        Tb.forms.created_at: createdAt?.toIso8601String(),
        Tb.forms.title: title,
        Tb.forms.data: data,
        Tb.forms.key: key,
        Tb.forms.occasion: occasionId,
        Tb.forms.blueprint: blueprint,
        Tb.forms.type: type,
        Tb.forms.bank_account: bankAccount?.id,
        Tb.forms.deadline_duration_seconds: deadlineDurationSeconds,
        Tb.forms.is_open: isOpen,
        'account_number': accountNumber,
        'secret': secret,
        Tb.forms.header: header,
        Tb.forms.header_off: headerOff,
        Tb.forms.link: link,
        'fields': relatedFields,
      };

  Map<String, dynamic> toEditedJson() => {
        'deleted_field_ids': deletedFieldIds.toList(),
        'deleted_product_ids': deletedProductIds.toList(),
        Tb.forms.id: id,
        Tb.forms.created_at: createdAt?.toIso8601String(),
        Tb.forms.title: title,
        Tb.forms.data: data,
        Tb.forms.key: key,
        Tb.forms.occasion: occasionId,
        Tb.forms.blueprint: blueprint,
        Tb.forms.type: type,
        Tb.forms.bank_account: bankAccount?.id,
        Tb.forms.deadline_duration_seconds: deadlineDurationSeconds,
        Tb.forms.is_open: isOpen,
        Tb.forms.header: header,
        Tb.forms.header_off: headerOff,
        Tb.forms.link: link,
        Tb.forms.header: header,
        Tb.forms.header_off: headerOff,
        Tb.forms.link: link,
        Tb.form_fields.table: relatedFields,
      };

  // Helper for Design Data
  Map<String, dynamic> get _designData =>
      data?[metaDesign] as Map<String, dynamic>? ?? {};

  Map<String, dynamic> get _mutableDesignData {
    data ??= {};
    return data!.putIfAbsent(metaDesign, () => <String, dynamic>{})
        as Map<String, dynamic>;
  }

  // Helper for Schedule Data
  Map<String, dynamic> get _scheduleData =>
      data?[metaSchedule] as Map<String, dynamic>? ?? {};

  Map<String, dynamic> get _mutableScheduleData {
    data ??= {};
    return data!.putIfAbsent(metaSchedule, () => <String, dynamic>{})
        as Map<String, dynamic>;
  }

  DateTime? get startTime {
    if (_scheduleData.containsKey(metaStartTime)) {
      return DateTime.tryParse(_scheduleData[metaStartTime])?.toOccasionTime();
    }
    return null;
  }

  set startTime(DateTime? value) {
    if (value == null) {
      _scheduleData.remove(metaStartTime);
    } else {
      _mutableScheduleData[metaStartTime] =
          value.toUtcFromOccasionTime().toIso8601String();
    }
  }

  DateTime? get endTime {
    if (_scheduleData.containsKey(metaEndTime)) {
      return DateTime.tryParse(_scheduleData[metaEndTime])?.toOccasionTime();
    }
    return null;
  }

  set endTime(DateTime? value) {
    if (value == null) {
      _scheduleData.remove(metaEndTime);
    } else {
      _mutableScheduleData[metaEndTime] =
          value.toUtcFromOccasionTime().toIso8601String();
    }
  }

  bool get enableCountdown {
    if (_scheduleData.containsKey(metaEnableCountdown)) {
      return _scheduleData[metaEnableCountdown] == true;
    }
    return false;
  }

  set enableCountdown(bool value) {
    _mutableScheduleData[metaEnableCountdown] = value;
  }

  String get countdownStyle {
    if (_designData.containsKey(metaCountdownStyle)) {
      return _designData[metaCountdownStyle];
    }
    return 'normal';
  }

  set countdownStyle(String value) {
    _mutableDesignData[metaCountdownStyle] = value;
  }

  String? get countdownTitle {
    if (_scheduleData.containsKey(metaCountdownTitle)) {
      return _scheduleData[metaCountdownTitle];
    }
    return null;
  }

  set countdownTitle(String? value) {
    if (value == null) {
      _scheduleData.remove(metaCountdownTitle);
    } else {
      _mutableScheduleData[metaCountdownTitle] = value;
    }
  }

  int? _parseColor(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      if (value.startsWith('#')) {
        String hex = value.substring(1);
        if (hex.length == 6) {
          hex = "FF$hex";
        }
        return int.tryParse(hex, radix: 16);
      }
      return int.tryParse(value);
    }
    return null;
  }

  String _colorToHex(int value) {
    return '#${value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }

  int? get primaryColor {
    if (_designData.containsKey(metaPrimaryColor)) {
      return _parseColor(_designData[metaPrimaryColor]);
    }
    return null;
  }

  set primaryColor(int? value) {
    if (value == null) {
      _designData.remove(metaPrimaryColor);
    } else {
      _mutableDesignData[metaPrimaryColor] = _colorToHex(value);
    }
  }

  int? get secondaryColor {
    if (_designData.containsKey(metaSecondaryColor)) {
      return _parseColor(_designData[metaSecondaryColor]);
    }
    return null;
  }

  set secondaryColor(int? value) {
    if (value == null) {
      _designData.remove(metaSecondaryColor);
    } else {
      _mutableDesignData[metaSecondaryColor] = _colorToHex(value);
    }
  }

  String? get fontFamily {
    if (_designData.containsKey(metaFontFamily)) {
      return _designData[metaFontFamily];
    }
    return null;
  }

  set fontFamily(String? value) {
    if (value == null) {
      _designData.remove(metaFontFamily);
    } else {
      _mutableDesignData[metaFontFamily] = value;
    }
  }

  bool get isCardDesign {
    if (_designData.containsKey(metaIsCardDesign)) {
      return _designData[metaIsCardDesign] == true;
    }
    return false;
  }

  set isCardDesign(bool value) {
    _mutableDesignData['is_card_design'] = value;
  }

  static const String metaCommunicationTone = "communication_tone";

  String? get communicationTone {
    return data?[metaCommunicationTone];
  }

  /// Returns a list of available supported currencies.
  List<String> getSupportedCurrencies() {
    if (bankAccount != null && bankAccount!.supportedCurrencies.isNotEmpty) {
      return bankAccount!.supportedCurrencies;
    } else if (availableBankAccounts != null) {
      final currencySet = <String>{};
      for (var account in availableBankAccounts!) {
        currencySet.addAll(account.supportedCurrencies);
      }
      return currencySet.toList();
    } else {
      return [];
    }
  }

  @override
  String toString() {
    return title ?? link ?? "---";
  }
}

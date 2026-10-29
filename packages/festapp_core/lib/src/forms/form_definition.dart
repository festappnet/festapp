import 'package:festapp_core/forms.dart';
import 'package:festapp_core/json_values.dart';

const _unchanged = Object();

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

class FormDefinition {
  final bool demoSimulation;
  final int? participantCapacity;
  final bool waitlistEnabled;
  final bool showRemainingCapacity;
  final int? waitlistOfferDurationSeconds;
  final FormCapacityModel? capacity;
  final String? registrationMode;
  final Map<String, dynamic>? payments;
  bool get isWaitlist => registrationMode == 'waitlist';
  final int? id;
  final DateTime? createdAt;
  final String? title;
  final Map<String, dynamic>? data;
  final String? key;
  final int? occasionId;
  final int? blueprint;
  final String? type;
  final int? bankAccountId;
  final int? deadlineDurationSeconds;

  int effectiveDeadlineDurationSeconds({int? occasionDefault}) =>
      deadlineDurationSeconds ?? occasionDefault ?? 604800;
  final bool? isOpen;
  final String? accountNumber;
  final String? secret;
  final String? header;
  final String? headerOff;
  final String? link;
  // UPDATED: Now non-nullable.
  final List<FormFieldDefinition> relatedFields;
  bool get usesSeatSelection => usesSeatSelectionIn(relatedFields);
  static bool usesSeatSelectionIn(Iterable<FormFieldDefinition> fields) =>
      fields.any(
        (field) =>
            field.isTicketField == true &&
            field.type == FormMetadata.fieldTypeSpot &&
            field.isHidden != true,
      );

  final FormStatsModel? stats;
  final bool? isReminderEnabled;
  final bool? canDelete;

  static const String metaIsCardDesign = "is_card_design";
  static const String metaReminderIntervalSeconds = "reminder_interval_seconds";
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
  static const String metaShowBeforeStartMessage = "show_before_start_message";
  static const String metaBeforeStartMessage = "before_start_message";
  static const String metaCountdownTitle = "countdown_title";
  static const String metaPrimaryColor = "primary_color";
  static const String metaSecondaryColor = "secondary_color";
  static const String metaFontFamily = "font_family";
  static const String metaDesign = "design";
  static const String metaSchedule = "schedule";

  FormDefinition({
    this.demoSimulation = false,
    this.participantCapacity,
    this.waitlistEnabled = false,
    this.showRemainingCapacity = true,
    this.waitlistOfferDurationSeconds,
    this.capacity,
    this.registrationMode,
    Map<String, dynamic>? payments,
    this.id,
    this.createdAt,
    this.title,
    Map<String, dynamic>? data,
    this.key,
    this.occasionId,
    this.blueprint,
    this.type,
    this.bankAccountId,
    this.deadlineDurationSeconds,
    this.isOpen,
    this.accountNumber,
    this.secret,
    this.header,
    this.headerOff,
    this.link,
    List<FormFieldDefinition>? relatedFields,
    this.stats,
    this.isReminderEnabled,
    this.canDelete,
  }) : payments = payments == null
           ? null
           : freezeJsonValue(payments) as Map<String, dynamic>,
       data = data == null
           ? null
           : freezeJsonValue(data) as Map<String, dynamic>,
       relatedFields = List.unmodifiable(relatedFields ?? const []);

  factory FormDefinition.fromJson(Map<String, dynamic> json) {
    final occasionData = json['occasion'];
    final parsedOccasionId = occasionData is Map
        ? occasionData['id']
        : occasionData;

    return FormDefinition(
      demoSimulation: json['demo_simulation'] == true,
      participantCapacity: json['participant_capacity'],
      waitlistEnabled: json['waitlist_enabled'] == true,
      showRemainingCapacity: json['show_remaining_capacity'] != false,
      waitlistOfferDurationSeconds: json['waitlist_offer_duration_seconds'],
      capacity: json['capacity'] is Map<String, dynamic>
          ? FormCapacityModel.fromJson(json['capacity'])
          : null,
      registrationMode: json['registrationMode'],
      payments: json['payments'] is Map
          ? (json['payments'] as Map).cast<String, dynamic>()
          : null,
      id: json['id'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      title: json['title'],
      data: _parseMetadata(json['data']),
      key: json['key'],
      occasionId: parsedOccasionId,
      blueprint: json['blueprint'],
      type: json['type'],
      bankAccountId: json['bank_account'],
      deadlineDurationSeconds: json['deadline_duration_seconds'],
      isOpen: json['is_open'],
      accountNumber: json['account_number'],
      secret: json['secret'],
      header: json['header'],
      headerOff: json['header_off'],
      link: json['link'],
      relatedFields: json['fields'] != null
          ? (json['fields'] as List)
                .map((field) => FormFieldDefinition.fromJson(field))
                .toList()
          : [],
      stats: json['stats'] != null
          ? FormStatsModel.fromJson(json['stats'])
          : null,
      isReminderEnabled: json['is_reminder_feature_enabled'],
      canDelete:
          json['can_delete'] ??
          true, // Default to true if not present to avoid breaking existing clients slightly, but realistically it comes from DB.
    );
  }

  // Older JSONB concatenations can produce [null, {settings}] instead of an
  // object. Normalize once at the read boundary; all writes remain objects.
  static Map<String, dynamic>? _parseMetadata(dynamic value) {
    if (value == null) return null;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List) {
      final metadata = <String, dynamic>{};
      for (final entry in value) {
        if (entry == null) continue;
        if (entry is! Map) {
          throw const FormatException('Form metadata must contain objects');
        }
        metadata.addAll(Map<String, dynamic>.from(entry));
      }
      return metadata;
    }
    throw const FormatException('Form metadata must be an object');
  }

  Map<String, dynamic> toJson() => {
    'participant_capacity': participantCapacity,
    'waitlist_enabled': waitlistEnabled,
    'show_remaining_capacity': showRemainingCapacity,
    'waitlist_offer_duration_seconds': waitlistOfferDurationSeconds,
    if (payments != null) 'payments': payments,
    'id': id,
    'created_at': createdAt?.toIso8601String(),
    'title': title,
    'data': data,
    'key': key,
    'occasion': occasionId,
    'blueprint': blueprint,
    'type': type,
    'bank_account': bankAccountId,
    'deadline_duration_seconds': deadlineDurationSeconds,
    'is_open': isOpen,
    'account_number': accountNumber,
    'secret': secret,
    'header': header,
    'header_off': headerOff,
    'link': link,
    'fields': relatedFields,
  };

  // Helper for Design Data
  Map<String, dynamic> get _designData =>
      data?[metaDesign] as Map<String, dynamic>? ?? {};

  // Helper for Schedule Data
  Map<String, dynamic> get _scheduleData =>
      data?[metaSchedule] as Map<String, dynamic>? ?? {};

  DateTime? get startTimeUtc {
    final value = _scheduleData[metaStartTime];
    return value is String ? DateTime.tryParse(value) : null;
  }

  FormDefinition withStartTimeUtc(DateTime? value) {
    if (value == null && !_scheduleData.containsKey(metaStartTime)) return this;
    final section = Map<String, dynamic>.from(_scheduleData);

    if (value == null) {
      section.remove(metaStartTime);
    } else {
      section[metaStartTime] = value.toUtc().toIso8601String();
    }

    return copyWith(data: {...?data, metaSchedule: section});
  }

  DateTime? get endTimeUtc {
    final value = _scheduleData[metaEndTime];
    return value is String ? DateTime.tryParse(value) : null;
  }

  FormDefinition withEndTimeUtc(DateTime? value) {
    if (value == null && !_scheduleData.containsKey(metaEndTime)) return this;
    final section = Map<String, dynamic>.from(_scheduleData);

    if (value == null) {
      section.remove(metaEndTime);
    } else {
      section[metaEndTime] = value.toUtc().toIso8601String();
    }

    return copyWith(data: {...?data, metaSchedule: section});
  }

  bool get enableCountdown {
    if (_scheduleData.containsKey(metaEnableCountdown)) {
      return _scheduleData[metaEnableCountdown] == true;
    }
    return false;
  }

  FormDefinition withEnableCountdown(bool value) {
    final section = Map<String, dynamic>.from(_scheduleData);

    section[metaEnableCountdown] = value;

    return copyWith(data: {...?data, metaSchedule: section});
  }

  bool get showBeforeStartMessage =>
      _scheduleData[metaShowBeforeStartMessage] == true;

  FormDefinition withShowBeforeStartMessage(bool value) {
    final section = Map<String, dynamic>.from(_scheduleData);
    section[metaShowBeforeStartMessage] = value;
    return copyWith(data: {...?data, metaSchedule: section});
  }

  String? get beforeStartMessage =>
      _scheduleData[metaBeforeStartMessage] as String?;

  FormDefinition withBeforeStartMessage(String? value) {
    if (value == null && !_scheduleData.containsKey(metaBeforeStartMessage)) {
      return this;
    }
    final section = Map<String, dynamic>.from(_scheduleData);
    if (value == null) {
      section.remove(metaBeforeStartMessage);
    } else {
      section[metaBeforeStartMessage] = value;
    }
    return copyWith(data: {...?data, metaSchedule: section});
  }

  String get countdownStyle {
    if (_designData.containsKey(metaCountdownStyle)) {
      return _designData[metaCountdownStyle];
    }
    return 'normal';
  }

  FormDefinition withCountdownStyle(String value) {
    final section = Map<String, dynamic>.from(_designData);

    section[metaCountdownStyle] = value;

    return copyWith(data: {...?data, metaDesign: section});
  }

  String? get countdownTitle {
    if (_scheduleData.containsKey(metaCountdownTitle)) {
      return _scheduleData[metaCountdownTitle];
    }
    return null;
  }

  FormDefinition withCountdownTitle(String? value) {
    if (value == null && !_scheduleData.containsKey(metaCountdownTitle))
      return this;
    final section = Map<String, dynamic>.from(_scheduleData);

    if (value == null) {
      section.remove(metaCountdownTitle);
    } else {
      section[metaCountdownTitle] = value;
    }

    return copyWith(data: {...?data, metaSchedule: section});
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

  FormDefinition withPrimaryColor(int? value) {
    if (value == null && !_designData.containsKey(metaPrimaryColor))
      return this;
    final section = Map<String, dynamic>.from(_designData);

    if (value == null) {
      section.remove(metaPrimaryColor);
    } else {
      section[metaPrimaryColor] = _colorToHex(value);
    }

    return copyWith(data: {...?data, metaDesign: section});
  }

  int? get secondaryColor {
    if (_designData.containsKey(metaSecondaryColor)) {
      return _parseColor(_designData[metaSecondaryColor]);
    }
    return null;
  }

  FormDefinition withSecondaryColor(int? value) {
    if (value == null && !_designData.containsKey(metaSecondaryColor))
      return this;
    final section = Map<String, dynamic>.from(_designData);

    if (value == null) {
      section.remove(metaSecondaryColor);
    } else {
      section[metaSecondaryColor] = _colorToHex(value);
    }

    return copyWith(data: {...?data, metaDesign: section});
  }

  String? get backgroundMode => _designData['background_mode'] as String?;

  FormDefinition withBackgroundMode(String? value) {
    if (value != null && !const ['solid', 'gradient'].contains(value)) {
      throw ArgumentError.value(value, 'backgroundMode');
    }
    final section = Map<String, dynamic>.from(_designData);
    if (value == null) {
      section.remove('background_mode');
    } else {
      section['background_mode'] = value;
    }
    return copyWith(data: {...?data, metaDesign: section});
  }

  String? get fontFamily {
    if (_designData.containsKey(metaFontFamily)) {
      return _designData[metaFontFamily];
    }
    return null;
  }

  FormDefinition withFontFamily(String? value) {
    if (value == null && !_designData.containsKey(metaFontFamily)) return this;
    final section = Map<String, dynamic>.from(_designData);

    if (value == null) {
      section.remove(metaFontFamily);
    } else {
      section[metaFontFamily] = value;
    }

    return copyWith(data: {...?data, metaDesign: section});
  }

  bool get isCardDesign {
    if (_designData.containsKey(metaIsCardDesign)) {
      return _designData[metaIsCardDesign] == true;
    }
    return false;
  }

  FormDefinition withIsCardDesign(bool value) {
    final section = Map<String, dynamic>.from(_designData);

    section['is_card_design'] = value;

    return copyWith(data: {...?data, metaDesign: section});
  }

  static const String metaCommunicationTone = "communication_tone";

  String? get communicationTone {
    return data?[metaCommunicationTone];
  }

  @override
  String toString() {
    return title ?? link ?? "---";
  }

  FormDefinition copyWith({
    Object? participantCapacity = _unchanged,
    Object? waitlistEnabled = _unchanged,
    Object? showRemainingCapacity = _unchanged,
    Object? waitlistOfferDurationSeconds = _unchanged,
    Object? capacity = _unchanged,
    Object? registrationMode = _unchanged,
    Object? payments = _unchanged,
    Object? id = _unchanged,
    Object? createdAt = _unchanged,
    Object? title = _unchanged,
    Object? data = _unchanged,
    Object? key = _unchanged,
    Object? occasionId = _unchanged,
    Object? blueprint = _unchanged,
    Object? type = _unchanged,
    Object? bankAccountId = _unchanged,
    Object? deadlineDurationSeconds = _unchanged,
    Object? isOpen = _unchanged,
    Object? accountNumber = _unchanged,
    Object? secret = _unchanged,
    Object? header = _unchanged,
    Object? headerOff = _unchanged,
    Object? link = _unchanged,
    Object? relatedFields = _unchanged,
    Object? stats = _unchanged,
    Object? isReminderEnabled = _unchanged,
    Object? canDelete = _unchanged,
  }) => FormDefinition(
    demoSimulation: demoSimulation,
    participantCapacity: identical(participantCapacity, _unchanged)
        ? this.participantCapacity
        : participantCapacity as int?,
    waitlistEnabled: identical(waitlistEnabled, _unchanged)
        ? this.waitlistEnabled
        : waitlistEnabled as bool,
    showRemainingCapacity: identical(showRemainingCapacity, _unchanged)
        ? this.showRemainingCapacity
        : showRemainingCapacity as bool,
    waitlistOfferDurationSeconds:
        identical(waitlistOfferDurationSeconds, _unchanged)
        ? this.waitlistOfferDurationSeconds
        : waitlistOfferDurationSeconds as int?,
    capacity: identical(capacity, _unchanged)
        ? this.capacity
        : capacity as FormCapacityModel?,
    registrationMode: identical(registrationMode, _unchanged)
        ? this.registrationMode
        : registrationMode as String?,
    payments: identical(payments, _unchanged)
        ? this.payments
        : (payments as Map?)?.cast<String, dynamic>(),
    id: identical(id, _unchanged) ? this.id : id as int?,
    createdAt: identical(createdAt, _unchanged)
        ? this.createdAt
        : createdAt as DateTime?,
    title: identical(title, _unchanged) ? this.title : title as String?,
    data: identical(data, _unchanged)
        ? this.data
        : (data as Map?)?.cast<String, dynamic>(),
    key: identical(key, _unchanged) ? this.key : key as String?,
    occasionId: identical(occasionId, _unchanged)
        ? this.occasionId
        : occasionId as int?,
    blueprint: identical(blueprint, _unchanged)
        ? this.blueprint
        : blueprint as int?,
    type: identical(type, _unchanged) ? this.type : type as String?,
    bankAccountId: identical(bankAccountId, _unchanged)
        ? this.bankAccountId
        : bankAccountId as int?,
    deadlineDurationSeconds: identical(deadlineDurationSeconds, _unchanged)
        ? this.deadlineDurationSeconds
        : deadlineDurationSeconds as int?,
    isOpen: identical(isOpen, _unchanged) ? this.isOpen : isOpen as bool?,
    accountNumber: identical(accountNumber, _unchanged)
        ? this.accountNumber
        : accountNumber as String?,
    secret: identical(secret, _unchanged) ? this.secret : secret as String?,
    header: identical(header, _unchanged) ? this.header : header as String?,
    headerOff: identical(headerOff, _unchanged)
        ? this.headerOff
        : headerOff as String?,
    link: identical(link, _unchanged) ? this.link : link as String?,
    relatedFields: identical(relatedFields, _unchanged)
        ? this.relatedFields
        : relatedFields as List<FormFieldDefinition>,
    stats: identical(stats, _unchanged) ? this.stats : stats as FormStatsModel?,
    isReminderEnabled: identical(isReminderEnabled, _unchanged)
        ? this.isReminderEnabled
        : isReminderEnabled as bool?,
    canDelete: identical(canDelete, _unchanged)
        ? this.canDelete
        : canDelete as bool?,
  );
}

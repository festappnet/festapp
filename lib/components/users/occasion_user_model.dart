import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/users/user_columns.dart';
import 'package:intl/intl.dart';
import 'package:trina_grid/trina_grid.dart';

class OccasionUserModel extends ITrinaRowModel {
  static const String birthDateJsonFormat = "yyyy-MM-dd";
  static const String aggregateVersionColumn = TrinaRowVersion.column;

  DateTime? createdAt;
  DateTime? lastSignInAt;
  DateTime? firstInvitationSentAt;
  DateTime? lastInvitationSentAt;
  int invitationSendCount;
  DateTime? orderCreatedAt;
  int? occasion;
  String? user;
  int? role;
  int? unit;
  String? formId;
  String? groupTitle;
  String? companionOwnerId;
  String? companionOwnerName;
  String? companionOrigin;
  List<String> managedCompanionNames;
  FormModel? form;

  bool? isEditor = false;
  bool? isEditorView = false;
  bool? isEditorOrder = false;
  bool? isEditorOrderView = false;
  bool? isCleaningCrew = false;
  bool? isCleaningBlocked = false;
  bool? isReceptionist = false;
  bool? isManager = false;
  bool? isApprover = false;
  bool? isApproved = false;

  bool isPrivileged() =>
      (isEditor ?? false) ||
      (isManager ?? false) ||
      (isEditorView ?? false) ||
      (isEditorOrder ?? false) ||
      (isEditorOrderView ?? false) ||
      (isReceptionist ?? false);

  Map<String, dynamic>? data;
  Map<String, dynamic>? services;
  int aggregateVersion;
  OccasionUserModel(
      {this.createdAt,
      this.lastSignInAt,
      this.firstInvitationSentAt,
      this.lastInvitationSentAt,
      this.invitationSendCount = 0,
      this.orderCreatedAt,
      this.occasion,
      this.user,
      this.data,
      this.role,
      this.isEditor,
      this.isEditorView,
      this.isEditorOrder,
      this.isEditorOrderView,
      this.isCleaningCrew,
      this.isCleaningBlocked,
      this.isReceptionist,
      this.isManager,
      this.isApprover,
      this.isApproved,
      this.services,
      this.unit,
      this.formId,
      this.groupTitle,
      this.companionOwnerId,
      this.companionOwnerName,
      this.companionOrigin,
      this.managedCompanionNames = const [],
      this.form,
      this.aggregateVersion = 0});

  bool get isInvited => invitationSendCount > 0;

  factory OccasionUserModel.fromJson(Map<String, dynamic> json) {
    return OccasionUserModel(
        createdAt: json[Tb.occasion_users.created_at] != null
            ? DateTime.parse(json[Tb.occasion_users.created_at])
            : null,
        lastSignInAt: json[DbUsers.lastSignInAtKey] != null
            ? DateTime.parse(json[DbUsers.lastSignInAtKey])
            : null,
        orderCreatedAt: json[DbUsers.orderCreatedAtKey] != null
            ? DateTime.parse(json[DbUsers.orderCreatedAtKey])
            : null,
        occasion: json[Tb.occasion_users.occasion],
        user: json[Tb.occasion_users.user],
        unit: json[Tb.unit_users.unit],
        formId: json[DbUsers.formIdKey],
        groupTitle: json[DbUsers.groupTitleKey],
        companionOwnerId: json['companion_owner_id'],
        companionOwnerName: json['companion_owner_name'],
        companionOrigin: json['companion_origin'],
        isEditor: json[Tb.occasion_users.is_editor],
        isEditorView: json[Tb.occasion_users.is_editor_view],
        isEditorOrder: json[Tb.occasion_users.is_editor_order],
        isEditorOrderView: json[Tb.occasion_users.is_editor_order_view],
        isCleaningCrew: json[Tb.occasion_users.is_cleaning_crew],
        isCleaningBlocked: json[Tb.occasion_users.is_cleaning_blocked],
        isReceptionist: json[Tb.occasion_users.is_receptionist],
        isApprover: json[Tb.occasion_users.is_approver],
        isApproved: json[Tb.occasion_users.is_approved],
        isManager: json[Tb.occasion_users.is_manager],
        role: json[Tb.occasion_users.role],
        data: json[Tb.occasion_users.data],
        services: json[Tb.occasion_users.services],
        aggregateVersion: TrinaRowVersion.read(json));
  }

  dynamic toUpdateJson() {
    if (AppConfig.areAllVolunteersApprovers &&
        data![Tb.occasion_users.data_is_volunteer] == true) {
      isApprover = true;
    }

    return {
      Tb.occasion_users.occasion: RightsService.currentOccasionId(),
      Tb.occasion_users.user: user,
      Tb.occasion_users.is_editor: isEditor ?? false,
      Tb.occasion_users.is_editor_view: isEditorView ?? false,
      Tb.occasion_users.is_editor_order: isEditorOrder ?? false,
      Tb.occasion_users.is_editor_order_view: isEditorOrderView ?? false,
      Tb.occasion_users.is_cleaning_crew: isCleaningCrew ?? false,
      Tb.occasion_users.is_cleaning_blocked: isCleaningBlocked ?? false,
      Tb.occasion_users.is_receptionist: isReceptionist ?? false,
      Tb.occasion_users.is_approver: isApprover ?? false,
      Tb.occasion_users.is_approved: isApproved ?? false,
      Tb.occasion_users.is_manager: isManager ?? false,
      Tb.occasion_users.role: role,
      Tb.occasion_users.data: data,
      Tb.occasion_users.services: services,
    };
  }

  factory OccasionUserModel.newRow(int occasionId) {
    return OccasionUserModel(occasion: occasionId);
  }

  Map<String, dynamic> convertDateTime(Map<String, dynamic> map) {
    map.forEach((key, value) {
      if (value is DateTime) {
        map[key] = value.toIso8601String();
      } else if (value is Map<String, dynamic>) {
        map[key] = convertDateTime(value);
      }
    });
    return map;
  }

  Map<String, TrinaCell> serviceToOneColumnTrinaRow(
      Map<String, dynamic>? services, String serviceType) {
    Map<String, TrinaCell> serviceCells = {};
    for (var entry in services?[serviceType]?.entries ?? []) {
      serviceCells[serviceType + entry.key] = TrinaCell(value: entry.value);
    }
    return serviceCells;
  }

  Map<String, TrinaCell> servicesToOneColumnTrinaRow(
      Map<String, dynamic>? services, String serviceType) {
    TrinaCell cell = TrinaCell(value: "");
    var emptyResult = {serviceType: cell};
    if (services?[serviceType] == null) {
      return emptyResult;
    }
    var value = services?[serviceType]?.entries;
    if (value.isEmpty) {
      return emptyResult;
    }
    var first = value.first.key;
    cell = TrinaCell(value: first);
    return {serviceType: cell};
  }

  Map<String, TrinaCell> servicesToTrinaRow(
      Map<String, dynamic>? services, String serviceType) {
    Map<String, TrinaCell> serviceCells = {};
    for (var entry in services?[serviceType]?.entries ?? []) {
      serviceCells[serviceType + entry.key] = TrinaCell(value: entry.value);
    }
    return serviceCells;
  }

  @override
  Future<void> deleteMethod(BuildContext context) async {
    await DbUsers.deleteOccasionUser(this);
  }

  @override
  String toBasicString() => data?[Tb.occasion_users.data_email] ?? "";

  @override
  TrinaRow toTrinaRow(BuildContext context) {
    Map<String, TrinaCell> json = {};
    Map<String, TrinaCell> foodServices =
        servicesToTrinaRow(services, DbOccasions.serviceTypeFood);
    json.addAll(foodServices);
    json.addAll(servicesToOneColumnTrinaRow(
        services, DbOccasions.serviceTypeAccommodation));
    json.addAll({
      aggregateVersionColumn: TrinaRowVersion.cell(aggregateVersion),
      UserColumns.ID: TrinaCell(value: user),
      UserColumns.EDITOR: TrinaCell(value: isEditor.toString()),
      UserColumns.EDITOR_VIEW: TrinaCell(value: isEditorView.toString()),
      UserColumns.EDITOR_ORDER: TrinaCell(value: isEditorOrder.toString()),
      UserColumns.EDITOR_ORDER_VIEW:
          TrinaCell(value: isEditorOrderView.toString()),
      UserColumns.CLEANING_CREW: TrinaCell(value: isCleaningCrew.toString()),
      UserColumns.CLEANING_BLOCKED:
          TrinaCell(value: isCleaningBlocked.toString()),
      UserColumns.RECEPTIONIST: TrinaCell(value: isReceptionist.toString()),
      UserColumns.MANAGER: TrinaCell(value: isManager.toString()),
      UserColumns.APPROVED: TrinaCell(value: isApproved.toString()),
      UserColumns.APPROVER: TrinaCell(value: isApprover.toString()),
      UserColumns.ROLE: TrinaCell(value: role?.toString() ?? ""),
      UserColumns.EMAIL_HISTORY: TrinaCell(value: ''),
      UserColumns.EMAIL:
          TrinaCell(value: data?[Tb.occasion_users.data_email] ?? ""),
      UserColumns.NAME:
          TrinaCell(value: data?[Tb.occasion_users.data_name] ?? ""),
      UserColumns.SURNAME:
          TrinaCell(value: data?[Tb.occasion_users.data_surname] ?? ""),
      UserColumns.GROUP: TrinaCell(value: groupTitle ?? ""),
      UserColumns.COMPANION_OWNER: TrinaCell(value: companionOwnerName ?? ""),
      UserColumns.COMPANION_OWNER_ID: TrinaCell(value: companionOwnerId ?? ""),
      UserColumns.COMPANION_ORIGIN: TrinaCell(value: companionOrigin ?? ""),
      UserColumns.MANAGED_COMPANION_NAMES:
          TrinaCell(value: managedCompanionNames),
      UserColumns.SEX: TrinaCell(value: data?[Tb.occasion_users.data_sex]),
      UserColumns.PHONE:
          TrinaCell(value: data?[Tb.occasion_users.data_phone] ?? ""),
      UserColumns.BIRTHDAY: TrinaCell(
          value: DateTime.tryParse(
                  data?[Tb.occasion_users.data_birthDate] ?? "") ??
              DateTime.fromMicrosecondsSinceEpoch(0)),
      UserColumns.INVITED: TrinaCell(value: isInvited.toString()),
      UserColumns.APP_LINKS_SENT: TrinaCell(
          value: data?[Tb.occasion_users.data_appLinksSent].toString()),
      UserColumns.IS_VOLUNTEER: TrinaCell(
          value: data?[Tb.occasion_users.data_is_volunteer].toString()),
      UserColumns.NOTE:
          TrinaCell(value: data?[Tb.occasion_users.data_note] ?? ""),
      UserColumns.DIET:
          TrinaCell(value: data?[Tb.occasion_users.data_diet] ?? ""),
      UserColumns.TEXT1:
          TrinaCell(value: data?[Tb.occasion_users.data_text1] ?? ""),
      UserColumns.TEXT2:
          TrinaCell(value: data?[Tb.occasion_users.data_text2] ?? ""),
      UserColumns.TEXT3:
          TrinaCell(value: data?[Tb.occasion_users.data_text3] ?? ""),
      UserColumns.FORM: TrinaCell(value: form?.toString() ?? ""),
      UserColumns.ORDERED_AT: TrinaCell(value: orderCreatedAt),
      UserColumns.CREATED_AT: TrinaCell(value: createdAt),
      UserColumns.LAST_SIGN_IN_AT: TrinaCell(value: lastSignInAt),
    });
    return TrinaRow(cells: json);
  }

  static void mapOneToServices(Map<String, dynamic> services,
      String serviceType, String? key, String value) {
    if (key == null) {
      return;
    }
    if (services[serviceType] == null) {
      services[serviceType] = {};
    }
    services[serviceType][key] = value;
  }

  static void mapJsonToServices(Map<String, dynamic> json,
      Map<String, dynamic> services, String serviceType) {
    for (var entry in json.entries) {
      if (entry.key.startsWith(serviceType)) {
        var code = entry.key.substring(serviceType.length);
        services[serviceType] ??= {};
        services[serviceType][code] = entry.value;
      }
    }
  }

  static OccasionUserModel fromPlutoJson(Map<String, dynamic> json) {
    DateTime? bd;
    var jsonTime = json[UserColumns.BIRTHDAY];
    if (jsonTime != null && jsonTime is String) {
      var birthDateString = json[UserColumns.BIRTHDAY];
      var dateFormat = DateFormat(birthDateJsonFormat);
      bd = dateFormat.parse(birthDateString);
    } else {
      bd = jsonTime;
    }
    Map<String, dynamic> services = {};
    mapJsonToServices(json, services, DbOccasions.serviceTypeFood);
    final accommodationCode = json[UserColumns.ACCOMMODATION]?.toString() ?? '';
    // Presence of the accommodation object is intentional: an empty object
    // clears the current assignment, while missing service types are preserved
    // by save_occasion_user_for_edit.
    services[DbOccasions.serviceTypeAccommodation] = <String, dynamic>{};
    if (accommodationCode.isNotEmpty) {
      mapOneToServices(
        services,
        DbOccasions.serviceTypeAccommodation,
        accommodationCode,
        DbOccasions.servicePaid,
      );
    }
    return OccasionUserModel(
      occasion: RightsService.currentOccasionId(),
      aggregateVersion: TrinaRowVersion.read(json),
      user: json[UserColumns.ID]?.isEmpty == true ? null : json[UserColumns.ID],
      groupTitle: json[UserColumns.GROUP],
      companionOwnerId: json[UserColumns.COMPANION_OWNER_ID]?.isEmpty == true
          ? null
          : json[UserColumns.COMPANION_OWNER_ID],
      companionOwnerName: json[UserColumns.COMPANION_OWNER]?.isEmpty == true
          ? null
          : json[UserColumns.COMPANION_OWNER],
      companionOrigin: json[UserColumns.COMPANION_ORIGIN]?.isEmpty == true
          ? null
          : json[UserColumns.COMPANION_ORIGIN],
      isApprover: json[UserColumns.APPROVER] == "true" ? true : false,
      isApproved: json[UserColumns.APPROVED] == "true" ? true : false,
      isManager: json[UserColumns.MANAGER] == "true" ? true : false,
      isEditor: json[UserColumns.EDITOR] == "true" ? true : false,
      isEditorView: json[UserColumns.EDITOR_VIEW] == "true" ? true : false,
      isEditorOrder: json[UserColumns.EDITOR_ORDER] == "true" ? true : false,
      isEditorOrderView:
          json[UserColumns.EDITOR_ORDER_VIEW] == "true" ? true : false,
      isCleaningCrew: json[UserColumns.CLEANING_CREW] == "true" ? true : false,
      isCleaningBlocked:
          json[UserColumns.CLEANING_BLOCKED] == "true" ? true : false,
      isReceptionist: json[UserColumns.RECEPTIONIST] == "true" ? true : false,
      role: int.tryParse(json[UserColumns.ROLE] ?? ""),
      services: services,
      data: {
        Tb.occasion_users.data_name: json[UserColumns.NAME]?.trim(),
        Tb.occasion_users.data_surname: json[UserColumns.SURNAME]?.trim(),
        Tb.occasion_users.data_sex: json[UserColumns.SEX]?.trim(),
        Tb.occasion_users.data_email: json[UserColumns.EMAIL]?.trim(),
        Tb.occasion_users.data_phone: json[UserColumns.PHONE]?.trim(),
        Tb.occasion_users.data_birthDate: bd?.toIso8601String(),
        Tb.occasion_users.data_appLinksSent:
            json[UserColumns.APP_LINKS_SENT] == "true" ? true : false,
        Tb.occasion_users.data_is_volunteer:
            json[UserColumns.IS_VOLUNTEER] == "true" ? true : false,
        Tb.occasion_users.data_note: json[UserColumns.NOTE]?.trim(),
        Tb.occasion_users.data_diet: json[UserColumns.DIET]?.trim(),
        Tb.occasion_users.data_text1: json[UserColumns.TEXT1]?.trim(),
        Tb.occasion_users.data_text2: json[UserColumns.TEXT2]?.trim(),
        Tb.occasion_users.data_text3: json[UserColumns.TEXT3]?.trim(),
      },
    );
  }

  @override
  Future<void> updateMethod(BuildContext context) async {
    await DbUsers.updateOccasionUser(this);
  }

  bool compareStrings(String? str1, String? str2) {
    bool isEmptyOrNull(String? str) => str == null || str.trim().isEmpty;
    if (isEmptyOrNull(str1) && isEmptyOrNull(str2)) {
      return true;
    }
    return str1 == str2;
  }

  bool compareField(Map<String, dynamic> u, dynamic dataField, dynamic uField) {
    return compareStrings(u[uField], data?[dataField]);
  }

  bool importedEquals(Map<String, dynamic> iu) {
    final importedDataFields = [
      Tb.occasion_users.data_email,
      Tb.occasion_users.data_name,
      Tb.occasion_users.data_surname,
      Tb.occasion_users.data_sex,
      Tb.occasion_users.data_phone,
      Tb.occasion_users.data_text1,
      Tb.occasion_users.data_text2,
      Tb.occasion_users.data_text3,
      Tb.occasion_users.data_text4,
      Tb.occasion_users.data_diet,
      Tb.occasion_users.data_note,
      Tb.occasion_users.data_birthDate,
    ];

    for (final field in importedDataFields) {
      if (iu.containsKey(field) && !compareField(iu, field, field)) {
        return false;
      }
    }

    if (iu.containsKey(Tb.occasion_users.role) &&
        iu[Tb.occasion_users.role] != role) {
      return false;
    }

    final importedServices = iu[Tb.occasion_users.services];
    if (iu.containsKey(Tb.occasion_users.services) &&
        importedServices is Map<String, dynamic>) {
      return compareServicesJson(
          importedServices, services, importedServices.keys.toList());
    }

    return true;
  }

  static bool compareJson(
      Map<String, dynamic>? json1, Map<String, dynamic>? json2) {
    if (json1 == null && json2 == null) return true;
    if (json1 == null || json2 == null) return false;

    // Use DeepCollectionEquality to perform a deep comparison for non-null maps
    final deepEquality = const DeepCollectionEquality().equals;
    return deepEquality(json1, json2);
  }

  static bool compareServicesJson(Map<String, dynamic>? json1,
      Map<String, dynamic>? json2, List<String> serviceTypes) {
    if (json1 == null && json2 == null) return true;
    if (json1 == null || json2 == null) return false;
    for (String serviceType in serviceTypes) {
      // Check if both JSON objects contain the current service type key
      if (!(json1.containsKey(serviceType) && json2.containsKey(serviceType))) {
        return false;
      }
      Map<String, dynamic> service1 = json1[serviceType];
      Map<String, dynamic> service2 = json2[serviceType];

      // Compare the contents of each service type map
      for (var key in service1.keys) {
        var value1 = service1[key];
        var value2 = service2[key];

        // Check if value is "serviceNone" in one JSON and something else in the other
        if ((value1 == DbOccasions.serviceNone &&
                value2 != DbOccasions.serviceNone) ||
            (value2 == DbOccasions.serviceNone &&
                value1 != DbOccasions.serviceNone)) {
          return false;
        }
      }

      // Check for any extra keys in json2 that are not in json1
      for (var key in service2.keys.where((k) => k.isNotEmpty)) {
        if (!service1.containsKey(key)) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  get id => user;
}

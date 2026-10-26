import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/organization/organization_model.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';

class OccasionLinkModel {
  int? code;
  final Map<String, dynamic>? unitDashboard;
  OccasionModel? occasion;
  UnitModel? unit;
  UserInfoModel? userInfo;
  OccasionUserModel? occasionUser;
  OccasionUserModel? unitUser;
  List<int>? bankAccountsAdmin;
  bool? isAdmin = false;
  OrganizationModel? organization;
  bool clientSyncV1;
  final bool demoReadOnly;
  final Map<String, bool> capabilities;
  final Map<int, Map<String, bool>> bankCapabilities;

  bool isAvailable() => code == 200;
  bool isAccessDenied() => code == 403;
  bool isNotFound() => code == 404;

  factory OccasionLinkModel.fromJson(Map<String, dynamic> json) {
    var unitUser = json["unit_user"] != null
        ? OccasionUserModel.fromJson(json["unit_user"])
        : null;
    var occasionUser = json["occasion_user"] != null
        ? OccasionUserModel.fromJson(json["occasion_user"])
        : null;
    var userInfo = json["user_info"] != null
        ? UserInfoModel.fromJson(json["user_info"])
        : null;
    var organization = json["organization"] != null
        ? OrganizationModel.fromJson(json["organization"])
        : null;

    if (json["groups"] != null && json["groups"] is Map && userInfo != null) {
      final groupsData = json["groups"] as Map<String, dynamic>;
      userInfo.userGroups = groupsData.values
          .map((groupJson) =>
              UserGroupInfoModel.fromJson(groupJson as Map<String, dynamic>))
          .toSet();
    }
    return OccasionLinkModel(
      code: json["code"],
      unitDashboard: json["unit_dashboard"] == null
          ? null
          : Map<String, dynamic>.unmodifiable(json["unit_dashboard"]),
      capabilities: Map<String, bool>.unmodifiable({
        for (final entry in (json['capabilities'] as Map? ?? {}).entries)
          if (entry.key is String) entry.key as String: entry.value == true,
      }),
      userInfo: userInfo,
      unitUser: unitUser,
      occasionUser: occasionUser,
      bankAccountsAdmin: List<int>.from(json["bank_accounts_admin"] ?? []),
      bankCapabilities: Map.unmodifiable({
        for (final entry in (json['bank_capabilities'] as Map? ?? {}).entries)
          if (int.tryParse(entry.key.toString()) case final id?)
            id: Map<String, bool>.unmodifiable({
              for (final capability in (entry.value as Map? ?? {}).entries)
                if (capability.key is String)
                  capability.key as String: capability.value == true,
            }),
      }),
      occasion: json["occasion"] != null && json["occasion"]["id"] != null
          ? OccasionModel.fromJson(json["occasion"])
          : null,
      unit: json["unit"] != null ? UnitModel.fromJson(json["unit"]) : null,
      isAdmin: json["is_admin"],
      organization: organization,
      demoReadOnly: json['demo_read_only'] == true,
      clientSyncV1: json['client_sync_v1'] as bool? ?? false,
    );
  }

  OccasionLinkModel({
    this.code,
    this.unitDashboard,
    this.userInfo,
    this.occasionUser,
    this.unitUser,
    this.bankAccountsAdmin,
    this.occasion,
    this.unit,
    this.isAdmin,
    this.organization,
    this.clientSyncV1 = false,
    this.demoReadOnly = false,
    this.capabilities = const {},
    this.bankCapabilities = const {},
  });
  OccasionLinkModel copyWith({
    OrganizationModel? organization,
    Map<String, bool>? capabilities,
    Map<int, Map<String, bool>>? bankCapabilities,
  }) =>
      OccasionLinkModel(
        code: code,
        unitDashboard: unitDashboard,
        userInfo: userInfo,
        occasionUser: occasionUser,
        unitUser: unitUser,
        bankAccountsAdmin: bankAccountsAdmin,
        occasion: occasion,
        unit: unit,
        isAdmin: isAdmin,
        organization: organization ?? this.organization,
        clientSyncV1: clientSyncV1,
        demoReadOnly: demoReadOnly,
        capabilities: capabilities ?? this.capabilities,
        bankCapabilities: bankCapabilities ?? this.bankCapabilities,
      );
}

import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/organization/organization_model.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';

class OccasionLinkModel {
  int? code;
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
      userInfo: userInfo,
      unitUser: unitUser,
      occasionUser: occasionUser,
      bankAccountsAdmin: List<int>.from(json["bank_accounts_admin"] ?? []),
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
  });
}

import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/users/user_info_model.dart';

/// Represents a user's participation in a group, including their admin status.
class GroupParticipantModel {
  UserInfoModel? userInfo;
  bool? isAdmin;

  GroupParticipantModel({
    this.userInfo,
    this.isAdmin,
  });

  factory GroupParticipantModel.fromJson(Map<String, dynamic> json) {
    return GroupParticipantModel(
      userInfo: json[Tb.user_info.table] != null
          ? UserInfoModel.fromJson(json[Tb.user_info.table])
          : null,
      isAdmin: json[Tb.user_groups.is_admin],
    );
  }

  Map<String, dynamic> toJson() => {
        Tb.user_info.table: userInfo?.toJson(),
        Tb.user_groups.is_admin: isAdmin ?? false,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupParticipantModel &&
          runtimeType == other.runtimeType &&
          userInfo == other.userInfo;

  @override
  int get hashCode => userInfo.hashCode;

  @override
  String toString() {
    return userInfo?.toFullNameString() ?? 'Unknown Participant';
  }
}

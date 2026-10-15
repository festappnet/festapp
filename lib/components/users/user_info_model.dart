import 'package:flutter/widgets.dart';
import 'package:fstapp/components/_shared/person_fields_strings.dart';
import 'package:fstapp/components/single_data_grid/i_has_id.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/components/users/companion/companion_model.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:collection/collection.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:festapp_core/map.dart';
import '../occasion/occasion_model.dart';
import '../groups/user_group_info_model.dart';

class UserInfoModel extends IHasId {
  @override
  String? id;
  String? email;
  String? name;
  String? surname;
  String? sex;
  String? role;
  String? phone;
  DateTime? birthDate;
  bool? isAdmin = false;
  bool? isEditor = false;
  PlaceModel? accommodationPlace;
  Set<UserGroupInfoModel>? userGroups;
  List<UnitModel>? units;
  List<OccasionModel>? occasions;

  UserGroupInfoModel? eventUserGroup;
  OccasionUserModel? occasionUser;
  String? roleString;
  List<CompanionModel>? companions = [];
  UserInfoModel? companionParent;
  List<String>? eventIds;

  int? ticketId;
  TicketModel? ticket;
  // NEW: Property to hold the answer from the feature field.
  String? groupFeatureAnswer;

  static const String idColumn = "id";
  static const String emailReadonlyColumn = "email_readonly";
  static const String emailDeliveryColumn = "email_delivery";
  static const String nameColumn = "name";
  static const String surnameColumn = "surname";
  static const String sexColumn = "sex";
  static const String phoneColumn = "phone";
  static const String roleColumn = "role";
  static const String birthDateColumn = "birth_date";
  static const String placeColumn = "placeColumn";
  static const String userGroupColumn = "userGroup";
  static const String occasionUserColumn = "occasionUser";
  static const String roleStringColumn = "roleString";
  static const String userCompanionsColumn = "userCompanions";
  static const String companionParentColumn = "companion_parent";
  static const String unitsField = "units";
  static const String occasionsField = "occasions";
  static const String ticketIdColumn = "ticket_id";
  static const String scheduleColumn = "schedule";
  static const String userInfoOffline = "user_info";
  static const String birthDateJsonFormat = "yyyy-MM-dd";
  static const sexes = ["male", "female", ""];

  UserInfoModel({
    this.id,
    this.email,
    this.name,
    this.surname,
    this.sex,
    this.birthDate,
    this.role,
    this.isAdmin,
    this.isEditor,
    this.phone,
    this.accommodationPlace,
    this.eventUserGroup,
    this.occasionUser,
    this.roleString,
    this.companions,
    this.companionParent,
    this.units,
    this.occasions,
    this.eventIds,
    this.userGroups,
    this.ticketId,
    this.ticket,
    // NEW: Added to constructor.
    this.groupFeatureAnswer,
  });

  /// Combines the current organization-wide profile with one occasion's
  /// participation. Profile identity stays owned by this model; roles,
  /// services and other occasion-specific state stay on [occasionUser].
  UserInfoModel withOccasionParticipation(OccasionUserModel participation) {
    final combined = UserInfoModel(
      id: id,
      email: email,
      name: name,
      surname: surname,
      sex: sex,
      birthDate: birthDate,
      role: role,
      isAdmin: isAdmin,
      isEditor: isEditor,
      phone: phone,
      accommodationPlace: accommodationPlace,
      eventUserGroup: eventUserGroup,
      occasionUser: participation,
      roleString: roleString,
      companions: companions,
      companionParent: companionParent,
      units: units,
      occasions: occasions,
      eventIds: eventIds,
      userGroups: userGroups,
      ticketId: ticketId,
      ticket: ticket,
      groupFeatureAnswer: groupFeatureAnswer,
    );
    combined.isSignedIn = isSignedIn;
    return combined;
  }

  static UserInfoModel fromJson(Map<String, dynamic> json) {
    return UserInfoModel(
      id: json[idColumn],
      email: json[emailReadonlyColumn] ?? json["email"],
      name: json[nameColumn],
      surname: json[surnameColumn],
      accommodationPlace: json[placeColumn] != null
          ? PlaceModel.fromJson(json[placeColumn])
          : null,
      eventUserGroup: json[userGroupColumn] != null
          ? UserGroupInfoModel.fromJson(json[userGroupColumn])
          : null,
      occasionUser: json[occasionUserColumn] != null
          ? OccasionUserModel.fromJson(json[occasionUserColumn])
          : null,
      roleString: json[roleStringColumn],
      companions: json[userCompanionsColumn] != null
          ? List<CompanionModel>.from(json[userCompanionsColumn]!
              .map((c) => CompanionModel.fromJson(c)))
          : null,
      companionParent: json[companionParentColumn] != null
          ? UserInfoModel.fromJson(json[companionParentColumn])
          : null,
      units: json[unitsField] != null
          ? List<UnitModel>.from(
              json[unitsField].map((u) => UnitModel.fromJson(u)))
          : null,
      occasions: json[occasionsField] != null
          ? List<OccasionModel>.from(
              json[occasionsField].map((o) => OccasionModel.fromJson(o)))
          : null,
      eventIds: json[scheduleColumn] != null
          ? List<String>.from(json[scheduleColumn]!.map((s) => s))
          : null,
      sex: json[sexColumn],
      phone: json[phoneColumn],
      birthDate: json[birthDateColumn] != null
          ? DateTime.tryParse(json[birthDateColumn] as String)
          : null,
      ticketId: json[ticketIdColumn],
    );
  }

  Map<String, dynamic> toJson() => {
        idColumn: id,
        emailReadonlyColumn: email,
        nameColumn: name,
        surnameColumn: surname,
        phoneColumn: phone,
        roleColumn: role,
        placeColumn: accommodationPlace?.toJson(),
        userGroupColumn: eventUserGroup?.toJson(),
        occasionUserColumn: occasionUser?.toUpdateJson(),
        roleStringColumn: roleString,
        sexColumn: sex,
        birthDateColumn: birthDate != null
            ? DateFormat(birthDateJsonFormat).format(birthDate!)
            : null,
        userCompanionsColumn: companions != null
            ? List<dynamic>.from(companions!.map((c) => c.toJson()))
            : null,
      };

  @override
  String toString() => toFullNameString();

  String toFullNameString() {
    if (companionParent != null) {
      return (name ?? "") +
          (" (${UserStrings.companionOf}: ${companionParent!.toFullNameString()})");
    }
    return "${name ?? ""} ${surname ?? ""}".trim();
  }

  /// **UPDATED**: Returns a secondary string of information including the feature field answer.
  String getSecondaryInfoString(BuildContext context) {
    final infoParts = <String>[];

    // 1. Add Birth Year
    if (birthDate != null) {
      infoParts.add(birthDate!.year.toString());
    }

    // NEW: 2. Add answer from the special feature field
    if (groupFeatureAnswer != null && groupFeatureAnswer!.isNotEmpty) {
      infoParts.add(groupFeatureAnswer!);
    }

    // 3. Add Form Title
    final formTitle = ticket?.relatedOrder?.form?.toString();
    if (formTitle != null && formTitle.isNotEmpty) {
      infoParts.add(formTitle);
    }

    // 4. Add Order Creation Date
    final orderDate = ticket?.relatedOrder?.createdAt;
    if (orderDate != null) {
      infoParts
          .add(DateFormat.yMd(context.locale.toString()).format(orderDate));
    }

    return infoParts.join(' • ');
  }

  String shortNameToString() {
    return "$name ${(surname != null && surname!.isNotEmpty) ? "${surname![0]}." : "-"}";
  }

  bool hasGroup() => eventUserGroup != null;

  UserGroupInfoModel? get getGameUserGroup =>
      userGroups?.firstWhereOrNull((g) => g.type == InformationModel.gameType);

  bool isSignedIn = false;

  List<UnitModel> getUnitsWithEditorAccess() {
    return units?.where((u) => u.unitUser?.isEditorView == true).toList() ?? [];
  }

  static String sexToLocale(String? sx) {
    if (sx == "female") {
      return PersonFieldsStrings.female;
    } else if (sx == "male") {
      return PersonFieldsStrings.male;
    }
    return PersonFieldsStrings.notSpecified;
  }

  static String? sexFromLocale(String? localeString) {
    if (localeString == null) {
      return null;
    }

    String trimmedVal = localeString.trim();

    if (trimmedVal == PersonFieldsStrings.female || trimmedVal == "Female") {
      return "female";
    } else if (trimmedVal == PersonFieldsStrings.male || trimmedVal == "Male") {
      return "male";
    }

    return null;
  }

  @override
  int get hashCode {
    return id.hashCode;
  }

  @override
  bool operator ==(Object other) {
    if (other is UserInfoModel) {
      if (id == null && other.id == null) {
        return false;
      }
      return id == other.id;
    }
    return false;
  }

  String getGenderPrefix() {
    return sex == "female" ? "F" : "M";
  }
}

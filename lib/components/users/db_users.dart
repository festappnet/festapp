import 'package:festapp_core/forms.dart';
import 'package:collection/collection.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/order_product_ticket_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/forms/models/form_bundle.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/unit_commands.dart';
import 'package:fstapp/components/users/unit_user_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/users/profile_commands.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/occasion_services/service_item_model.dart';
import 'package:fstapp/components/users/occasion_editor_payload.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OccasionEditorData {
  final List<OccasionUserModel> users;
  final List<FormBundle> forms;
  final Map<String, List<ServiceItemModel>> services;
  OccasionEditorData({
    required this.users,
    required this.forms,
    required this.services,
  });
}

class OccasionUsersBundle {
  final Map<String, UserInfoModel> users;
  final Map<int, TicketModel> tickets;
  final Map<int, OrderProductTicketModel> orderProductTickets;
  final Map<int, OrderModel> orders;
  final Map<int, FormBundle> forms;
  final Map<int, FormFieldDefinition> formFields;

  OccasionUsersBundle({
    required this.users,
    required this.tickets,
    required this.orderProductTickets,
    required this.orders,
    required this.forms,
    required this.formFields,
  });
}

class DbUsers {
  static final _supabase = Supabase.instance.client;
  static UnitCommands get _unitCommands => SupabaseUnitCommands(_supabase);
  static final ProfileCommands _profileCommands =
      SupabaseProfileCommands(_supabase);

  static const String formIdKey = 'form_id';
  static const String orderCreatedAtKey = 'order_created_at';
  static const String lastSignInAtKey = 'last_sign_in_at';
  static const String groupTitleKey = 'group_title';

  static Future<OccasionEditorData> getOccasionEditorDataBundle() async {
    final occasionId = RightsService.currentOccasionId()!;
    final results = await Future.wait<dynamic>([
      _supabase.rpc('get_occasion_users_editor_bundle_v1', params: {
        'p_occasion': occasionId,
      }),
      _supabase.rpc('get_occasion_sign_in_email_statuses',
          params: {'p_occasion': occasionId}),
    ]);
    return parseOccasionEditorData(results[0], invitationStatuses: results[1]);
  }

  static OccasionEditorData parseOccasionEditorData(dynamic result,
      {dynamic invitationStatuses}) {
    final payload = OccasionEditorPayload.fromRpc(result);
    if (payload.isSuccess) {
      final users = List<OccasionUserModel>.from(
          payload.users.map((x) => OccasionUserModel.fromJson(x)));
      final forms = List<FormBundle>.from(
          payload.forms.map((x) => FormBundle.fromJson(x)));
      final services = <String, List<ServiceItemModel>>{
        for (final type in [
          DbOccasions.serviceTypeAccommodation,
          DbOccasions.serviceTypeFood,
        ])
          type: List<ServiceItemModel>.from(
            (payload.services[type] ?? const [])
                .map((item) => ServiceItemModel.fromJson(item)),
          ),
      };

      final formMap = {for (var form in forms) form.definition.key: form};
      final usersById = {for (final user in users) user.user: user};

      for (final status in invitationStatuses is List
          ? invitationStatuses
          : const <dynamic>[]) {
        if (status is! Map) continue;
        final user = usersById[status['user']];
        if (user == null) continue;
        user.invitationSendCount = status['send_count'] as int? ?? 0;
        final firstSentAt = status['first_sent_at'] as String?;
        final lastSentAt = status['last_sent_at'] as String?;
        user.firstInvitationSentAt =
            firstSentAt == null ? null : DateTime.parse(firstSentAt);
        user.lastInvitationSentAt =
            lastSentAt == null ? null : DateTime.parse(lastSentAt);
      }

      for (final user in users) {
        user.services ??= {};
        final food = user.services!.putIfAbsent(
          DbOccasions.serviceTypeFood,
          () => <String, dynamic>{},
        ) as Map<String, dynamic>;
        for (final item in services[DbOccasions.serviceTypeFood] ?? const []) {
          food.putIfAbsent(item.code, () => DbOccasions.serviceNone);
        }
        if (user.formId != null && formMap.containsKey(user.formId)) {
          user.form = formMap[user.formId];
        }
      }

      users.sort((a, b) {
        bool isAPrivileged = a.isPrivileged();
        bool isBPrivileged = b.isPrivileged();

        if (isAPrivileged && !isBPrivileged) return -1;
        if (!isAPrivileged && isBPrivileged) return 1;

        final dateA = a.orderCreatedAt ?? a.createdAt;
        final dateB = b.orderCreatedAt ?? b.createdAt;

        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;

        return dateA.compareTo(dateB);
      });

      return OccasionEditorData(
        users: users,
        forms: forms,
        services: services,
      );
    }
    return OccasionEditorData(users: [], forms: [], services: {});
  }

  static Future<OccasionUsersBundle> getOccasionUsersWithOrdersBundle() async {
    final response = await _supabase.rpc(
      'get_users_from_occasion_with_orders',
      params: {'oc': RightsService.currentOccasionId()!},
    );

    final json = response;

    // 1. Parse all data into dictionaries, keyed by ID
    final users = (json['users'] as Map<String, dynamic>)
        .map((key, value) => MapEntry(key, UserInfoModel.fromJson(value)));
    final tickets = (json['tickets'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(int.parse(key), TicketModel.fromJson(value)));
    final orderProductTickets = (json['order_product_ticket']
            as Map<String, dynamic>)
        .map((key, value) =>
            MapEntry(int.parse(key), OrderProductTicketModel.fromJson(value)));
    final orders = (json['orders'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(int.parse(key), OrderModel.fromJson(value)));
    final forms = (json['forms'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(int.parse(key), FormBundle.fromJson(value)));
    final formFields = (json['form_fields'] as Map<String, dynamic>).map(
        (key, value) =>
            MapEntry(int.parse(key), FormFieldDefinition.fromJson(value)));

    // 2. Link the parsed models together
    final fieldsByForm = groupBy(formFields.values, (field) => field.form);
    for (final entry in forms.entries.toList()) {
      final added = fieldsByForm[entry.key];
      if (added != null)
        forms[entry.key] = entry.value.withDefinition(entry.value.definition
            .copyWith(relatedFields: [
          ...entry.value.definition.relatedFields,
          ...added
        ]));
    }
    final formMapByKey = {for (var f in forms.values) f.definition.key: f};
    final optsByTicketId =
        groupBy(orderProductTickets.values, (opt) => opt.ticketId);

    for (final order in orders.values) {
      if (order.formKey != null) {
        order.form = formMapByKey[order.formKey];
      }
    }

    for (final ticket in tickets.values) {
      final ticketOpts = optsByTicketId[ticket.id];
      if (ticketOpts != null && ticketOpts.isNotEmpty) {
        final orderId = ticketOpts.first.orderId;
        if (orderId != null) {
          ticket.relatedOrder = orders[orderId];
        }
      }
    }

    for (final user in users.values) {
      if (user.ticketId != null) {
        user.ticket = tickets[user.ticketId];
      }
    }

    // 3. **UPDATED**: Enhance user data with info from their order form in a single pass.
    for (final user in users.values) {
      final order = user.ticket?.relatedOrder;
      final orderDataFields = order?.data?['fields'];

      if (orderDataFields is! List) continue;

      for (final fieldResponse in orderDataFields) {
        if (fieldResponse is! Map || fieldResponse.isEmpty) continue;

        final fieldIdStr = fieldResponse.keys.first as String;
        final fieldValue = fieldResponse.values.first;
        if (fieldValue == null) continue;

        final fieldId = int.tryParse(fieldIdStr);
        if (fieldId == null) continue;

        final formFieldModel = formFields[fieldId];
        if (formFieldModel == null) continue;

        // Check for birth_date if not already present on the user model
        if (user.birthDate == null) {
          if (formFieldModel.type == FormMetadata.fieldTypeBirthDate) {
            final date = DateTime.tryParse(fieldValue as String);
            if (date != null) user.birthDate = date;
          } else if (formFieldModel.type == FormMetadata.fieldTypeBirthYear) {
            final year = int.tryParse(fieldValue.toString());
            if (year != null) user.birthDate = DateTime(year);
          }
        }

        // Check for the group feature field if not already present
        if (user.groupFeatureAnswer == null &&
            formFieldModel.data?[FormMetadata.isGroupFeatureField] == true) {
          user.groupFeatureAnswer = fieldValue.toString();
        }

        // Exit early if we've found both pieces of information we're looking for
        if (user.birthDate != null && user.groupFeatureAnswer != null) {
          break;
        }
      }
    }

    return OccasionUsersBundle(
      users: users,
      tickets: tickets,
      orderProductTickets: orderProductTickets,
      orders: orders,
      forms: forms,
      formFields: formFields,
    );
  }

  static Future<List<UserInfoModel>> getUsersInfo(List<String> userIds) async {
    var result = await _supabase.rpc("get_user_info_for_users",
        params: {"oc": RightsService.currentOccasionId(), "user_ids": userIds});
    if (result["code"] == 200) {
      return List<UserInfoModel>.from(
          result["data"].map((x) => UserInfoModel.fromJson(x)));
    }
    return [];
  }

  static Future<UserInfoModel?> getUserInfo(String userId) async {
    var list = await getUsersInfo([userId]);
    if (list.length == 1) {
      return list[0];
    }
    return null;
  }

  static Future<List<UserInfoModel>> getAllUsersBasics() async {
    var result = await _supabase.rpc("get_all_user_basics_from_occasion",
        params: {"oc": RightsService.currentOccasionId()});
    if (result["code"] == 200) {
      var t = List<UserInfoModel>.from(
          result["data"].map((x) => UserInfoModel.fromJson(x)));
      return t;
    }
    return [];
  }

  static Future<List<UserInfoModel>> getAllUsersBasicsForScan(
      String scanCode) async {
    // This calls the RPC.
    // If the scanCode is invalid, the SQL function raises an EXCEPTION,
    // which causes this line to throw a PostgrestException immediately.
    final result = await _supabase.rpc(
      "get_all_user_basics_for_scan",
      params: {"scan_code": scanCode},
    );

    // If successful, 'result' is the JSON List directly
    if (result is List) {
      return List<UserInfoModel>.from(
          result.map((x) => UserInfoModel.fromJson(x)));
    }

    // Fallback for unexpected return types
    return [];
  }

  static Future<List<UserInfoModel>> getAllUsersBasicsForUnit(
      int unitId) async {
    // This calls the RPC "get_all_user_basics_from_occasion_unit".
    // If the unit is not found or user is not auth, it throws a Postgres error.
    final result = await _supabase.rpc("get_all_user_basics_from_occasion_unit",
        params: {"p_unit_id": unitId});

    if (result is List) {
      return List<UserInfoModel>.from(
          result.map((x) => UserInfoModel.fromJson(x)));
    }
    return [];
  }

  static Future<List<UnitUserModel>> getAllUsersFromUnit(int unitId) async {
    var result = await _supabase
        .rpc("get_all_users_from_unit", params: {"unit_id": unitId});
    if (result["code"] == 200) {
      final users = List<UnitUserModel>.from(
          result["data"].map((x) => UnitUserModel.fromJson(x)));
      int permissionPriority(UnitUserModel user) {
        if (user.isManager == true) return 3;
        if (user.isEditor == true) return 2;
        if (user.isEditorView == true) return 1;
        return 0;
      }

      // Keep the original order within each permission level.
      mergeSort(users,
          compare: (a, b) =>
              permissionPriority(b).compareTo(permissionPriority(a)));
      return users;
    }
    return [];
  }

  static Future<UnitModel?> getCurrentUnit(int unit) async {
    var result =
        await _supabase.rpc("get_unit_for_edit", params: {"unit_id": unit});

    if (result != null && result["code"] == 200) {
      return UnitModel.fromJson(result["data"]);
    }
    return null;
  }

  static Future<UnitModel?> getCurrentOrganization() async {
    var result = await _supabase.rpc("get_current_organization_data");

    if (result != null && result["code"] == 200) {
      return UnitModel.fromJson(result["data"]);
    } else if (result != null && result["code"] == 403) {}

    // Return null if no organization data is found or unauthorized
    return null;
  }

  static Future<void> updateUnitUser(UnitUserModel uum) async {
    await _unitCommands.saveUser(uum);
    if (uum.user != null && uum.user == RightsService.currentUser()?.id) {
      await RightsService.refreshAfterAuthorizationChange();
    }
  }

  static Future<void> updateOccasionUser(OccasionUserModel oum) async {
    await AuthService.ensureCanUpdateUsers(oum);

    final result = oum.user == null
        ? await _profileCommands.create(oum)
        : await _profileCommands.save(oum);
    if (result.status == ProfileCommandStatus.conflict)
      throw StateError('Profile was changed by another editor');
    if (result.status == ProfileCommandStatus.rejected ||
        (oum.user == null && result.userId == null))
      throw StateError('Profile save was rejected');
    oum
      ..user = result.userId ?? oum.user
      ..aggregateVersion = result.version;
    if (oum.user != null && oum.user == RightsService.currentUser()?.id) {
      await RightsService.refreshAfterAuthorizationChange();
    }
  }

  static Future<void> addUserToOccasion(String id, int occasion) =>
      _profileCommands.ensureMembership(occasion, id);

  static Future<void> addUserToUnit(String id, int unit) async {
    await _supabase.rpc("add_user_to_unit", params: {
      "usr": id,
      "unit_id": unit,
    });
  }

  static Future<void> importOccasionUsersFromCsv(
      List<Map<String, dynamic>> rows, List<String> deleteUserIds) async {
    final result = await _profileCommands.importProfiles(
      RightsService.currentOccasionId()!,
      rows,
      deleteUserIds,
    );
    if (result.status == ProfileCommandStatus.rejected) {
      throw StateError('CSV import was rejected');
    }
    if (result.status == ProfileCommandStatus.conflict) {
      throw StateError('CSV import conflicted with another change');
    }
    return;
  }

  static Future<void> deleteUnitUser(String user, int unit) async {
    await _unitCommands.deleteUserAccess(unit, user);
    return;
  }

  static Future<void> deleteOccasionUser(OccasionUserModel profile) async {
    final result = await _profileCommands.delete(profile);
    if (result.status == ProfileCommandStatus.conflict) {
      throw StateError('Profile was changed by another editor');
    }
    if (result.status == ProfileCommandStatus.rejected) {
      throw StateError('Profile delete was rejected');
    }
    return;
  }

  static Future<OccasionUserModel> getOccasionUser(String id) async {
    final data =
        await _supabase.rpc('get_occasion_membership_for_edit_v1', params: {
      'p_occasion': RightsService.currentOccasionId()!,
      'p_user': id,
    });
    return OccasionUserModel.fromJson(data);
  }

  static Future<OccasionModel> getOccasion(int id) async {
    var data = await _supabase
        .from(Tb.occasions.table)
        .select()
        .eq(Tb.occasions.id, id)
        .single();
    return OccasionModel.fromJson(data);
  }

  static Future<dynamic> importUsersFromTickets(int occasionId) async {
    return _profileCommands.importFromTickets(occasionId);
  }
}

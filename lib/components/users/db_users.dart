import 'package:collection/collection.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/order_product_ticket_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
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
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OccasionEditorData {
  final List<OccasionUserModel> users;
  final List<FormModel> forms;
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
  final Map<int, FormModel> forms;
  final Map<int, FormFieldModel> formFields;

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
      final forms =
          List<FormModel>.from(payload.forms.map((x) => FormModel.fromJson(x)));
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

      final formMap = {for (var form in forms) form.key: form};
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
        (key, value) => MapEntry(int.parse(key), FormModel.fromJson(value)));
    final formFields = (json['form_fields'] as Map<String, dynamic>).map(
        (key, value) =>
            MapEntry(int.parse(key), FormFieldModel.fromJson(value)));

    // 2. Link the parsed models together
    final formMapByKey = {for (var f in forms.values) f.key: f};
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

    for (final field in formFields.values) {
      if (field.form != null && forms.containsKey(field.form)) {
        forms[field.form]!.relatedFields.add(field);
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
          if (formFieldModel.type == FormHelper.fieldTypeBirthDate) {
            final date = DateTime.tryParse(fieldValue as String);
            if (date != null) user.birthDate = date;
          } else if (formFieldModel.type == FormHelper.fieldTypeBirthYear) {
            final year = int.tryParse(fieldValue.toString());
            if (year != null) user.birthDate = DateTime(year);
          }
        }

        // Check for the group feature field if not already present
        if (user.groupFeatureAnswer == null &&
            formFieldModel.data?[FormHelper.isGroupFeatureField] == true) {
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
      var t = List<UnitUserModel>.from(
          result["data"].map((x) => UnitUserModel.fromJson(x)));
      return t;
    }
    return [];
  }

  static Future<void> updateUserInfo(OccasionUserModel oum) async {
    final response = await _supabase.rpc("update_user", params: {
      "input_data": {
        "occasion": oum.occasion!,
        "user": oum.user,
        "data": oum.data
      }
    });

    var code = response['code'];
    if (code != 200 && code != 201) {
      throw Exception(response['message']);
    }
  }

  static Future<String?> unsafeCreateUser(
      int occasion, String email, String pw, dynamic data) async {
    var newId = await _supabase.rpc("create_user_in_organization_with_data_ws",
        params: {
          "org": AppConfig.organization,
          "email": email,
          "password": pw,
          "data": data
        });
    if (newId == null) {
      throw Exception("Creating of user has failed.");
    }
    await addUserToOccasion(newId, occasion);
    return newId;
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
    var response = await _supabase.rpc("update_unit_user", params: {
      "input_data": uum,
    });
    var code = response['code'];
    if (code != 200 && code != 201) {
      throw Exception(response['message']);
    }
  }

  static Future<void> updateOccasionUser(OccasionUserModel oum) async {
    await AuthService.ensureCanUpdateUsers(oum);

    // Existing occasion users are updated atomically by one authoritative RPC.
    // This is the path used by both the Users and Stay grids.
    if (oum.user != null) {
      if (ClientSyncRuntime.isV1Selected) {
        final result = await _profileCommands.save(oum);
        if (result.status == ProfileCommandStatus.conflict) {
          throw StateError('Profile was changed by another editor');
        }
        if (result.status == ProfileCommandStatus.rejected) {
          throw StateError('Profile save was rejected');
        }
        oum.aggregateVersion = result.version;
        return;
      }
      final response = await _supabase.rpc(
        'save_occasion_user_for_edit',
        params: {'input_data': oum.toUpdateJson()},
      );
      final code = response['code'];
      if (code != 200) {
        throw Exception(response['message']);
      }
      return;
    }

    if (ClientSyncRuntime.isV1Selected) {
      final result = await _profileCommands.create(oum);
      if (result.status != ProfileCommandStatus.applied ||
          result.userId == null) {
        throw StateError('Profile create was rejected');
      }
      oum
        ..user = result.userId
        ..aggregateVersion = result.version;
      return;
    }

    final response = await _supabase.rpc("update_user", params: {
      "input_data": {
        "occasion": oum.occasion!,
        "user": oum.user,
        "data": oum.data
      }
    });

    var code = response['code'];
    if (code != 200 && code != 201) {
      throw Exception(response['message']);
    }

    oum.user ??= response['user'];
    await addUserToOccasion(oum.user!, oum.occasion!);

    if (oum.user != null) {
      await _supabase.from(Tb.occasion_users.table).upsert(oum.toUpdateJson());
    }
  }

  static Future<void> addUserToOccasion(String id, int occasion) async {
    if (ClientSyncRuntime.isV1Selected) {
      await _profileCommands.ensureMembership(occasion, id);
      return;
    }
    await _supabase.rpc("add_user_to_occasion", params: {
      "usr": id,
      "oc": occasion,
    });
  }

  static Future<void> addUserToUnit(String id, int unit) async {
    await _supabase.rpc("add_user_to_unit", params: {
      "usr": id,
      "unit_id": unit,
    });
  }

  static Future<void> importOccasionUsersFromCsv(
      List<Map<String, dynamic>> rows, List<String> deleteUserIds) async {
    final result = await _profileCommands.importProfiles(
        RightsService.currentOccasionId()!, rows, deleteUserIds);
    if (result.status == ProfileCommandStatus.rejected ||
        result.status == ProfileCommandStatus.conflict) {
      throw StateError('CSV import rejected or conflicted');
    }
  }

  static Future<void> deleteUnitUser(String user, int unit) async {
    if (ClientSyncRuntime.isV1Selected) {
      await _unitCommands.deleteUserAccess(unit, user);
      return;
    }
    await _supabase
        .rpc("delete_unit_user", params: {"usr": user, "unit_id": unit});
  }

  static Future<void> deleteOccasionUser(OccasionUserModel profile) async {
    final result = await _profileCommands.delete(profile);
    if (result.status == ProfileCommandStatus.conflict ||
        result.status == ProfileCommandStatus.rejected) {
      throw StateError('Profile delete rejected or conflicted');
    }
  }

  static Future<String?> getUserByEmail(String email) async {
    var data = await _supabase.rpc("get_user_id_by_email",
        params: {"email": email.toLowerCase()}).maybeSingle();
    if (data == null) {
      return null;
    }
    return data["id"];
  }

  static Future<String?> getLastTimeSignIn(String id) async {
    var data =
        await _supabase.rpc("get_last_sign_in_at", params: {"user_id": id});
    return data;
  }

  static Future<OccasionUserModel> getOccasionUser(String id) async {
    var data = await _supabase
        .from(Tb.occasion_users.table)
        .select()
        .eq(Tb.occasion_users.user, id)
        .eq(Tb.occasion_users.occasion, RightsService.currentOccasionId()!)
        .limit(1)
        .single();
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
    if (ClientSyncRuntime.isV1Selected) {
      return _profileCommands.importFromTickets(occasionId);
    }
    return await _supabase.rpc('import_users_from_tickets_ws',
        params: {'p_occasion_id': occasionId});
  }
}

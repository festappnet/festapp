import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

import 'unit_occasion_dashboard.dart';

import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/unit_commands.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/database_tables/tb.dart';

class DbUnits {
  static Future<UnitOccasionDashboard> getOccasionDashboard(
    int unitId, {
    SupabaseClient? client,
  }) async {
    final data = await (client ?? _supabase).rpc(
      'get_unit_edit_data',
      params: {'p_unit_id': unitId},
    );
    final result = UnitOccasionDashboard.fromJson(
      Map<String, dynamic>.from(data),
    );
    if (result.unitId != unitId) {
      throw StateError('Unit dashboard scope mismatch');
    }
    return result;
  }

  static final _supabase = Supabase.instance.client;
  static UnitCommands get _commands => SupabaseUnitCommands(_supabase);

  static Future<List<UnitModel>> getOccasionCopyUnits(int occasionId) async {
    final rows = await _supabase.rpc(
      'get_occasion_copy_units',
      params: {'p_occasion': occasionId},
    ) as List;
    return rows
        .map((row) => UnitModel.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  static Future<bool> hasOccasions(int unitId) async {
    final count = await _supabase
        .from(Tb.occasions.table)
        .count(CountOption.exact)
        .eq(Tb.occasions.unit, unitId);
    return count > 0;
  }

  /// Fetches a unit and its public occasions, or all occasions for an organization.
  ///
  /// [organizationId]: The ID of the organization (required).
  /// [unitId]: The ID of the specific unit (optional). If null, fetches all
  ///           occasions for the given [organizationId].
  static Future<UnitModel> getPublicOccasions(
    int organizationId,
    int? unitId,
  ) async {
    try {
      final result = await _supabase.rpc(
        "get_public_occasions",
        params: {
          'p_organization_id': organizationId,
          'p_unit_id': unitId, // This will be 'null' if unitId is null
        },
      );

      return UnitModel.fromJson(result);
    } catch (e) {
      // You can re-throw, log, or handle the error as needed.
      // For example:
      // if (e is PostgrestException) {
      //   print("Error fetching public occasions: ${e.message}");
      // }
      rethrow;
    }
  }

  static Future<void> updateUnit(UnitModel unit) async {
    final saved = await _commands.save(unit);
    unit
      ..title = saved.title
      ..data = saved.data
      ..aggregateVersion = saved.aggregateVersion;
    return;
  }

  static Future<int> createUnitAndAssignManager(String title) async {
    final response = await _supabase.rpc(
      "create_unit_and_assign_manager",
      params: {'title': title},
    );
    if (response['code'] == 200) {
      return response['data']['id'];
    } else {
      throw Exception(response['message']);
    }
  }

  static Future<void> deleteUnit(int unitId) async {
    final response = ClientCommandResponse.from(
      await ClientCommandTransport.supabase(
        _supabase,
        durable: true,
      ).invoke('delete_unit_client_sync_v1', {'p_unit': unitId}),
    );
    if (response.code != 200) throw StateError('Organizer deletion rejected');
  }
}

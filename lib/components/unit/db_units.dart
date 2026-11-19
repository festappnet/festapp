import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

import 'unit_occasion_dashboard.dart';
import 'unit_measurement_approval.dart';
import 'unit_website_consent.dart';

import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/unit_commands.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/database_tables/tb.dart';

class DbUnits {
  static Future<Map<String, dynamic>> getMetaPurchase(int unitId) async =>
      Map<String, dynamic>.from(
        await _supabase.rpc(
          'get_unit_meta_purchase',
          params: {'p_unit': unitId},
        ) as Map,
      );

  static Future<void> mutateMetaPurchase(
    String operation,
    Map<String, dynamic> params,
  ) async {
    await _supabase.rpc(operation, params: params);
  }

  static Future<UnitMeasurementApproval> getMetaCapiApproval(
    int unitId,
  ) async => UnitMeasurementApproval.fromJson(
    Map<String, dynamic>.from(
      await _supabase.rpc(
        'get_unit_meta_capi_approval',
        params: {'p_unit': unitId},
      ),
    ),
  );

  static Future<UnitMeasurementApproval> requestMetaCapiApproval(
    int unitId,
  ) async => UnitMeasurementApproval.fromJson(
    Map<String, dynamic>.from(
      await _supabase.rpc(
        'request_unit_meta_capi_approval',
        params: {'p_unit': unitId},
      ),
    ),
  );

  static Future<String> detectComplianzPolicy(int unitId, String origin) async {
    final response = await _supabase.functions.invoke(
      'probe-complianz',
      body: {'unitId': unitId, 'origin': origin},
    );
    return (response.data as Map)['policyId'] as String;
  }

  static Future<UnitWebsiteConsent> confirmDetectedComplianz(
    int unitId,
    String origin,
    String platform,
    String policyId,
    int version,
    String revision,
  ) async {
    try {
      final response = await _supabase.functions.invoke(
        'probe-complianz',
        body: {
          'unitId': unitId,
          'origin': origin,
          'confirm': true,
          'platform': platform,
          'expectedPolicyId': policyId,
          'version': version,
          'revision': revision,
        },
      );
      return UnitWebsiteConsent.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on FunctionException catch (error) {
      final details = error.details;
      if (error.status == 409 &&
          details is Map &&
          details['error'] == 'policy_changed') {
        throw const ComplianzPolicyChanged();
      }
      rethrow;
    }
  }

  static Future<UnitWebsiteConsent> getWebsiteConsent(int unitId) async =>
      UnitWebsiteConsent.fromJson(
        Map<String, dynamic>.from(
          await _supabase.rpc(
            'get_unit_website_consent_bindings',
            params: {'p_unit': unitId},
          ),
        ),
      );

  static Future<UnitWebsiteConsent> saveWebsiteConsent(
    int unitId,
    String origin,
    String platform,
    Map<String, dynamic> config,
    int version,
    String revision,
    bool confirm,
  ) async => UnitWebsiteConsent.fromJson(
    Map<String, dynamic>.from(
      await _supabase.rpc(
        'save_unit_website_consent_binding',
        params: {
          'p_unit': unitId,
          'p_website_origin': origin,
          'p_platform': platform,
          'p_provider_config': config,
          'p_expected_version': version,
          'p_expected_consent_revision': revision,
          'p_confirm': confirm,
        },
      ),
    ),
  );

  static Future<UnitWebsiteConsent> disableWebsiteConsent(
    String binding,
    int version,
  ) async => UnitWebsiteConsent.fromJson(
    Map<String, dynamic>.from(
      await _supabase.rpc(
        'disable_unit_website_consent_binding',
        params: {'p_binding': binding, 'p_expected_version': version},
      ),
    ),
  );

  static Future<Map<String, dynamic>> exportWebsiteConsent(
    String binding,
    int version,
  ) async => Map<String, dynamic>.from(
    await _supabase.rpc(
      'export_unit_website_consent_binding',
      params: {'p_binding': binding, 'p_expected_version': version},
    ),
  );

  static Future<UnitMeasurementApproval> getMeasurementApproval(
    int unitId,
  ) async => UnitMeasurementApproval.fromJson(
    Map<String, dynamic>.from(
      await _supabase.rpc(
        'get_unit_measurement_approval',
        params: {'p_unit': unitId},
      ),
    ),
  );

  static Future<UnitMeasurementApproval> requestMeasurementApproval(
    int unitId,
  ) async => UnitMeasurementApproval.fromJson(
    Map<String, dynamic>.from(
      await _supabase.rpc(
        'request_unit_measurement_approval',
        params: {'p_unit': unitId},
      ),
    ),
  );

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

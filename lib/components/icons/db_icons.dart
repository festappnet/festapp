import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/components/icons/icon_commands.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown when delete_icon reports the icon is still referenced (HTTP 409).
class IconInUseException implements Exception {
  final int places;
  final int pathGroups;
  final int placeTypes;
  IconInUseException(this.places, this.pathGroups, this.placeTypes);
}

class DbIcons {
  static final _supabase = Supabase.instance.client;
  static final IconCommands _commands = SupabaseIconCommands(_supabase);
  static const int maxBytes = 51200; // 50 KB

  /// Icons visible in this context: the current unit's icons plus legacy
  /// org-wide icons (unit IS NULL). Mirrors the deployed PostgREST filter.
  static Future<List<IconModel>> getManagedIcons() async {
    final unitId = RightsService.currentUnit()?.id;
    final org = AppConfig.organization;
    if (ClientSyncRuntime.isV1Selected &&
        RightsService.currentOccasionId() != null) {
      final response = await _supabase.rpc('get_map_editor_bundle_v1', params: {
        'p_occasion': RightsService.currentOccasionId()!,
      });
      final bundle = (response as Map).cast<String, dynamic>();
      return ((bundle['icons'] as List?) ?? const [])
          .map((x) => IconModel.fromJson((x as Map).cast<String, dynamic>()))
          .toList();
    }
    final query = _supabase.from(Tb.icons.table).select();
    final data = unitId != null
        ? await query.or('${Tb.icons.unit}.eq.$unitId,'
            'and(${Tb.icons.unit}.is.null,${Tb.icons.organization}.eq.$org)')
        : await query.eq(Tb.icons.organization, org);
    return data.map<IconModel>((x) => IconModel.fromJson(x)).toList();
  }

  /// Inserts a new SVG icon owned by the current unit. RLS enforces
  /// created_by = auth.uid() and unit membership.
  static Future<IconModel> insertIcon({
    required String link,
    required String svgData,
  }) async {
    final unitId = RightsService.currentUnit()?.id;
    if (unitId == null) {
      throw Exception('no_unit');
    }
    final result =
        await _commands.create(unitId: unitId, link: link, svg: svgData);
    if (result.status != IconCommandStatus.applied || result.icon == null) {
      throw StateError('Icon save was rejected');
    }
    return result.icon!;
  }

  /// Deletes an icon via the delete_icon RPC (handles permission + ref checks).
  static Future<void> deleteIcon(int iconId) async {
    final unitId = RightsService.currentUnit()?.id;
    if (unitId == null)
      throw StateError('Icon deletion requires its unit context');
    final result = await _commands.delete(unitId: unitId, iconId: iconId);
    if (result.status == IconCommandStatus.applied ||
        result.status == IconCommandStatus.unchanged) return;
    if (result.status == IconCommandStatus.rejected && result.refs != null) {
      throw IconInUseException(
          (result.refs!['places'] as num?)?.toInt() ?? 0,
          (result.refs!['path_groups'] as num?)?.toInt() ?? 0,
          (result.refs!['place_types'] as num?)?.toInt() ?? 0);
    }
    throw StateError('Icon delete was rejected');
  }
}

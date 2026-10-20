import 'package:fstapp/components/icons/place_type_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/map/map_commands.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/database_tables/tb.dart';

/// Versioned occasion place-type commands and their editor projection.
class DbPlaceTypes {
  static final _supabase = Supabase.instance.client;
  static final MapCommands _commands = SupabaseMapCommands(_supabase);

  static Future<List<PlaceTypeModel>> getPlaceTypes([int? occasionId]) async {
    final occ = occasionId ?? RightsService.currentOccasionId();
    if (!RightsService.isEditorView() && !RightsService.isEditor()) {
      final rows = await _supabase
          .from(Tb.place_types.table)
          .select()
          .eq(Tb.place_types.occasion, occ!)
          .order(Tb.place_types.order);
      return rows.map(PlaceTypeModel.fromJson).toList();
    }
    final response = await _supabase.rpc('get_map_editor_bundle_v1', params: {
      'p_occasion': occ!,
    });
    final bundle = (response as Map).cast<String, dynamic>();
    return ((bundle['placeTypes'] as List?) ?? const [])
        .map((x) => PlaceTypeModel.fromJson((x as Map).cast<String, dynamic>()))
        .toList();
  }

  static Future<PlaceTypeModel> upsert(PlaceTypeModel type) async {
    type.occasion ??= RightsService.currentOccasionId();
    final result = await _commands.savePlaceType(type.occasion!, type);
    if (result.status == MapCommandStatus.conflict) {
      throw StateError('Place type was changed by another editor');
    }
    if (result.status == MapCommandStatus.rejected || result.entity == null) {
      throw StateError('Place type save was rejected');
    }
    return result.entity!;
  }

  static Future<void> delete(PlaceTypeModel type) async {
    final result = await _commands.deletePlaceType(
        type.occasion ?? RightsService.currentOccasionId()!, type);
    if (result.status == MapCommandStatus.conflict) {
      throw StateError('Place type was changed by another editor');
    }
    if (result.status == MapCommandStatus.rejected) {
      throw StateError('Place type delete was rejected');
    }
    return;
  }
}

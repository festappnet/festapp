import 'package:fstapp/components/information/game/game_settings_model.dart';
import 'package:fstapp/components/images/db_images.dart';
import 'package:fstapp/components/images/image_model.dart';
import 'package:fstapp/components/occasion/occasion_commands.dart';
import 'package:fstapp/components/occasion/occasion_media_copier.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion_services/service_item_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DbOccasions {
  static final _supabase = Supabase.instance.client;
  static final OccasionCommands _commands = SupabaseOccasionCommands(_supabase);

  static const String serviceNone = "none";
  static const String servicePaid = "paid";
  static const String serviceUsed = "used";
  static const String serviceTypeFood = "food";
  static const String serviceTypeAccommodation = "accommodation";

  static Future<List<ServiceItemModel>> getAllServices(String type) async {
    var data = await _supabase.rpc("get_all_service_items", params: {
      'oc': RightsService.currentOccasionId(),
      'type': type,
    });
    var items = List<ServiceItemModel>.from(
        data["data"].map((x) => ServiceItemModel.fromJson(x)));
    return items;
  }

  /// Creates a service item and returns the raw RPC result so callers can
  /// distinguish the outcome: 200 = created, 400 = duplicate code,
  /// 403 = not a manager on the occasion.
  static Future<Map<String, dynamic>> createService(
      String type, ServiceItemModel item) async {
    if (ClientSyncRuntime.isV1Selected) {
      return _commands.createService(
        RightsService.currentOccasionId()!,
        type,
        item.code,
        item.title ?? '',
        item.reference,
      );
    }
    var result = await _supabase.rpc("create_service_item", params: {
      'oc': RightsService.currentOccasionId(),
      'type': type,
      'code': item.code,
      'title': item.title,
      'reference': item.reference,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  static Future<bool> updateService(String type, ServiceItemModel item) async {
    if (ClientSyncRuntime.isV1Selected) {
      final result = await _commands.updateService(
        RightsService.currentOccasionId()!,
        type,
        item.code,
        item.title ?? '',
        item.reference,
      );
      return result['code'] == 200;
    }
    var result = await _supabase.rpc("update_service_item", params: {
      'oc': RightsService.currentOccasionId(),
      'type': type,
      'code': item.code,
      'new_title': item.title,
      'new_reference': item.reference,
    });
    return result["code"] == 200;
  }

  static Future<bool> deleteService(String type, ServiceItemModel item,
      [bool force = false]) async {
    final occasionId = RightsService.currentOccasionId()!;
    final result = ClientSyncRuntime.isV1Selected
        ? await _commands.deleteService(occasionId, type, item.code, force)
        : await _supabase.rpc("delete_service_item", params: {
            'oc': occasionId,
            'code': item.code,
            'type': type,
            'force': force,
          });
    return result["code"] == 200;
  }

  static Future<GameSettingsModel?> loadGameSettings() async {
    if (ClientSyncRuntime.isV1Selected) {
      final data = (await ClientSyncProjection.occasionConfig())['data'];
      if (data is Map && data[Tb.occasions.data_game] is Map) {
        return GameSettingsModel.fromJson(
          (data[Tb.occasions.data_game] as Map).cast<String, dynamic>(),
        );
      }
      return null;
    }
    final response = await _supabase
        .from(Tb.occasions.table)
        .select(Tb.occasions.data)
        .eq(Tb.occasions.id, RightsService.currentOccasionId()!)
        .maybeSingle();

    if (response != null) {
      final data = response[Tb.occasions.data];
      if (data != null && data[Tb.occasions.data_game] != null) {
        return GameSettingsModel.fromJson(data[Tb.occasions.data_game]);
      }
    }
    return null;
  }

  static Future<bool> updateGameSettings(GameSettingsModel settings) async {
    if (ClientSyncRuntime.isV1Selected) {
      final response = await _commands.updateGameSettings(
        RightsService.currentOccasionId()!,
        settings.start,
        settings.end,
      );
      return response['code'] == 200;
    }
    final response = await _supabase.rpc('game_update_settings', params: {
      'oc': RightsService.currentOccasionId(),
      'new_start_time': settings.start?.toIso8601String(),
      'new_end_time': settings.end?.toIso8601String(),
    });

    if (response == null) {
      return false;
    }

    return response != null && response['code'] == 200;
  }

  static Future<OccasionModel> getOccasion(int oc) async {
    var data = await _supabase
        .from(Tb.occasions.table)
        .select()
        .eq(Tb.occasions.id, oc)
        .single();
    return OccasionModel.fromJson(data);
  }

  static Future<OccasionModel> getOccasionByLink(String link) async {
    var data = await _supabase.rpc(
        ClientSyncRuntime.isV1Selected
            ? 'get_occasion_for_edit_v1'
            : 'get_occasion_by_link',
        params: {
          ClientSyncRuntime.isV1Selected ? 'p_link' : 'link_param': link,
        });

    if (data == null) {
      throw const PostgrestException(message: 'Occasion not found');
    }

    return OccasionModel.fromJson(data);
  }

  static Future<List<OccasionModel>> getAllOccasionsForEdit(int unitId) async {
    var data = await _supabase.rpc("get_all_occasions_for_edit_v212", params: {
      "unit_id": unitId,
    });
    return List<OccasionModel>.from(data.map((x) => OccasionModel.fromJson(x)));
  }

  static Future<void> updateOccasion(OccasionModel occasionModel) async {
    if (ClientSyncRuntime.isV1Selected) {
      final saved = occasionModel.id == null
          ? await _commands.create(occasionModel)
          : await _commands.save(occasionModel);
      occasionModel.id = saved.id;
      occasionModel.aggregateVersion = saved.aggregateVersion;
      return;
    }
    final Map<String, dynamic> occasionJson = occasionModel.toJson();
    await _supabase.rpc("update_occasion_203", params: {
      "input_data": occasionJson,
    });
  }

  /// Returns false only when the event exists but its media could not be copied.
  static Future<bool> duplicateOccasion(int oc) async {
    final ocId = ClientSyncRuntime.isV1Selected
        ? await _commands.duplicate(oc)
        : await _supabase.rpc("duplicate_occasion", params: {"oc": oc}) as int;

    try {
      final occasion = await getOccasion(ocId);
      await copyOccasionMedia(occasion, DbImages.createCopyOfImage);
      await updateOccasion(occasion);
      return true;
    } catch (error, stackTrace) {
      // The database copy is committed. Keep its existing public media links
      // and report the partial result instead of inviting a second copy.
      debugPrint('Occasion $ocId was copied, but media setup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  static Future<void> deleteOccasion(int oc) async {
    if (ClientSyncRuntime.isV1Selected) {
      await _commands.delete(oc);
    } else {
      await _supabase.rpc('delete_occasion', params: {'oc': oc});
    }

    final data = await _supabase
        .from(Tb.images.table)
        .select()
        .isFilter(Tb.images.occasion, null)
        .isFilter(Tb.images.unit, null);
    final orphanImages =
        List<ImageModel>.from(data.map((x) => ImageModel.fromJson(x)));

    for (var img in orphanImages) {
      await DbImages.removeImage(img.link!);
    }

    await _supabase
        .from(Tb.images.table)
        .delete()
        .isFilter(Tb.images.occasion, null)
        .isFilter(Tb.images.unit, null);
  }
}

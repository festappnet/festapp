import 'dart:convert';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:fstapp/components/information/game/game_settings_model.dart';
import 'package:fstapp/components/images/db_images.dart';
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
    return _commands.createService(
      RightsService.currentOccasionId()!,
      type,
      item.code,
      item.title ?? '',
      item.reference,
    );
  }

  static Future<bool> updateService(String type, ServiceItemModel item) async {
    final result = await _commands.updateService(
      RightsService.currentOccasionId()!,
      type,
      item.code,
      item.title ?? '',
      item.reference,
    );
    return result['code'] == 200;
  }

  static Future<bool> deleteService(String type, ServiceItemModel item,
      [bool force = false]) async {
    final occasionId = RightsService.currentOccasionId()!;
    final result =
        await _commands.deleteService(occasionId, type, item.code, force);
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
    final response = await _commands.updateGameSettings(
      RightsService.currentOccasionId()!,
      settings.start,
      settings.end,
    );
    return response['code'] == 200;
  }

  static Future<OccasionModel> getOccasion(int oc) async {
    final data = await _supabase
        .rpc('get_occasion_for_authoring_v1', params: {'p_occasion': oc});
    return OccasionModel.fromJson(data);
  }

  static Future<OccasionModel> getOccasionByLink(String link) async {
    final data = await _supabase
        .rpc('get_occasion_for_edit_v1', params: {'p_link': link});

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

  static Future<OccasionModel> getTicketLayoutForEdit(
      OccasionModel current) async {
    final snapshot = Map<String, dynamic>.from(await _supabase.rpc(
        'get_ticket_layout_for_authoring_v1',
        params: {'p_occasion': current.id}));
    return OccasionModel(
      id: (snapshot['occasion'] as num).toInt(),
      link: current.link,
      isOpen: current.isOpen,
      isHidden: current.isHidden,
      isPromoted: current.isPromoted,
      aggregateVersion: (snapshot['aggregate_version'] as num).toInt(),
      features: [
        TicketFeature.fromJson({
          'code': 'ticket',
          ...Map<String, dynamic>.from(snapshot['appearance'] as Map),
        })
      ],
    );
  }

  static Future<void> updateTicketLayout(OccasionModel occasion) async {
    final ticket = occasion.features.whereType<TicketFeature>().single;
    final change = Map<String, dynamic>.from(jsonDecode(jsonEncode({
      'expected': ticket.layoutChange != null
          ? ticket.layoutChange!['expected']
          : ticket.layout,
      'next': ticket.layout,
      'appearance': {
        'background': ticket.ticketBackground,
        'ticket_type': ticket.ticketType
      },
    })) as Map);
    final id = occasion.id!;
    final version = occasion.aggregateVersion;
    final payload = {
      'occasion': id,
      'expectedVersion': version,
      'change': change
    };
    final principal = '${_supabase.rest.url}:${_supabase.auth.currentUser!.id}';
    final commandId = await ClientCommandIdentity.claimIntent(
        'ticket_layout.save', payload,
        principalBinding: principal, scopeBinding: id.toString());
    final saved = await _commands.saveTicketLayout(id, version, change,
        commandId: commandId);
    await ClientCommandIdentity.completeIntent('ticket_layout.save', payload,
        commandId: commandId, principalBinding: principal);
    occasion.aggregateVersion = saved.aggregateVersion;
    occasion.features = saved.features;
    occasion.markTicketLayoutSaved();
  }

  static Future<void> updateOccasion(OccasionModel occasionModel) async {
    final OccasionModel saved;
    saved = occasionModel.id == null
        ? await _commands.create(occasionModel)
        : await _commands.save(occasionModel);

    occasionModel.id = saved.id;
    occasionModel.link = saved.link;
    occasionModel.aggregateVersion = saved.aggregateVersion;
    occasionModel.features = saved.features;
    occasionModel.markTicketLayoutSaved();
  }

  /// Returns false only when the event exists but its media could not be copied.
  static Future<bool> duplicateOccasion(int oc,
      {int? targetUnitId, String locale = 'en'}) async {
    final ocId = await _commands.duplicate(oc,
        targetUnitId: targetUnitId, locale: locale);

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

  /// Keeps the committed result visible even if the following media work fails.
  static Future<({int occasionId, bool mediaCopied})> duplicateDemoOccasion(
      int source,
      {required int targetUnitId,
      required String commandId,
      String locale = 'en'}) async {
    final response =
        await _supabase.rpc('duplicate_occasion_client_sync_v1', params: {
      'p_occasion': source,
      'p_target_unit': targetUnitId,
      'p_command_id': commandId,
      'p_locale': locale,
    });
    final id = (response['data']['occasionId'] as num).toInt();
    var ready = false;
    try {
      final copy = await getOccasion(id);
      await copyOccasionMedia(copy, DbImages.createCopyOfImage);
      await updateOccasion(copy);
      ready = true;
    } catch (_) {
      // Never repeat SQL creation to recover a media failure.
    }
    return (occasionId: id, mediaCopied: ready);
  }

  static Future<void> deleteOccasion(int oc) async {
    await _commands.delete(oc);
  }
}

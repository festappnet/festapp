import 'dart:convert';

import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:fstapp/components/information/game/game_settings_model.dart';
import 'package:fstapp/components/images/db_images.dart';
import 'package:fstapp/components/occasion/occasion_commands.dart';
import 'package:fstapp/components/occasion/occasion_duplication.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion_services/service_item_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
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
    var data = await _supabase.rpc(
      "get_all_service_items",
      params: {'oc': RightsService.currentOccasionId(), 'type': type},
    );
    var items = List<ServiceItemModel>.from(
      data["data"].map((x) => ServiceItemModel.fromJson(x)),
    );
    return items;
  }

  /// Creates a service item and returns the raw RPC result so callers can
  /// distinguish the outcome: 200 = created, 400 = duplicate code,
  /// 403 = not a manager on the occasion.
  static Future<Map<String, dynamic>> createService(
    String type,
    ServiceItemModel item,
  ) async {
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

  static Future<bool> deleteService(
    String type,
    ServiceItemModel item, [
    bool force = false,
  ]) async {
    final occasionId = RightsService.currentOccasionId()!;
    final result = await _commands.deleteService(
      occasionId,
      type,
      item.code,
      force,
    );
    return result["code"] == 200;
  }

  static Future<GameSettingsModel?> loadGameSettings() async {
    final response = await _supabase.rpc(
      'get_game_settings_for_authoring_v1',
      params: {'p_occasion': RightsService.currentOccasionId()!},
    );
    return GameSettingsModel.fromJson(
      (response['game'] as Map).cast<String, dynamic>(),
    )..aggregateVersion = (response['version'] as num).toInt();
  }

  static Future<bool> updateGameSettings(GameSettingsModel settings) async {
    final response = await _commands.updateGameSettings(
      RightsService.currentOccasionId()!,
      settings.start,
      settings.end,
      expectedVersion: settings.aggregateVersion,
    );
    if (response['code'] == 200 && response['version'] is num) {
      settings.aggregateVersion = (response['version'] as num).toInt();
    }
    return response['code'] == 200;
  }

  static Future<OccasionModel> getOccasion(int oc) async {
    final data = await _supabase.rpc(
      'get_occasion_for_authoring_v1',
      params: {'p_occasion': oc},
    );
    return OccasionModel.fromJson(data);
  }

  static Future<OccasionModel> getOccasionByLink(String link) async {
    final data = await _supabase.rpc(
      'get_occasion_for_edit_v1',
      params: {'p_link': link},
    );

    if (data == null) {
      throw const PostgrestException(message: 'Occasion not found');
    }

    return OccasionModel.fromJson(data);
  }

  static Future<List<OccasionModel>> getAllOccasionsForEdit(int unitId) async {
    var data = await _supabase.rpc(
      "get_all_occasions_for_edit_v212",
      params: {"unit_id": unitId},
    );
    return List<OccasionModel>.from(data.map((x) => OccasionModel.fromJson(x)));
  }

  static Future<OccasionModel> getTicketLayoutForEdit(
    OccasionModel current,
  ) async {
    final snapshot = Map<String, dynamic>.from(
      await _supabase.rpc(
        'get_ticket_layout_for_authoring_v1',
        params: {'p_occasion': current.id},
      ),
    );
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
        }),
      ],
    );
  }

  static Future<void> updateTicketLayout(OccasionModel occasion) async {
    final ticket = occasion.features.whereType<TicketFeature>().single;
    final change = Map<String, dynamic>.from(
      jsonDecode(
        jsonEncode({
          'expected': ticket.layoutChange != null
              ? ticket.layoutChange!['expected']
              : ticket.layout,
          'next': ticket.layout,
          'appearance': {
            'background': ticket.ticketBackground,
            'ticket_type': ticket.ticketType,
          },
        }),
      ) as Map,
    );
    final id = occasion.id!;
    final version = occasion.aggregateVersion;
    final payload = {
      'occasion': id,
      'expectedVersion': version,
      'change': change,
    };
    final principal = '${_supabase.rest.url}:${_supabase.auth.currentUser!.id}';
    final commandId = await ClientCommandIdentity.claimIntent(
      'ticket_layout.save',
      payload,
      principalBinding: principal,
      scopeBinding: id.toString(),
    );
    final saved = await _commands.saveTicketLayout(
      id,
      version,
      change,
      commandId: commandId,
    );
    await ClientCommandIdentity.completeIntent(
      'ticket_layout.save',
      payload,
      commandId: commandId,
      principalBinding: principal,
    );
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

  static final _duplicator = OccasionDuplicator(
    commands: _commands,
    loadOccasion: getOccasion,
    copyImage: DbImages.createCopyOfImage,
  );

  /// Returns false only when the event exists but its media could not be copied.
  static Future<bool> duplicateOccasion(
    int oc, {
    int? targetUnitId,
    String locale = 'en',
  }) async {
    final result = await _duplicator.duplicate(
      oc,
      targetUnitId: targetUnitId,
      locale: locale,
    );
    return result.mediaCopied;
  }

  /// Keeps the committed result visible even if the following media work fails.
  static Future<({int occasionId, bool mediaCopied})> duplicateDemoOccasion(
    int source, {
    required int targetUnitId,
    required String commandId,
    String locale = 'en',
  }) => _duplicator.duplicate(
    source,
    targetUnitId: targetUnitId,
    commandId: commandId,
    locale: locale,
  );

  static Future<void> deleteOccasion(int oc) async {
    await _commands.delete(oc);
  }
}

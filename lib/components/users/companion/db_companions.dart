import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/components/users/companion/companion_model.dart';
import 'package:fstapp/components/users/companion/companion_commands.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/map/db_places.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DbCompanions {
  static final _supabase = Supabase.instance.client;
  static SupabaseCompanionCommands get _commands =>
      SupabaseCompanionCommands(_supabase);

  static Future<List<CompanionModel>> getAllCompanions() async {
    if (ClientSyncRuntime.isV1Selected) {
      return ClientSyncProjection.companions();
    }
    var data = await _supabase.rpc("get_user_companions_data", params: {
      'p_occasion': RightsService.currentOccasionId(),
    });
    var companions = List<CompanionModel>.from(
        data["data"].map((x) => CompanionModel.fromJson(x)));
    ClientSyncProjection.hydrateCompanionAccommodations(
      companions,
      occasionServices: RightsService.currentOccasion()?.services,
      places: await DbPlaces.getMapPlaces(),
    );
    return companions;
  }

  static Future<void> signIn(
      BuildContext context, int eventId, CompanionModel companion) async {
    await DbEvents.signInToEvent(context, eventId,
        UserInfoModel(name: companion.name, id: companion.id));
  }

  static Future<void> signOut(
      BuildContext context, int eventId, CompanionModel companion) async {
    await DbEvents.signOutFromEvent(context, eventId,
        UserInfoModel(name: companion.name, id: companion.id));
  }

  static Future<void> create(String name) async {
    await _commands.createSelf(RightsService.currentOccasionId()!, name);
    return;
  }

  static Future<void> deleteSelf(CompanionModel companion) async {
    await _commands.deleteSelf(
      RightsService.currentOccasionId()!,
      companion.id,
    );
  }

  static Future<void> assignExisting(String ownerId, String companionId) =>
      _commands.assignExisting(
          RightsService.currentOccasionId()!, ownerId, companionId);

  static Future<void> unassignExisting(String ownerId, String companionId) =>
      _commands.unassignExisting(
          RightsService.currentOccasionId()!, ownerId, companionId);
}

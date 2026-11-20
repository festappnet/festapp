import 'package:supabase_flutter/supabase_flutter.dart';

class UnitPickerFavorites {
  UnitPickerFavorites(this.userId);

  final String userId;

  Future<Set<int>> load() async {
    final ids = await Supabase.instance.client.rpc<List<dynamic>>(
      'get_unit_picker_favorites',
      params: {'p_user_id': userId},
    );
    return ids.cast<int>().toSet();
  }

  Future<void> save(int unitId, bool favorite) async {
    await Supabase.instance.client.rpc(
      'set_unit_picker_favorite',
      params: {
        'p_user_id': userId,
        'p_unit_id': unitId,
        'p_favorite': favorite,
      },
    );
  }
}

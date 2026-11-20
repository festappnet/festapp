import 'package:supabase_flutter/supabase_flutter.dart';

class UnitPickerFavorites {
  UnitPickerFavorites(this.userId);

  final String userId;

  SupabaseQueryBuilder get _table =>
      Supabase.instance.client.from('unit_picker_favorites');

  Future<Set<int>> load() async {
    final rows = await _table.select('unit_id').eq('user_id', userId);
    return {for (final row in rows) row['unit_id'] as int};
  }

  Future<void> save(int unitId, bool favorite) async {
    if (favorite) {
      await _table.upsert(
        {'user_id': userId, 'unit_id': unitId},
        onConflict: 'user_id,unit_id',
        ignoreDuplicates: true,
      );
    } else {
      await _table.delete().eq('user_id', userId).eq('unit_id', unitId);
    }
  }
}

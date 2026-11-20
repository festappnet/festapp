import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UnitPickerFavorites extends ChangeNotifier {
  UnitPickerFavorites(this.userId, this._ids);

  final String userId;
  final Set<int> _ids;
  final Set<int> _savingIds = {};

  bool isFavorite(int? unitId) => _ids.contains(unitId);
  bool isSaving(int unitId) => _savingIds.contains(unitId);

  Future<void> save(int unitId, bool favorite) async {
    if (!_savingIds.add(unitId)) return;
    notifyListeners();
    try {
      await Supabase.instance.client.rpc(
        'set_unit_picker_favorite',
        params: {
          'p_user_id': userId,
          'p_unit_id': unitId,
          'p_favorite': favorite,
        },
      );
      if (favorite) {
        _ids.add(unitId);
      } else {
        _ids.remove(unitId);
      }
    } finally {
      _savingIds.remove(unitId);
      notifyListeners();
    }
  }
}

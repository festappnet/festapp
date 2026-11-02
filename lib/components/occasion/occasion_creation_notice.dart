/// One pending acknowledgement per destination unit, consumed by its next list.
/// This is transient navigation feedback, never a persisted "new" sale state.
class OccasionCreationNotice {
  static final Map<int, int> _pending = {};
  static void record(int unit, int occasion) => _pending[unit] = occasion;
  static int? peek(int unit) => _pending[unit];
  static int? take(int unit) => _pending.remove(unit);
}

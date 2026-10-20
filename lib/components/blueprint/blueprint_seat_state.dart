/// Festapp's persisted seat lifecycle, including legacy reservation overlays.
enum BlueprintSeatState {
  empty,
  available,
  selected,
  selectedByMe,
  ordered,
  used,
  blocked,
}

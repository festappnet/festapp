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

/// RGBA fills shared by the map and its status legend.
const blueprintSeatStateFills = <BlueprintSeatState, String>{
  BlueprintSeatState.available: '#267329FF',
  BlueprintSeatState.selectedByMe: '#267329FF',
  BlueprintSeatState.selected: '#00000042',
  BlueprintSeatState.ordered: '#0000001F',
  BlueprintSeatState.used: '#412673FF',
  BlueprintSeatState.blocked: '#000000DE',
  BlueprintSeatState.empty: '#267329FF',
};

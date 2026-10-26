import 'package:fstapp/components/information/information_model.dart';

List<InformationModel> applyInformationExpansionState(
  List<InformationModel> information,
  Set<int> expandedInformationIds,
) {
  for (final item in information) {
    item.isExpanded = expandedInformationIds.contains(item.id);
  }
  return information;
}

void updateExpandedInformationIds(
  Set<int> expandedInformationIds,
  int? informationId,
  bool isExpanded,
) {
  if (informationId == null) return;
  if (isExpanded) {
    expandedInformationIds.add(informationId);
  } else {
    expandedInformationIds.remove(informationId);
  }
}

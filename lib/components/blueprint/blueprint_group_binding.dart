import 'package:venue_seat_picker/venue_seat_picker.dart';

/// Physical assemblies may nest below a stable commercial group.
String? blueprintCommercialGroupFor(LayoutNode seat, VenueLayoutDocument document,
    {required Map<String, int> groupProducts, String? currentGroupId}) {
  final nodes = {for (final node in document.nodes) node.id: node};
  final ancestors = <LayoutNode>[];
  final seen = <String>{};
  var parent = nodes[seat.parentId];
  while (parent != null && seen.add(parent.id)) {
    if (const {'group', 'table', 'furniture'}.contains(parent.kind)) {
      ancestors.add(parent);
    }
    parent = nodes[parent.parentId];
  }
  for (final node in ancestors) {
    if (node.id == currentGroupId) return currentGroupId;
  }
  for (final node in ancestors) {
    if (groupProducts.containsKey(node.id)) return node.id;
  }
  for (final node in ancestors) {
    if (node.kind == 'group') return node.id;
  }
  return ancestors.isEmpty ? null : ancestors.first.id;
}

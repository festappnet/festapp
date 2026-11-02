import 'package:venue_seat_picker/venue_seat_picker.dart';

/// Optional visual navigation intent; it grants no selection or mutation rights.
class BlueprintFocusTarget {
  const BlueprintFocusTarget(this.blueprintId, this.nodeIds);
  final int blueprintId;
  final Set<String> nodeIds;

  static BlueprintFocusTarget? fromQuery(Map<String, String> query) {
    final id = int.tryParse(query['blueprintId'] ?? '');
    if (id == null || id <= 0) return null;
    final nodes = [
      if (query['blueprintNodeId'] != null) query['blueprintNodeId']!,
      ...?query['blueprintNodeIds']?.split(','),
    ].map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    return BlueprintFocusTarget(id, Set.unmodifiable(nodes));
  }

  Set<String> nodesFor(int? loadedBlueprintId, VenueLayoutDocument document) =>
      loadedBlueprintId == blueprintId
      ? document.nodes
            .where((node) => nodeIds.contains(node.id))
            .map((node) => node.id)
            .toSet()
      : const {};
}

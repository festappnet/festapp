import 'package:venue_seat_picker/venue_seat_picker.dart';

/// Optional visual navigation intent; it grants no selection or mutation rights.
class BlueprintFocusTarget {
  const BlueprintFocusTarget(this.blueprintId, this.nodeId);
  final int blueprintId;
  final String? nodeId;

  static BlueprintFocusTarget? fromQuery(Map<String, String> query) {
    final id = int.tryParse(query['blueprintId'] ?? '');
    if (id == null || id <= 0) return null;
    final node = query['blueprintNodeId']?.trim();
    return BlueprintFocusTarget(id, node == null || node.isEmpty ? null : node);
  }

  String? nodeFor(int? loadedBlueprintId, VenueLayoutDocument document) =>
      loadedBlueprintId == blueprintId &&
          nodeId != null &&
          document.nodes.any((node) => node.id == nodeId)
      ? nodeId
      : null;
}

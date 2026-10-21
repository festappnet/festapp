import 'package:venue_seat_picker/venue_seat_picker.dart';

/// Explicit completion of the partial physical profile emitted by the old
/// importer. Manual chair poses remain intact; new chairs use normal packing.
VenueLayoutDocument normalizeBlueprintTableSeating(
    VenueLayoutDocument document) {
  return document.copyWith(nodes: [
    for (final node in document.nodes)
      if (node.kind == 'table' &&
          node.seating.containsKey('width') &&
          node.seating.containsKey('height') &&
          node.seating.containsKey('gap') &&
          !node.seating.containsKey('spacing') &&
          !node.seating.containsKey('edgePadding') &&
          document.attachments.any((a) =>
              a['targetId'] == node.id && a['placement']?['mode'] == 'free'))
        node.copyWith(seating: {
          ...TableSeating.fromDocument(document, node).record,
          'edgePadding': 0.0,
        })
      else
        node,
  ]);
}

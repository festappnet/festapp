import 'canonical_contract.dart';
import 'model.dart';
import 'table_seating.dart';

VenueLayoutDocument setNodeStyleLeaf(
  VenueLayoutDocument document,
  String id,
  List<String> path, {
  Object? value,
  bool unset = false,
}) => document.copyWith(
  nodes: [
    for (final node in document.nodes)
      node.id == id
          ? node.copyWith(
              style: patchCanonicalStyle(
                node.style,
                path,
                value: value,
                unset: unset,
              ),
            )
          : node,
  ],
);
VenueLayoutDocument setKindStyleLeaf(
  VenueLayoutDocument document,
  String kind,
  List<String> path, {
  Object? value,
  bool unset = false,
}) {
  if (!canonicalStyleKinds.contains(kind)) {
    throw ArgumentError('invalid_style_kind');
  }
  final kinds = Map<String, dynamic>.from(
    document.styles['kinds'] as Map? ?? {},
  );
  final next = patchCanonicalStyle(
    Map<String, dynamic>.from(kinds[kind] as Map? ?? {}),
    path,
    value: value,
    unset: unset,
  );
  if (next.isEmpty) {
    kinds.remove(kind);
  } else {
    kinds[kind] = next;
  }
  return document.copyWith(styles: {...document.styles, 'kinds': kinds});
}

VenueLayoutDocument setDocumentLabelLeaf(
  VenueLayoutDocument document,
  String field, {
  Object? value,
  bool unset = false,
}) {
  final next = patchCanonicalStyle(
    {'label': document.styles['label'] ?? {}},
    ['label', field],
    value: value,
    unset: unset,
  );
  return document.copyWith(
    styles: {...document.styles, 'label': next['label'] ?? {}},
  );
}

VenueLayoutDocument setTableChildStyleLeaf(
  VenueLayoutDocument document,
  String tableId,
  List<String> path, {
  Object? value,
  bool unset = false,
}) => document.copyWith(
  nodes: [
    for (final node in document.nodes)
      node.id == tableId
          ? node.copyWith(
              childStyles: {
                'seat': patchCanonicalStyle(
                  Map<String, dynamic>.from(
                    node.childStyles['seat'] as Map? ?? {},
                  ),
                  path,
                  value: value,
                  unset: unset,
                ),
              },
            )
          : node,
  ],
);

/// Resolved portable declarations for a fragment crossing a document boundary.
Map<String, dynamic> materializedNodeStyle(
  VenueLayoutDocument document,
  LayoutNode node,
) {
  if (!canonicalStyleKinds.contains(node.kind)) return node.style;
  final appearance = resolveNodeAppearance(document, node);
  if (const {'image', 'vector'}.contains(node.kind)) {
    return {'opacity': appearance.values['opacity']};
  }
  return Map<String, dynamic>.from(appearance.values);
}

/// Resolve a copied fragment's source context once into ordinary declarations.
/// Later edits use the ordinary resolver and physical placement commands.
VenueLayoutDocument materializeFragmentContext(VenueLayoutDocument document) {
  if (document.schemaVersion != 2) {
    throw const FormatException('canonical_document_required');
  }
  return document.copyWith(
    styles: const {},
    seatingDefaults: const {},
    nodes: [
      for (final node in document.nodes)
        node.copyWith(
          style: materializedNodeStyle(document, node),
          seating: node.kind == 'table' || node.assembly != null
              ? TableSeating.fromDocument(document, node).record
              : node.seating,
        ),
    ],
  );
}

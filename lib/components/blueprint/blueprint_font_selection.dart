import 'package:venue_seat_picker/venue_seat_picker.dart';

/// A font-family choice selects a real face. This changes the authored style in
/// the same edit; renderers never synthesize a missing weight or italic face.
VenueLayoutDocument normalizeBlueprintFontSelection(VenueLayoutDocument before,
    VenueLayoutDocument after, Map<String, dynamic> families,
    {String? nodeId, String? appearanceKind}) {
  Map<String, Object>? correction(Map<String, dynamic> label) {
    final faces = (families[label['fontFamilyId']] as Map?)?['faces'] as Map?;
    if (faces == null || faces.isEmpty) {
      throw LayoutTextDependencyFailure('font_family_unavailable',
          fontFamilyId: label['fontFamilyId'] as String?);
    }
    final current =
        '${label['weight']}:${label['italic'] == true ? 'italic' : 'normal'}';
    if (faces[current] is String) return null;
    final available = faces.keys
        .cast<String>()
        .where((key) =>
            RegExp(r'^(400|700):(normal|italic)$').hasMatch(key) &&
            faces[key] is String)
        .toList();
    if (available.isEmpty)
      throw const LayoutTextDependencyFailure('font_face_unavailable');
    // Keep supported formatting where possible; the chosen combination must
    // always identify a real face in this family.
    int score(String key) {
      final parts = key.split(':');
      final weightChanged = int.parse(parts[0]) != label['weight'];
      final italicChanged = (parts[1] == 'italic') != (label['italic'] == true);
      return (weightChanged ? 3 : 0) + (italicChanged ? 2 : 0);
    }

    available.sort((a, b) {
      final c = score(a).compareTo(score(b));
      return c == 0 ? a.compareTo(b) : c;
    });
    final parts = available.first.split(':');
    return {'weight': int.parse(parts[0]), 'italic': parts[1] == 'italic'};
  }

  var next = after;
  const probeId = '00000000-0000-4000-8000-000000000000';
  final probe = nodeId == null
      ? LayoutNode(
          id: probeId,
          kind:
              appearanceKind == 'document' ? 'text' : appearanceKind ?? 'text')
      : next.nodes.firstWhere((n) => n.id == nodeId);
  final targetDocument =
      nodeId == null && (appearanceKind == null || appearanceKind == 'document')
          ? next.copyWith(styles: {'label': next.styles['label'] ?? {}})
          : next;
  final targetLabel = resolveNodeAppearance(targetDocument, probe).label;
  final targetFamily = targetLabel['fontFamilyId'];
  final initial = correction(targetLabel);
  if (initial != null) {
    for (final entry in initial.entries) {
      next = nodeId != null
          ? setNodeStyleLeaf(next, nodeId, ['label', entry.key],
              value: entry.value)
          : appearanceKind != null && appearanceKind != 'document'
              ? setKindStyleLeaf(next, appearanceKind, ['label', entry.key],
                  value: entry.value)
              : setDocumentLabelLeaf(next, entry.key, value: entry.value);
    }
  }
  if (nodeId == null &&
      (appearanceKind == null || appearanceKind == 'document')) {
    for (final kind
        in ((next.styles['kinds'] as Map?)?.keys ?? const <String>[])
            .cast<String>()) {
      final kindProbe = LayoutNode(id: probeId, kind: kind);
      final old = resolveNodeAppearance(before, kindProbe).label;
      final label = resolveNodeAppearance(next, kindProbe).label;
      if (old['fontFamilyId'] == label['fontFamilyId'] &&
          label['fontFamilyId'] != targetFamily) continue;
      final fix = correction(label);
      if (fix != null)
        for (final entry in fix.entries) {
          next = setKindStyleLeaf(next, kind, ['label', entry.key],
              value: entry.value);
        }
    }
  }
  final previous = {for (final n in before.nodes) n.id: n};
  for (final node in next.nodes) {
    final label = resolveNodeAppearance(next, node).label;
    final old = previous[node.id];
    final oldFamily = old == null
        ? null
        : resolveNodeAppearance(before, old).label['fontFamilyId'];
    final inScope = nodeId != null
        ? node.id == nodeId
        : (appearanceKind == null || appearanceKind == 'document')
            ? label['fontFamilyId'] == targetFamily
            : node.kind == appearanceKind &&
                label['fontFamilyId'] == targetFamily;
    if (oldFamily == label['fontFamilyId'] && !inScope) continue;
    final fix = correction(label);
    if (fix != null)
      for (final entry in fix.entries) {
        next = setNodeStyleLeaf(next, node.id, ['label', entry.key],
            value: entry.value);
      }
  }
  return next;
}

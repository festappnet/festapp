/// Immutable confirmation of exactly the reservation state shown to an editor.
/// The opaque snapshot is never a buyer's reservation secret.
class BlueprintHoldReleasePreview {
  BlueprintHoldReleasePreview({
    required this.organizationId,
    this.unitId,
    required this.occasionId,
    required this.blueprintId,
    required this.layoutRevision,
    required List<int> requestedSpotIds,
    required List<int> affectedSpotIds,
    required this.holdSnapshot,
    required List<({int id, String? title, String state})> seats,
    required this.activeHoldCount,
    required this.canApply,
  })  : requestedSpotIds = List.unmodifiable(requestedSpotIds),
        affectedSpotIds = List.unmodifiable(affectedSpotIds),
        seats = List.unmodifiable(seats);

  final int organizationId, occasionId, blueprintId, layoutRevision;
  final int? unitId;
  final List<int> requestedSpotIds, affectedSpotIds;
  final String holdSnapshot;
  final List<({int id, String? title, String state})> seats;
  final int activeHoldCount;
  final bool canApply;

  factory BlueprintHoldReleasePreview.fromJson(Map<String, dynamic> json,
      {required int organizationId, int? unitId}) {
    final requested = (json['requestedSpotIds'] as List).cast<int>();
    final affected = (json['affectedSpotIds'] as List).cast<int>();
    final seats = (json['seats'] as List)
        .map((raw) => (
              id: raw['spotId'] as int,
              title: raw['title'] as String?,
              state: raw['state'] as String,
            ))
        .toList();
    final snapshot = json['holdSnapshot'] as String;
    final affectedSet = affected.toSet();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(snapshot) ||
        affected.isEmpty ||
        affectedSet.length != affected.length ||
        seats.length != affected.length ||
        seats.map((s) => s.id).toSet().length != affected.length ||
        seats.any((s) => !affectedSet.contains(s.id)) ||
        requested.any((id) => !affectedSet.contains(id))) {
      throw const FormatException('Incomplete reservation confirmation');
    }
    return BlueprintHoldReleasePreview(
      organizationId: organizationId,
      unitId: unitId,
      occasionId: json['occasionId'] as int,
      blueprintId: json['blueprintId'] as int,
      layoutRevision: json['layoutRevision'] as int,
      requestedSpotIds: requested,
      affectedSpotIds: affected,
      holdSnapshot: snapshot,
      seats: seats,
      activeHoldCount: json['activeHoldCount'] as int,
      canApply: json['canApply'] as bool,
    );
  }
}

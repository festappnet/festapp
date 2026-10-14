/// Server-owned capacity snapshot. Never recompute availability in clients.
class FormCapacityModel {
  final Map<String, dynamic> data;
  FormCapacityModel.fromJson(Map<String, dynamic> json)
      : data = Map.unmodifiable(json);
  bool get enabled => data['enabled'] == true;
  int? get limit => (data['limit'] as num?)?.toInt();
  int? get remainingPublic => (data['remainingPublic'] as num?)?.toInt();
  bool get showRemaining => data['showRemaining'] == true;
  int get occupiedPeople => (data['occupiedPeople'] as num?)?.toInt() ?? 0;
  int get offeredPlaces => (data['offeredPlaces'] as num?)?.toInt() ?? 0;

  int get heldForWaiting => (data['heldForWaiting'] as num?)?.toInt() ?? 0;

  /// Active registrations include every waiting item and may exceed the limit.
  int get occupiedPlaces => occupiedPeople + offeredPlaces + waitingPeople;

  /// Only committed admissions and reservations constrain capacity edits.
  int get minimumCapacity => occupiedPeople + offeredPlaces + heldForWaiting;
  int get waitingPeople => (data['waitingPeople'] as num?)?.toInt() ?? 0;
  int get offerablePlaces => (data['offerablePlaces'] as num?)?.toInt() ?? 0;
  int get revision => (data['revision'] as num?)?.toInt() ?? 0;
  bool get canSendOffers => data['canSendOffers'] == true;
  String? get blockedReason => data['blockedReason'] as String?;
}

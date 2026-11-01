// The organizer protocol is owned by seating_transition SQL, not the renderer.
Map<String, dynamic> seatingMap(Object? value) =>
    Map<String, dynamic>.from(value as Map);
List<Map<String, dynamic>> seatingRows(Object? value) =>
    (value as List? ?? const []).map(seatingMap).toList();
int seatingInt(Object? value) => (value as num).toInt();

class SeatingCapabilities {
  SeatingCapabilities(Map<String, dynamic> json)
    : configure = json['configure'] == true,
      readHolders = json['readHolders'] == true,
      assign = json['assign'] == true;
  final bool configure, readHolders, assign;
}

class SeatingAdmission {
  SeatingAdmission(Map<String, dynamic> json)
    : ticketId = seatingInt(json['ticketId']),
      itemId = (json['admissionItemId'] as num?)?.toInt(),
      orderId = seatingInt(json['orderId']),
      formId = seatingInt(json['formId']),
      productId = (json['productId'] as num?)?.toInt(),
      spotId = (json['spotId'] as num?)?.toInt(),
      holder = json['holder'] as String? ?? '',
      ticketSymbol = json['ticketSymbol']?.toString() ?? '${json['ticketId']}',
      orderSymbol = json['orderSymbol']?.toString() ?? '${json['orderId']}',
      productTitle = json['productTitle'] as String? ?? '',
      category = json['category'] as String,
      reason = json['reason'] as String?;
  final int ticketId, orderId, formId;
  final int? itemId, productId;
  final int? spotId;
  final String holder, ticketSymbol, orderSymbol, productTitle, category;
  final String? reason;
  bool get mutable =>
      itemId != null &&
      productId != null &&
      reason == null &&
      (category == 'unassigned' || category == 'assigned');
  String get label =>
      holder.isEmpty ? '#$ticketSymbol' : '$holder · #$ticketSymbol';
}

class SeatingSeat {
  SeatingSeat(Map<String, dynamic> json)
    : id = seatingInt(json['id']),
      productId = (json['productId'] as num?)?.toInt(),
      title = json['title'] as String? ?? '#${json['id']}',
      available = json['available'] == true,
      reason = json['reason'] as String?,
      unitSpotIds = (json['unitSpotIds'] as List? ?? [json['id']])
          .map(seatingInt)
          .toList();
  final int id;
  final int? productId;
  final String title;
  final bool available;
  final String? reason;
  final List<int> unitSpotIds;
}

class SeatingMapping {
  const SeatingMapping({
    required this.ticketId,
    required this.admissionItemId,
    required this.expectedSpotId,
    required this.targetSpotId,
  });
  final int ticketId, admissionItemId;
  final int? expectedSpotId, targetSpotId;
  Map<String, dynamic> toJson() => {
    'ticketId': ticketId,
    'admissionItemId': admissionItemId,
    'expectedSpotId': expectedSpotId,
    'targetSpotId': targetSpotId,
  };
}

class SeatingContext {
  SeatingContext(Map<String, dynamic> json)
    : transitionId = json['transitionId'] as String,
      blueprintId = seatingInt(json['blueprintId']),
      revision = seatingInt(json['revision']),
      state = json['state'] as String,
      capabilities = SeatingCapabilities(seatingMap(json['capabilities'])),
      counts = seatingMap(json['counts'])
          .map((k, v) => MapEntry(k, seatingInt(v))),
      items = seatingRows(json['items']).map(SeatingAdmission.new).toList(),
      seats = seatingRows(json['seats']).map(SeatingSeat.new).toList(),
      compatibility = seatingRows(json['compatibility']),
      cohort = seatingRows(json['cohort']),
      nextCursor = (json['nextCursor'] as num?)?.toInt(),
      publicationAvailable = json['publicationAvailable'] == true;
  final String transitionId, state;
  final int blueprintId, revision;
  final SeatingCapabilities capabilities;
  final Map<String, int> counts;
  final List<SeatingAdmission> items;
  final List<SeatingSeat> seats;
  final List<Map<String, dynamic>> compatibility, cohort;
  final int? nextCursor;
  final bool publicationAvailable;
  bool get allAssigned =>
      (counts['unassigned'] ?? 0) == 0 && (counts['blocked'] ?? 0) == 0;
  int get admitted => [
    'unassigned',
    'assigned',
    'standing',
    'blocked',
  ].fold(0, (n, k) => n + (counts[k] ?? 0));
}

class SeatingPreview {
  SeatingPreview(Map<String, dynamic> json)
    : fingerprint = json['fingerprint'] as String,
      blockers = seatingRows(json['blockers']),
      mappings = seatingRows(json['mappings']),
      forms = seatingRows(json['forms']),
      catalog = seatingRows(json['catalog']),
      transitionIds = (json['transitionIds'] as List? ?? const [])
          .cast<String>();
  final String fingerprint;
  final List<Map<String, dynamic>> blockers, mappings, forms, catalog;
  final List<String> transitionIds;
  bool get ready => blockers.isEmpty;
}

class SeatingRejection implements Exception {
  const SeatingRejection(this.reason, [this.blockers = const []]);
  final String reason;
  final List<Map<String, dynamic>> blockers;
}

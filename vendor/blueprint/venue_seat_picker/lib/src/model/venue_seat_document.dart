import 'venue_backdrop.dart';
import 'venue_seat.dart';

/// Portable versioned JSON document for venue layout authoring.
class VenueSeatDocument {
  const VenueSeatDocument({
    required this.rows,
    required this.columns,
    required this.seats,
    this.backdrop,
    this.schemaVersion = 1,
  });

  final int schemaVersion;
  final int rows;
  final int columns;
  final List<VenueSeat> seats;
  final VenueBackdrop? backdrop;

  factory VenueSeatDocument.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'] as int? ?? 1;
    if (version != 1) {
      throw FormatException('Unsupported venue seat schema version: $version');
    }
    return VenueSeatDocument(
      schemaVersion: version,
      rows: json['rows']! as int,
      columns: json['columns']! as int,
      seats: (json['seats']! as List)
          .cast<Map>()
          .map((value) => VenueSeat.fromJson(value.cast<String, Object?>()))
          .toList(),
      backdrop: switch (json['backdrop']) {
        final String source when source.isNotEmpty => VenueBackdrop.parse(
          source,
        ),
        _ => null,
      },
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'rows': rows,
    'columns': columns,
    'seats': seats.map((seat) => seat.toJson()).toList(),
    if (backdrop != null) 'backdrop': backdrop!.source,
  };
}

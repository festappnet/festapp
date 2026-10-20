import 'seat_adapter.dart';
import 'seat_status.dart';

/// Ready-to-use immutable seat model for applications without a custom model.
class VenueSeat {
  const VenueSeat({
    required this.id,
    required this.position,
    this.status = SeatStatus.available,
    this.label,
    this.groupId,
    this.metadata = const {},
  });

  final Object id;
  final SeatPosition position;
  final SeatStatus status;
  final String? label;
  final Object? groupId;
  final Map<String, Object?> metadata;

  VenueSeat copyWith({SeatPosition? position, SeatStatus? status}) => VenueSeat(
    id: id,
    position: position ?? this.position,
    status: status ?? this.status,
    label: label,
    groupId: groupId,
    metadata: metadata,
  );

  factory VenueSeat.fromJson(Map<String, Object?> json) => VenueSeat(
    id: json['id']!,
    position: SeatPosition(json['row']! as int, json['column']! as int),
    status: SeatStatus.fromWireName(json['status']! as String),
    label: json['label'] as String?,
    groupId: json['group'],
    metadata: (json['metadata'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'row': position.row,
    'column': position.column,
    'status': status.wireName,
    if (label != null) 'label': label,
    if (groupId != null) 'group': groupId,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

/// Adapter for the built-in [VenueSeat] model.
final venueSeatAdapter = SeatAdapter<VenueSeat, Object>(
  idOf: (seat) => seat.id,
  positionOf: (seat) => seat.position,
  statusOf: (seat) => seat.status,
  labelOf: (seat) => seat.label,
  groupOf: (seat) => seat.groupId,
);

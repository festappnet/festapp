class ClientActivityDay {
  const ClientActivityDay({
    required this.day,
    required this.actionCount,
    required this.changedItemCount,
    required this.activeActorCount,
  });

  final DateTime day;
  final int actionCount;
  final int changedItemCount;
  final int activeActorCount;

  factory ClientActivityDay.fromJson(Map<String, dynamic> json) =>
      ClientActivityDay(
        day: DateTime.parse(json['day'] as String),
        actionCount: (json['actionCount'] as num?)?.toInt() ?? 0,
        changedItemCount: (json['changedItemCount'] as num?)?.toInt() ?? 0,
        activeActorCount: (json['activeActorCount'] as num?)?.toInt() ?? 0,
      );
}

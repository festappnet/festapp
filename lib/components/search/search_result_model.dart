/// One result produced by the local search index.
class SearchResultModel {
  final String entityType; // event | place | song | game | info | news
  final int entityId;
  final String? title;
  final String? snippet;
  final double rank;
  final DateTime? startTime;
  final int? parentId; // event.place for events
  final Map<String, dynamic> extra;

  SearchResultModel({
    required this.entityType,
    required this.entityId,
    this.title,
    this.snippet,
    this.rank = 0,
    this.startTime,
    this.parentId,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? const {};
}

import 'package:fstapp/database_tables/tb.dart';

class NewsModel {
  static const String newsOffline = "newsOffline";
  static const String viewsColumn = "views";

  DateTime? createdAt;
  String? message;
  String? createdBy;
  int id;
  int? views;
  bool isRead = false;
  int aggregateVersion;

  NewsModel({
    required this.createdAt,
    required this.message,
    required this.createdBy,
    required this.id,
    required this.views,
    this.aggregateVersion = 0,
  });

  Map toJson() => {
        Tb.news.id: id,
        Tb.news.created_at: createdAt?.toIso8601String(),
        Tb.news.created_by: createdBy,
        viewsColumn: views,
        Tb.news.message: message,
      };

  factory NewsModel.fromJson(Map<String, dynamic> json) {
    return NewsModel(
        id: json[Tb.news.id],
        createdAt: json.containsKey(Tb.news.created_at)
            ? DateTime.parse(json[Tb.news.created_at])
            : null,
        message: json[Tb.news.message],
        createdBy: json[Tb.user_info.name],
        views: (json[NewsModel.viewsColumn] as num?)?.toInt(),
        aggregateVersion: (json['aggregate_version'] as num?)?.toInt() ?? 0);
  }
}

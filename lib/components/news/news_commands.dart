import 'package:fstapp/components/news/news_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_response.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum NewsCommandStatus { applied, unchanged, rejected, conflict }

class NewsCommandResult {
  const NewsCommandResult({
    required this.status,
    required this.version,
    this.news,
  });

  final NewsCommandStatus status;
  final int version;
  final NewsModel? news;
}

abstract interface class NewsCommands {
  Future<NewsCommandResult> create(int occasionId, String message);
  Future<NewsCommandResult> update(int occasionId, NewsModel news);
  Future<NewsCommandResult> delete(int occasionId, NewsModel news);
  Future<NewsCommandResult> publish({
    required int occasionId,
    required bool addToNews,
    required String? newsMessage,
    required bool sendNotification,
    required String? notificationHeading,
    required String? notificationContent,
    required List<String>? recipients,
  });
  Future<void> markRead(int occasionId, int newsId);
}

class SupabaseNewsCommands implements NewsCommands {
  SupabaseNewsCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client);

  SupabaseNewsCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<NewsCommandResult> create(int occasionId, String message) =>
      _save(occasionId, message, null, null);

  @override
  Future<NewsCommandResult> update(int occasionId, NewsModel news) =>
      _save(occasionId, news.message ?? '', news.id, news.aggregateVersion);

  Future<NewsCommandResult> _save(
    int occasionId,
    String message,
    int? id,
    int? expectedVersion,
  ) async {
    final raw = await _transport.invoke('save_news_client_sync_v1', {
      'p_occasion': occasionId,
      'p_expected_version': expectedVersion,
      'p_news': {if (id != null) 'id': id, 'message': message},
    });
    return _decode(raw);
  }

  @override
  Future<NewsCommandResult> delete(int occasionId, NewsModel news) async =>
      _decode(await _transport.invoke('delete_news_client_sync_v1', {
        'p_occasion': occasionId,
        'p_news_id': news.id,
        'p_expected_version': news.aggregateVersion,
      }));

  @override
  Future<NewsCommandResult> publish({
    required int occasionId,
    required bool addToNews,
    required String? newsMessage,
    required bool sendNotification,
    required String? notificationHeading,
    required String? notificationContent,
    required List<String>? recipients,
  }) async =>
      _decode(await _transport.invoke('publish_news_client_sync_v1', {
        'p_occasion': occasionId,
        'p_add_to_news': addToNews,
        'p_news_message': newsMessage,
        'p_send_notification': sendNotification,
        'p_notification_heading': notificationHeading,
        'p_notification_content': notificationContent,
        'p_recipients': recipients,
      }));

  @override
  Future<void> markRead(int occasionId, int newsId) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'mark_news_read_client_sync_v1',
      {'p_occasion': occasionId, 'p_news_id': newsId},
    ));
    if (response.code != 200 ||
        (response.status != 'applied' && response.status != 'unchanged')) {
      throw StateError('News marker mutation failed');
    }
    await response.applyReplacements();
  }

  Future<NewsCommandResult> _decode(Object? raw) async {
    final response = ClientCommandResponse.from(raw);
    await response.applyReplacements();
    final version = (response.data['version'] as num?)?.toInt() ?? 0;
    final entity = response.data['news'];
    return NewsCommandResult(
      status: NewsCommandStatus.values.byName(response.status),
      version: version,
      news: entity is Map
          ? NewsModel.fromJson({
              ...entity.cast<String, dynamic>(),
              'aggregate_version': version,
              'views': entity['views'] ?? 0,
            })
          : null,
    );
  }
}

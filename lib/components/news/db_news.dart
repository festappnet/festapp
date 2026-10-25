import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/news/news_model.dart';
import 'package:fstapp/components/news/news_strings.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection.dart';
import 'package:fstapp/components/news/news_commands.dart';
import 'package:html/parser.dart';
import 'news_submission.dart';

class DbNews {
  static final _supabase = Supabase.instance.client;
  static final NewsCommands _commands = SupabaseNewsCommands(_supabase);
  static Future<void> deleteNewsMessage(NewsModel message) async {
    final result =
        await _commands.delete(RightsService.currentOccasionId()!, message);
    if (result.status == NewsCommandStatus.conflict) {
      throw StateError('News was changed by another editor');
    }
    if (result.status == NewsCommandStatus.rejected) {
      throw StateError('News delete was rejected');
    }
    return;
  }

  static Future<void> updateNewsMessage(NewsModel message,
      {String? originalMessage}) async {
    final result = await _commands.update(
        RightsService.currentOccasionId()!, message,
        originalMessage: null);
    if (result.status == NewsCommandStatus.conflict) {
      throw StateError('News was changed by another editor');
    }
    if (result.status == NewsCommandStatus.rejected || result.news == null) {
      throw StateError('News save was rejected');
    }
    message
      ..message = result.news!.message
      ..aggregateVersion = result.version;
  }

  static Future<void> publishSubmission(
          BuildContext context, NewsSubmission submission) =>
      insertNewsMessage(
          context,
          submission.heading,
          submission.headingDefault,
          submission.content,
          submission.addToNews,
          submission.withNotification,
          submission.recipients);

  static Future<void> insertNewsMessage(
      BuildContext context,
      String? heading,
      String headingDefault,
      String message,
      bool addToNews,
      bool withNotification,
      List<String>? to) async {
    var messageForNews = heading != null
        ? "<strong>${htmlEscape.convert(heading)}</strong><br>$message"
        : message;
    String? basicMessage;
    if (withNotification) {
      var plainText = '';
      var document = parse(message);
      for (var child in document.getElementsByTagName('p')) {
        var innerText = '${child.text}\n';
        if (innerText.trim().isNotEmpty) plainText += innerText;
      }
      basicMessage = plainText.trim();
    }
    final result = await _commands.publish(
      occasionId: RightsService.currentOccasionId()!,
      addToNews: addToNews,
      newsMessage: addToNews ? messageForNews : null,
      sendNotification: withNotification,
      notificationHeading: withNotification ? heading ?? headingDefault : null,
      notificationContent: basicMessage,
      recipients: to,
    );
    if (result.status == NewsCommandStatus.rejected ||
        result.status == NewsCommandStatus.conflict) {
      throw StateError('News publication was rejected');
    }
    if (!context.mounted) return;
    if (withNotification) {
      ToastHelper.Show(
        context,
        addToNews
            ? (to == null
                ? NewsStrings.messageSentToEveryone
                : NewsStrings.messageSentToSelf)
            : NewsStrings.testSentToSelf,
      );
    } else if (addToNews) {
      ToastHelper.Show(context, NewsStrings.messageCreatedWithoutNotification);
    }
    return;
  }

  static Future<int> countNewMessages() async {
    AuthService.ensureUserIsLoggedIn();
    if (ClientSyncRuntime.isV1Selected) {
      return ClientSyncProjection.unreadNewsCount();
    }
    int lastMessageId = await getLastReadMessage();
    var result = await _supabase
        .from(Tb.news.table)
        .select()
        .eq(Tb.news.occasion, RightsService.currentOccasionId()!)
        .gt(Tb.news.id, lastMessageId)
        .count();
    return result.count;
  }

  static Future<int> getLastReadMessage() async {
    AuthService.ensureUserIsLoggedIn();
    int lastMessageId = 0;
    var lastMessage = await _supabase
        .from(Tb.news.table)
        .select("${Tb.news.id},"
            "${Tb.user_news.table}!inner(${Tb.user_news.news_id})")
        .match({
      Tb.news.occasion: RightsService.currentOccasionId()!,
      "${Tb.user_news.table}.${Tb.user_news.user}": AuthService.currentUserId()
    }).maybeSingle();
    if (lastMessage != null) {
      lastMessageId = lastMessage[Tb.news.id];
    }
    return lastMessageId;
  }

  static Future<void> setMessagesAsRead(int newId) async {
    AuthService.ensureUserIsLoggedIn();
    await _commands.markRead(RightsService.currentOccasionId()!, newId);
    return;
  }

  static Future<void> setLatestMessageAsRead() async {
    AuthService.ensureUserIsLoggedIn();
    final latestMessage = await _supabase
        .from(Tb.news.table)
        .select(Tb.news.id)
        .eq(Tb.news.occasion, RightsService.currentOccasionId()!)
        .order(Tb.news.id, ascending: false)
        .limit(1)
        .maybeSingle();
    if (latestMessage == null) return;
    final latestId = (latestMessage[Tb.news.id] as num).toInt();
    if (await getLastReadMessage() < latestId) {
      await setMessagesAsRead(latestId);
    }
  }

  static Future<List<NewsModel>> getAllNewsMessages() async {
    int lastReadMessageId = 0;
    if (AuthService.isLoggedIn()) {
      lastReadMessageId = await getLastReadMessage();
    }
    var data = await _supabase.rpc("get_news_with_versions_v1",
        params: {'p_occasion': RightsService.currentOccasionId()!});

    List<NewsModel> loadedMessages =
        List<NewsModel>.from(data.map((x) => NewsModel.fromJson(x)));

    int viewsAggregate = 0;
    for (var message in loadedMessages) {
      viewsAggregate += message.views ?? 0;
      message.views = viewsAggregate;
      if (AuthService.isLoggedIn()) {
        message.isRead = lastReadMessageId >= message.id;
      }
    }

    return loadedMessages;
  }
}

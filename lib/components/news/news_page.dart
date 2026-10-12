import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/news/news_model.dart';
import 'package:fstapp/components/_shared/async_reload_coordinator.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/components/news/db_news.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/news/news_strings.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/widgets/pop_button.dart';
import 'package:fstapp/components/images/zoomable_image/zoomable_image.dart';
import '../html/rich_html_editor_controller.dart';
import '../html/editable_html_field.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import '../occasion/occasion_home_page.dart';

@RoutePage()
class NewsPage extends StatefulWidget {
  static const ROUTE = "news";
  final VoidCallback? onSetAsRead;

  NewsPage({super.key, this.onSetAsRead});

  @override
  _NewsPageState createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  final _htmlSave = HtmlSaveCoordinator();
  List<NewsModel> newsMessages = [];
  final AsyncReloadCoordinator _refreshCoordinator = AsyncReloadCoordinator();

  // The tabs router this page is subscribed to, plus the last active index we
  // saw. Kept as fields so the listener can be removed in dispose() — otherwise
  // every time this page is recreated (tab switches, navigatePath re-resolves
  // the hierarchy) another listener leaks, and each one reloads news on *every*
  // tab notification, snowballing into a flood of `news` requests.
  TabsRouter? _tabsRouter;
  int _lastActiveIndex = -1;

  @override
  void initState() {
    super.initState();
    ClientSyncRuntime.projectionEpoch.addListener(_onProjectionChanged);
    loadData();
  }

  void _onProjectionChanged() {
    if (ClientSyncRuntime.isV1Selected) unawaited(loadData());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabsRouter = context.tabsRouter;
    if (!identical(_tabsRouter, tabsRouter)) {
      _tabsRouter?.removeListener(_onTabChanged);
      _tabsRouter = tabsRouter;
      _lastActiveIndex = tabsRouter.activeIndex;
      tabsRouter.addListener(_onTabChanged);
    }
  }

  /// Reload only when the News tab *becomes* active (a real transition), not on
  /// every tabs-router notification — the latter refetched on each rebuild.
  void _onTabChanged() {
    final router = _tabsRouter;
    if (router == null) return;
    final newsIndex = OccasionHomePage.baseTabKeys.indexOf(OccasionTab.news);
    final active = router.activeIndex;
    if (active == newsIndex && _lastActiveIndex != newsIndex) {
      unawaited(loadData());
    }
    _lastActiveIndex = active;
  }

  @override
  void dispose() {
    _htmlSave.dispose();
    _refreshCoordinator.dispose();
    ClientSyncRuntime.projectionEpoch.removeListener(_onProjectionChanged);
    _tabsRouter?.removeListener(_onTabChanged);
    super.dispose();
  }

  void _showMessageDialog(BuildContext context) {
    context.router.root.push<bool>(NewsFormRoute(onSubmit: (submission) =>
      DbNews.publishSubmission(context, submission))).then((saved) async {
        if (saved == true && mounted) await loadData();
      });
  }

  Future<void> loadNewsMessages() async {
    var loadedMessages = await DbNews.getAllNewsMessages();
    if (!mounted) return;
    setState(() {
      newsMessages = loadedMessages;
    });
  }

  Future<void> loadOfflineData() async {
    var loadedMessages = await OfflineDataService.getAllMessages();
    if (!mounted) return;
    setState(() {
      newsMessages = loadedMessages;
    });
  }

  Future<void> loadData() => _refreshCoordinator.run(() async {
        // If the live projection changes during this load, the coordinator
        // queues one more pass instead of losing the newer view counts.
        await loadOfflineData();
        if (!mounted) return;
        if (!ClientSyncRuntime.isV1Selected) {
          await loadNewsMessages();
          if (!mounted) return;
          await OfflineDataService.saveAllMessages(newsMessages);
        }
        widget.onSetAsRead?.call();
      });

  @override
  Widget build(BuildContext context) => HtmlEditingScope(coordinator: _htmlSave, child: _buildHtmlParent(context));

  Widget _buildHtmlParent(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConfig.newsPageColor(context),
      appBar: AppBar(
        title: Text(NewsStrings.news,
            style: TextStyle(color: ThemeConfig.appBarColorNegative())),
        leading: PopButton(),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
          child: newsMessages.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.article_outlined,
                        size: 64,
                        color: Theme.of(context).disabledColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        NewsStrings.noMessagesYet,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : PinchScrollView(
                  builder: (onPinchStart, onPinchEnd) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      for (var i = 0; i < newsMessages.length; i++) ...[
                        if (i != 0) const Divider(),
                        Builder(builder: (context) {
                          final message = newsMessages[i];
                          final htmlVersion = message.aggregateVersion;
                          final htmlOriginal = message.message;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        message.createdBy ?? "",
                                        style: message.isRead
                                            ? readTextStyle()
                                            : unReadTextStyle(),
                                      ),
                                    ),
                                    // How long ago the message was sent, as a
                                    // humanized "… ago" (shared with the offline
                                    // banner).
                                    if (message.createdAt != null)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: Text(
                                          TimeHelper.timeAgo(message.createdAt!,
                                              context.locale.languageCode),
                                          style: TextStyle(
                                            color: ThemeConfig.grey600(context),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 12),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                        StylesConfig.newsItemRoundness),
                                    color:
                                        Theme.of(context).colorScheme.surface,
                                  ),
                                  child: Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: EditableHtmlField(
                                          key: ValueKey('news-html-${message.id}'),
                                          html: message.message,
                                          enabled: RightsService.isEditor(),
                                          owner: HtmlMediaOwner.occasion(RightsService.currentOccasionId()),
                                          onChanged: (_) {},
                                          onSave: (html) async {
                                            final snapshot = NewsModel(id: message.id,
                                              message: html, createdAt: message.createdAt,
                                              createdBy: message.createdBy, views: message.views,
                                              aggregateVersion: htmlVersion);
                                            await DbNews.updateNewsMessage(snapshot,
                                                originalMessage: htmlOriginal);
                                            if (mounted) await loadData();
                                          },
                                        ),
                                      ),
                                      if (AuthService.isLoggedIn() &&
                                          message.views != null)
                                        Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              Icon(Icons.remove_red_eye,
                                                  size: 16,
                                                  color: Theme.of(context)
                                                      .disabledColor),
                                              const SizedBox(width: 6),
                                              Text(
                                                message.views!.toString(),
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .disabledColor,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (RightsService.isEditor())
                                PopupMenuButton<ContextMenuChoice>(
                                  onSelected: (choice) async {
                                    await DbNews.deleteNewsMessage(message);
                                    if (mounted) await loadData();
                                  },
                                  icon: const Icon(Icons.more_horiz),
                                  itemBuilder: (BuildContext context) =>
                                      <PopupMenuEntry<ContextMenuChoice>>[
                                    PopupMenuItem<ContextMenuChoice>(
                                      value: ContextMenuChoice.delete,
                                      child: Text(CommonStrings.delete),
                                    )
                                  ],
                                ),
                            ],
                          );
                        }),
                      ],
                    ],
                  ),
                ),
        ),
      ),
      floatingActionButton: Visibility(
        visible: RightsService.isEditor(),
        child: FloatingActionButton(
          onPressed: () => _showMessageDialog(context),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  TextStyle unReadTextStyle() => TextStyle(fontWeight: FontWeight.bold);
  TextStyle readTextStyle() => TextStyle(
      fontWeight: FontWeight.bold, color: Theme.of(context).hintColor);
}

enum ContextMenuChoice { delete, edit }

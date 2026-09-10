import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/news/news_model.dart';
import 'package:fstapp/components/_shared/async_reload_coordinator.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/components/news/db_news.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/news/news_form_page.dart';
import 'package:fstapp/components/news/news_strings.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/widgets/pop_button.dart';
import 'package:fstapp/components/images/zoomable_image/zoomable_image.dart';
import '../html/html_editor_page.dart';
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
    _refreshCoordinator.dispose();
    ClientSyncRuntime.projectionEpoch.removeListener(_onProjectionChanged);
    _tabsRouter?.removeListener(_onTabChanged);
    super.dispose();
  }

  void _showMessageDialog(BuildContext context) {
    context.router.root
        .pushPath(RouterService.getCurrentLink() + NewsFormPage.ROUTE)
        .then((value) async {
      if (value != null) {
        var data = value as Map<String, dynamic>;
        bool addToNews = data["add_to_news"] ?? true;
        bool withNotification = data["with_notification"]!;
        List<String>? to = data["to"];
        String message = data["content"]!;
        var heading = data["heading"];
        String headingDefault = data["heading_default"]!;

        await DbNews.insertNewsMessage(context, heading, headingDefault,
            message, addToNews, withNotification, to);

        if (addToNews) {
          await loadData();
        }
      }
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
  Widget build(BuildContext context) {
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
                                        child: HtmlView(
                                          html: message.message!,
                                          isSelectable: true,
                                          twoFingersOn: onPinchStart,
                                          twoFingersOff: onPinchEnd,
                                        ),
                                      ),
                                      Visibility(
                                        visible: AuthService.isLoggedIn() &&
                                            message.views != null,
                                        child: Padding(
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
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (RightsService.isEditor())
                                PopupMenuButton<ContextMenuChoice>(
                                  onSelected: (choice) async {
                                    if (choice == ContextMenuChoice.delete) {
                                      await DbNews.deleteNewsMessage(message);
                                      ToastHelper.Show(
                                          context, NewsStrings.messageRemoved);
                                    } else {
                                      await RouterService.navigatePageInfo(
                                        context,
                                        HtmlEditorRoute(
                                          content: {
                                            HtmlEditorPage.parContent:
                                                message.message
                                          },
                                          occasionId:
                                              RightsService.currentOccasionId(),
                                        ),
                                      ).then((value) async {
                                        if (value != null) {
                                          var newMessage = value as String;
                                          message.message = newMessage;
                                          await DbNews.updateNewsMessage(
                                              message);
                                          ToastHelper.Show(context,
                                              NewsStrings.messageChanged);
                                        }
                                      });
                                    }
                                    await loadData();
                                  },
                                  icon: const Icon(Icons.more_horiz),
                                  itemBuilder: (BuildContext context) =>
                                      <PopupMenuEntry<ContextMenuChoice>>[
                                    PopupMenuItem<ContextMenuChoice>(
                                      value: ContextMenuChoice.edit,
                                      child: Text(CommonStrings.edit),
                                    ),
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

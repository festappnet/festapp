import 'package:fstapp/components/email_delivery/email_delivery_strings.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'notification_center_controller.dart';
import 'notification_center_strings.dart';
import 'notification_center_time.dart';

class NotificationCenterPanel extends StatefulWidget {
  const NotificationCenterPanel(
      {super.key,
      required this.controller,
      required this.onDetail,
      this.anchor});
  final NotificationCenterController controller;
  final ValueChanged<NotificationItem> onDetail;
  final Rect? anchor;
  @override
  State<NotificationCenterPanel> createState() =>
      _NotificationCenterPanelState();
}

class _NotificationCenterPanelState extends State<NotificationCenterPanel> {
  bool settings = false;
  String s(String key) => NotificationCenterStrings.text(key);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final body = Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: IconTheme(
                    data: IconThemeData(
                        color: Theme.of(context).colorScheme.onSurface),
                    child: IconButtonTheme(
                        data: IconButtonThemeData(
                            style: IconButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).colorScheme.onSurface)),
                        child: AppDialogHeader(
                          title: Text(NotificationCenterStrings.title),
                          actions: [
                            IconButton(
                                tooltip: s(settings ? 'back' : 'settings'),
                                onPressed: () =>
                                    setState(() => settings = !settings),
                                icon: Icon(
                                    settings ? Icons.arrow_back : Icons.tune))
                          ],
                        )))),
            const Divider(height: 1),
            if (c.loading) const LinearProgressIndicator(),
            Flexible(
                child: settings
                    ? ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(16),
                        children: [
                            Text(s('muteHelp')),
                            const SizedBox(height: 16),
                            for (final occasion in c.occasions)
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title:
                                    Text(occasion['title']?.toString() ?? ''),
                                subtitle: Text(s('muted')),
                                value: occasion['muted'] == true,
                                onChanged: occasion['saving'] == true
                                    ? null
                                    : (value) async {
                                        final success =
                                            await c.mute(occasion, value);
                                        if (!success && context.mounted)
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content:
                                                      Text(s('saveFailed'))));
                                      },
                              ),
                          ])
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(16),
                        children: [
                            if (c.unread)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: OutlinedButton.icon(
                                      onPressed: c.loading ? null : c.open,
                                      icon: const Icon(Icons.refresh),
                                      label: Text(s('newItems')))),
                            if (c.refreshFailed)
                              Row(children: [
                                Expanded(child: Text(s('refreshFailed'))),
                                TextButton(
                                    onPressed: c.refresh,
                                    child: Text(CommonStrings.retry))
                              ]),
                            if (c.failed)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(s(c.groups.isEmpty
                                            ? 'loadFailed'
                                            : 'refreshFailed')),
                                        TextButton(
                                            onPressed:
                                                c.loading ? null : c.open,
                                            child: Text(CommonStrings.retry))
                                      ])),
                            if (c.groups.isEmpty && !c.loading && !c.failed)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 32),
                                  child: Column(children: [
                                    Icon(Icons.notifications_none,
                                        size: 32,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant),
                                    const SizedBox(height: 16),
                                    Text(s('empty'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                        textAlign: TextAlign.center),
                                    const SizedBox(height: 8),
                                    Text(s('emptyHelp'),
                                        textAlign: TextAlign.center)
                                  ])),
                            for (final section
                                in c.groups.map((g) => g.section).toSet()) ...[
                              Padding(
                                  padding:
                                      const EdgeInsets.only(top: 16, bottom: 8),
                                  child: Text(s('section$section'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall)),
                              for (final group in c.groups
                                  .where((g) => g.section == section))
                                _group(context, group),
                            ],
                            if (c.pageFailed) Text(s('refreshFailed')),
                            if (c.nextCursor != null)
                              TextButton(
                                  onPressed: c.loading ? null : c.loadMore,
                                  child: Text(s('more'))),
                          ])),
          ]);
          final size = MediaQuery.sizeOf(context);
          final desktop = size.width >= 720;
          return AppDialog(
              alignment: desktop ? Alignment.topRight : Alignment.center,
              insetPadding: desktop
                  ? EdgeInsets.fromLTRB(
                      16,
                      ((widget.anchor?.bottom ?? 8) + 8)
                          .clamp(
                              16.0, size.height > 112 ? size.height - 96 : 16.0)
                          .toDouble(),
                      (size.width - (widget.anchor?.right ?? size.width))
                          .clamp(16.0, size.width - 16)
                          .toDouble(),
                      16)
                  : const EdgeInsets.all(16),
              child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .85),
                  child: SizedBox(width: 440, child: body)));
        },
      );
  bool _hasDetail(NotificationItem item) =>
      item.data['messageId'] is String ||
      (item.occasionLink != null && item.data['orderId'] is int) ||
      (item.data['bankAccountId'] is int && item.data['unitId'] is int);
  bool _isError(NotificationItem item) =>
      const {'email_problem', 'bank_problem'}.contains(item.kind) &&
      item.status != 'recovered';

  Widget _group(BuildContext context, NotificationGroup group) {
    final c = widget.controller;
    final colors = Theme.of(context).colorScheme;
    final hasError =
        const {'email_problem', 'bank_problem'}.contains(group.kind) &&
            (group.items.isEmpty || group.items.any(_isError));
    final grouped = const {
          'order_created',
          'order_cancelled',
          'waitlist_registered'
        }.contains(group.kind) ||
        (group.kind == 'email_problem' && group.count > 1);
    final occasion =
        c.occasions.where((item) => item['id'] == group.occasionId).firstOrNull;
    return Padding(
      padding:
          hasError ? const EdgeInsets.symmetric(vertical: 8) : EdgeInsets.zero,
      child: Material(
        color: hasError ? colors.errorContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: hasError ? const EdgeInsets.all(12) : EdgeInsets.zero,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(
                expanded: grouped ? group.expanded : null,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: hasError
                      ? Icon(Icons.error_outline, color: colors.error)
                      : null,
                  textColor: hasError ? colors.onErrorContainer : null,
                  iconColor: hasError ? colors.onErrorContainer : null,
                  titleTextStyle: hasError
                      ? Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colors.onErrorContainer,
                          fontWeight: FontWeight.bold)
                      : null,
                  title: Text(NotificationCenterStrings.kind(group.kind)),
                  subtitle: Text([
                    group.occasionTitle,
                    if (group.day != null)
                      NotificationCenterTime.day(DateTime.parse(group.day!),
                          context.locale.toLanguageTag())
                  ].whereType<String>().join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (grouped) ...[
                      Text('${group.count}'),
                      Icon(group.expanded
                          ? Icons.expand_less
                          : Icons.expand_more)
                    ],
                    if (occasion != null)
                      PopupMenuButton<bool>(
                          tooltip: CommonStrings.moreOptions,
                          onSelected: (value) async {
                            if (!await c.mute(occasion, value) &&
                                context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(s('saveFailed'))));
                          },
                          itemBuilder: (_) => [
                                CheckedPopupMenuItem(
                                    value: occasion['muted'] != true,
                                    checked: occasion['muted'] == true,
                                    child: Text(s('muted')))
                              ]),
                  ]),
                  onTap: grouped ? () => c.expand(group) : null,
                )),
            if (!grouped || group.expanded) ...[
              for (final item in group.items)
                ListTile(
                  contentPadding: const EdgeInsets.only(left: 12),
                  textColor: _isError(item) ? colors.onErrorContainer : null,
                  titleTextStyle: _isError(item)
                      ? Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colors.onErrorContainer,
                          fontWeight: FontWeight.w600)
                      : null,
                  title: Text([
                    (item.kind == 'email_problem'
                            ? item.data['recipient']
                            : null) ??
                        item.data['orderSymbol'] ??
                        item.data['title'] ??
                        NotificationCenterStrings.kind(item.kind),
                    item.data['customerName']
                  ]
                      .where((e) => e != null && e.toString().isNotEmpty)
                      .join(' - ')),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text([
                        if (item.data['messageKind'] is String)
                          EmailDeliveryStrings.kind(item.data['messageKind']),
                        if (item.data['reason'] is String &&
                            (item.data['reason'] as String).isNotEmpty)
                          NotificationCenterStrings.reason(item.data['reason']),
                        if (item.data['count'] is int)
                          NotificationCenterStrings.places(item.data['count']),
                        if (item.data['remainingPublic'] is int &&
                            item.data['limit'] is int)
                          NotificationCenterStrings.capacity(
                              item.data['remainingPublic'], item.data['limit']),
                        if (item.data['heldForWaiting'] is int &&
                            item.data['heldForWaiting'] > 0)
                          NotificationCenterStrings.held(
                              item.data['heldForWaiting']),
                        if ((item.data['state'] ?? item.status)
                            .toString()
                            .isNotEmpty)
                          NotificationCenterStrings.status(
                              (item.data['state'] ?? item.status).toString())
                      ].join('\n')),
                      if (item.occurredAt != null)
                        Tooltip(
                          message: NotificationCenterTime.exact(
                              item.occurredAt!, context.locale.toLanguageTag()),
                          child: Text(NotificationCenterTime.timestamp(
                              item.occurredAt!,
                              context.locale.toLanguageTag())),
                        ),
                    ],
                  ),
                  trailing: !_hasDetail(item)
                      ? null
                      : ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: TextButton(
                            style: _isError(item)
                                ? TextButton.styleFrom(
                                    foregroundColor: colors.onErrorContainer,
                                    side: BorderSide(
                                        color: colors.onErrorContainer))
                                : null,
                            onPressed: () => widget.onDetail(item),
                            child: Text(s('detail'),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          )),
                ),
              for (final item in group.items)
                if (item.data['affectedOccasions'] is List &&
                    item.data['bankAccountId'] == null)
                  for (final occasion in item.data['affectedOccasions'] as List)
                    ListTile(
                        title: Text(occasion['title']?.toString() ?? ''),
                        trailing: TextButton(
                            onPressed: () =>
                                widget.onDetail(NotificationItem.fromJson({
                                  'id': item.id,
                                  'kind': item.kind,
                                  'occasionLink': occasion['link'],
                                  'data': {'relatedOrders': true}
                                })),
                            child: Text(s('detail')))),
              if (group.busy) const LinearProgressIndicator(),
              if (group.failed)
                TextButton(
                    onPressed: () => c.expand(group, more: true),
                    child: Text(CommonStrings.retry)),
              if (!group.busy &&
                  (group.cursor != null || group.items.length < group.count))
                TextButton(
                    onPressed: () => c.expand(group, more: true),
                    child: Text(s('more'))),
            ],
            if (!hasError) const Divider(height: 1),
          ]),
        ),
      ),
    );
  }
}

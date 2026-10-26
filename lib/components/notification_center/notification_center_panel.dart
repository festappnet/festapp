import 'package:material_ui/material_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

import 'notification_center_controller.dart';
import 'notification_center_strings.dart';
import 'notification_center_time.dart';
import 'notification_item_presenter.dart';

class NotificationCenterPanel extends StatefulWidget {
  const NotificationCenterPanel({
    super.key,
    required this.controller,
    required this.onDetail,
    this.anchor,
  });
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
      final body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: IconTheme(
              data: IconThemeData(
                color: Theme.of(context).colorScheme.onSurface,
              ),
              child: IconButtonTheme(
                data: IconButtonThemeData(
                  style: IconButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                child: AppDialogHeader(
                  title: Text(NotificationCenterStrings.title),
                  actions: [
                    IconButton(
                      tooltip: s(settings ? 'back' : 'settings'),
                      onPressed: () => setState(() => settings = !settings),
                      icon: Icon(settings ? Icons.arrow_back : Icons.tune),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
                          title: Text(occasion['title']?.toString() ?? ''),
                          subtitle: Text(s('muted')),
                          value: occasion['muted'] == true,
                          onChanged: occasion['saving'] == true
                              ? null
                              : (value) async {
                                  final success = await c.mute(occasion, value);
                                  if (!success && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(s('saveFailed'))),
                                    );
                                  }
                                },
                        ),
                    ],
                  )
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
                            label: Text(s('newItems')),
                          ),
                        ),
                      if (c.refreshFailed)
                        Row(
                          children: [
                            Expanded(child: Text(s('refreshFailed'))),
                            TextButton(
                              onPressed: c.refresh,
                              child: Text(CommonStrings.retry),
                            ),
                          ],
                        ),
                      if (c.failed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s(
                                  c.items.isEmpty
                                      ? 'loadFailed'
                                      : 'refreshFailed',
                                ),
                              ),
                              TextButton(
                                onPressed: c.loading ? null : c.open,
                                child: Text(CommonStrings.retry),
                              ),
                            ],
                          ),
                        ),
                      if (c.items.isEmpty && !c.loading && !c.failed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.notifications_none,
                                size: 32,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                s('empty'),
                                style: Theme.of(context).textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(s('emptyHelp'), textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      for (final section
                          in c.items.map((g) => g.section).toSet()) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Text(
                            s('section$section'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        ..._section(
                          context,
                          c.items.where((g) => g.section == section),
                        ),
                      ],
                      if (c.pageFailed) Text(s('refreshFailed')),
                      if (c.nextCursor != null)
                        TextButton(
                          onPressed: c.loading ? null : c.loadMore,
                          child: Text(s('more')),
                        ),
                    ],
                  ),
          ),
        ],
      );
      final size = MediaQuery.sizeOf(context);
      final desktop = size.width >= 720;
      return AppDialog(
        alignment: desktop ? Alignment.topRight : Alignment.center,
        insetPadding: desktop
            ? EdgeInsets.fromLTRB(
                16,
                ((widget.anchor?.bottom ?? 8) + 8)
                    .clamp(16.0, size.height > 112 ? size.height - 96 : 16.0)
                    .toDouble(),
                (size.width - (widget.anchor?.right ?? size.width))
                    .clamp(16.0, size.width - 16)
                    .toDouble(),
                16,
              )
            : const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: SizedBox(width: 440, child: body),
        ),
      );
    },
  );
  Iterable<Widget> _section(
    BuildContext context,
    Iterable<NotificationItem> items,
  ) sync* {
    final byOccasion = <Object, List<NotificationItem>>{};
    for (final item in items) {
      (byOccasion[item.occasionId ?? item.id] ??= []).add(item);
    }
    for (final entry in byOccasion.entries) {
      final first = entry.value.first;
      final occasion = widget.controller.occasions
          .where((item) => item['id'] == first.occasionId)
          .firstOrNull;
      final title = first.occasionTitle ?? occasion?['title']?.toString();
      yield Column(
        key: ValueKey('notification-occasion-${first.section}-${entry.key}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (first.occasionId != null && title != null)
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (occasion != null) _muteMenu(context, occasion),
                ],
              ),
            ),
          for (final item in entry.value) _item(context, item),
        ],
      );
    }
  }

  Widget _muteMenu(BuildContext context, Map<String, dynamic> occasion) =>
      PopupMenuButton<bool>(
        tooltip: CommonStrings.moreOptions,
        iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
        onSelected: (value) async {
          if (!await widget.controller.mute(occasion, value) &&
              context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(s('saveFailed'))));
          }
        },
        itemBuilder: (_) => [
          CheckedPopupMenuItem(
            value: occasion['muted'] != true,
            checked: occasion['muted'] == true,
            child: Text(s('muted')),
          ),
        ],
      );

  Widget _item(BuildContext context, NotificationItem item) {
    final presentation = NotificationItemPresenter(item);
    final colors = Theme.of(context).colorScheme;
    final error = presentation.isError;
    final locale =
        (EasyLocalization.of(context)?.locale ??
                Localizations.localeOf(context))
            .toLanguageTag();
    return Material(
      key: ValueKey('notification-item-${item.id}'),
      color: error ? colors.errorContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: error ? 12 : 0,
              vertical: 8,
            ),
            textColor: error ? colors.onErrorContainer : null,
            iconColor: error ? colors.onErrorContainer : null,
            leading: error ? const Icon(Icons.error_outline) : null,
            title: Text(presentation.title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final detail in presentation.details) Text(detail),
                if (item.occurredAt != null)
                  Tooltip(
                    message: NotificationCenterTime.exact(
                      item.occurredAt!,
                      locale,
                    ),
                    child: Text(
                      NotificationCenterTime.timestamp(
                        item.occurredAt!,
                        locale,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: presentation.hasDetail
                ? const Icon(Icons.chevron_right)
                : null,
            onTap: presentation.hasDetail ? () => widget.onDetail(item) : null,
          ),
          if (item.data['affectedOccasions'] is List &&
              item.data['bankAccountId'] == null)
            for (final occasion in item.data['affectedOccasions'] as List)
              ListTile(
                title: Text(occasion['title']?.toString() ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onDetail(
                  NotificationItem.fromJson({
                    'id': item.id,
                    'kind': item.kind,
                    'occasionLink': occasion['link'],
                    'data': {'relatedOrders': true},
                  }),
                ),
              ),
          if (!error) const Divider(height: 1),
        ],
      ),
    );
  }
}

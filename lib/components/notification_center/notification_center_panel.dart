import 'package:fstapp/components/notification_center/notification_center_time.dart';
import 'package:fstapp/components/email_delivery/email_delivery_strings.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/notification_center/notification_center_controller.dart';
import 'package:fstapp/components/notification_center/notification_center_strings.dart';

class NotificationCenterPanel extends StatefulWidget {
  const NotificationCenterPanel(
      {super.key, required this.controller, required this.onDetail});
  final NotificationCenterController controller;
  final ValueChanged<NotificationItem> onDetail;
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
            _header(context),
            const Divider(height: 1),
            if (c.loading) const LinearProgressIndicator(),
            Flexible(
                child: settings
                    ? _settings(context)
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(16),
                        children: [
                            if (c.unread)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: FilledButton.tonalIcon(
                                      onPressed: c.loading ? null : c.open,
                                      icon: const Icon(Icons.refresh),
                                      label: Text(s('newItems')))),
                            if (c.refreshFailed || c.failed)
                              _retry(
                                  context,
                                  s(c.failed && c.groups.isEmpty
                                      ? 'loadFailed'
                                      : 'refreshFailed'),
                                  c.loading
                                      ? null
                                      : c.failed
                                          ? c.open
                                          : c.refresh),
                            if (c.groups.isEmpty && c.loading)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 32),
                                  child: Semantics(
                                      liveRegion: true,
                                      child: Text(CommonStrings.loading,
                                          textAlign: TextAlign.center))),
                            if (c.groups.isEmpty && !c.loading && !c.failed)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 32),
                                  child: Column(children: [
                                    Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                            shape: BoxShape.circle),
                                        child: Icon(Icons.notifications_none,
                                            size: 28,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant)),
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
                                  child: Row(children: [
                                    Flexible(
                                        child: Semantics(
                                            header: true,
                                            child: Text(s('section$section'),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelLarge
                                                    ?.copyWith(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant)))),
                                    if (MediaQuery.textScalerOf(context)
                                            .scale(1) <=
                                        1.3) ...[
                                      const SizedBox(width: 12),
                                      const Expanded(child: Divider()),
                                    ],
                                  ])),
                              for (final group in c.groups
                                  .where((g) => g.section == section))
                                _group(context, group),
                            ],
                            if (c.pageFailed)
                              _retry(context, s('refreshFailed'),
                                  c.loading ? null : c.loadMore),
                            if (c.nextCursor != null && !c.pageFailed)
                              TextButton(
                                  onPressed: c.loading ? null : c.loadMore,
                                  child: Text(s('more'))),
                          ])),
          ]);
          return AppDialog(
              alignment: MediaQuery.sizeOf(context).width < 720
                  ? Alignment.center
                  : Alignment.centerRight,
              insetPadding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .85),
                  child: SizedBox(width: 440, child: body)));
        },
      );
  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final title = Text(
        settings ? s('settings') : NotificationCenterStrings.title,
        textAlign: TextAlign.start,
        style:
            theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600));
    final actions = [
      IconButton(
          tooltip: s(settings ? 'back' : 'settings'),
          onPressed: () => setState(() => settings = !settings),
          icon: Icon(settings ? Icons.arrow_back : Icons.tune))
    ];
    return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 12),
        child: IconButtonTheme(
            data: IconButtonThemeData(
                style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurface,
                    minimumSize: const Size(48, 48))),
            child: LayoutBuilder(builder: (context, constraints) {
              final stacked = constraints.maxWidth /
                      MediaQuery.textScalerOf(context).scale(1) <
                  250;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppDialogHeader(
                        title: stacked ? null : title, actions: actions),
                    if (stacked)
                      Padding(
                          padding: const EdgeInsets.only(right: 12, bottom: 4),
                          child: title),
                  ]);
            })));
  }

  Widget _settings(BuildContext context) {
    final c = widget.controller;
    final colors = Theme.of(context).colorScheme;
    return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          Text(s('muteHelp'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.5)),
          const SizedBox(height: 20),
          if (c.occasions.isEmpty) Text(s('settingsEmpty')),
          for (final occasion in c.occasions) ...[
            SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(occasion['title']?.toString() ?? ''),
                subtitle: Text(s('muted')),
                value: occasion['muted'] == true,
                onChanged: occasion['saving'] == true
                    ? null
                    : (value) async {
                        if (!await c.mute(occasion, value) && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s('saveFailed'))));
                        }
                      }),
            if (occasion['saving'] == true) const LinearProgressIndicator(),
            const Divider(height: 24),
          ],
        ]);
  }

  Widget _retry(BuildContext context, String message, VoidCallback? retry) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Semantics(
            liveRegion: true,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8)),
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(message,
                              style: Theme.of(context).textTheme.bodyMedium),
                          TextButton.icon(
                              onPressed: retry,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: Text(CommonStrings.retry)),
                        ])))));
  }

  Widget _groupHeader(BuildContext context, NotificationGroup group,
      Map<String, dynamic>? occasion, bool grouped, bool hasError) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final problem =
        const {'email_problem', 'bank_problem'}.contains(group.kind);
    final title = problem
        ? s('groups.${group.kind}')
        : NotificationCenterStrings.kind(group.kind);
    final metadata = [
      group.occasionTitle,
      if (group.day != null)
        NotificationCenterTime.day(DateTime.parse(group.day!), context.locale.toLanguageTag())
    ].whereType<String>().join(' · ');
    final heading =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: colors.onSurface, fontWeight: FontWeight.w600)),
      if (metadata.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(metadata,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant)),
      ],
    ]);
    final menu = occasion == null
        ? null
        : PopupMenuButton<bool>(
            tooltip: CommonStrings.moreOptions,
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
                      child: Text(s('muted')))
                ]);
    final count = grouped
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: hasError
                    ? colors.errorContainer
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6)),
            child: Text('${group.count}',
                style: theme.textTheme.labelMedium?.copyWith(
                    color: hasError
                        ? colors.onErrorContainer
                        : colors.onSurfaceVariant)))
        : null;
    return LayoutBuilder(builder: (context, constraints) {
      final stacked =
          constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
              240;
      final controls = Row(mainAxisSize: MainAxisSize.min, children: [
        if (count != null) count,
        if (grouped)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                  group.expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20)),
      ]);
      if (stacked) {
        return Semantics(
            expanded: grouped ? group.expanded : null,
            button: grouped,
            child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: grouped ? () => widget.controller.expand(group) : null,
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          heading,
                          if (grouped || problem || menu != null)
                            Row(children: [
                              if (problem) ...[
                                Icon(
                                    group.kind == 'email_problem'
                                        ? Icons.mark_email_unread_outlined
                                        : Icons.account_balance_outlined,
                                    size: 20,
                                    color: hasError
                                        ? colors.error
                                        : colors.onSurfaceVariant),
                                const SizedBox(width: 12),
                              ],
                              controls,
                              const Spacer(),
                              if (menu != null) menu,
                            ]),
                        ]))));
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Semantics(
                expanded: grouped ? group.expanded : null,
                button: grouped,
                child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap:
                        grouped ? () => widget.controller.expand(group) : null,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (problem) ...[
                                      Icon(
                                          group.kind == 'email_problem'
                                              ? Icons.mark_email_unread_outlined
                                              : Icons.account_balance_outlined,
                                          size: 20,
                                          color: hasError
                                              ? colors.error
                                              : colors.onSurfaceVariant),
                                      const SizedBox(width: 12),
                                    ],
                                    Expanded(child: heading),
                                    const SizedBox(width: 12),
                                    controls,
                                  ]),
                            ]))))),
        if (menu != null) menu,
      ]);
    });
  }

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
    final problem =
        const {'email_problem', 'bank_problem'}.contains(group.kind);
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
          problem ? const EdgeInsets.symmetric(vertical: 8) : EdgeInsets.zero,
      child: Material(
        color: problem ? colors.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: problem
              ? BorderSide(color: colors.outlineVariant)
              : BorderSide.none,
        ),
        child: Padding(
          padding: problem
              ? const EdgeInsets.all(16)
              : const EdgeInsets.symmetric(vertical: 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _groupHeader(context, group, occasion, grouped, hasError),
            if (!grouped || group.expanded) ...[
              for (final item in group.items) ...[
                const Divider(height: 16),
                _item(context, item),
              ],
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
                _retry(context, s('refreshFailed'),
                    () => c.expand(group, more: true)),
              if (!group.busy &&
                  !group.failed &&
                  (group.cursor != null || group.items.length < group.count))
                TextButton(
                    onPressed: () => c.expand(group, more: true),
                    child: Text(s('more'))),
            ],
            if (!problem) const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, NotificationItem item) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final error = _isError(item);
    String? value(String key) {
      final text = item.data[key]?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    final recipient = item.kind == 'email_problem' ? value('recipient') : null;
    final name = value('customerName');
    final reference = value('orderSymbol') ?? value('title');
    final title = name ??
        recipient ??
        reference ??
        NotificationCenterStrings.kind(item.kind);
    final secondary = recipient ?? (name != null ? reference : null);
    final status = NotificationCenterStrings.status(
        (item.data['state'] ?? item.status).toString());
    final metadata = [
      if (value('messageKind') != null)
        EmailDeliveryStrings.kind(value('messageKind')!),
      if (item.data['count'] is int)
        NotificationCenterStrings.places(item.data['count']),
      if (item.data['remainingPublic'] is int && item.data['limit'] is int)
        NotificationCenterStrings.capacity(
            item.data['remainingPublic'], item.data['limit']),
      if (item.data['heldForWaiting'] is int && item.data['heldForWaiting'] > 0)
        NotificationCenterStrings.held(item.data['heldForWaiting']),
    ];
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onSurface, fontWeight: FontWeight.w600)),
        if (secondary != null && secondary != title) ...[
          const SizedBox(height: 4),
          Text(secondary,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant)),
        ],
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(metadata.join(' · '),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant)),
        ],
        if (value('reason') != null) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(error ? Icons.error_outline : Icons.check_circle_outline,
                size: 20,
                color: error ? colors.error : colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
                child: Text(NotificationCenterStrings.reason(value('reason')!),
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: error ? colors.error : colors.onSurfaceVariant,
                        fontWeight:
                            error ? FontWeight.w600 : FontWeight.normal))),
          ]),
        ],
        const SizedBox(height: 8),
        Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (status.isNotEmpty)
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: error
                            ? colors.errorContainer
                            : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(status,
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: error
                                ? colors.onErrorContainer
                                : colors.onSurfaceVariant))),
              if (item.occurredAt != null)
                Tooltip(
                  message: NotificationCenterTime.exact(item.occurredAt!, context.locale.toLanguageTag()),
                  child: Text(NotificationCenterTime.timestamp(item.occurredAt!, context.locale.toLanguageTag()),
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))),
              if (_hasDetail(item))
                TextButton.icon(
                    onPressed: () => widget.onDetail(item),
                    style:
                        TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: Text(s('detail'))),
            ]),
      ]),
    );
  }
}

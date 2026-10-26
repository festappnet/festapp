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
                            ?.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                  ),
                  if (occasion != null) _muteMenu(context, occasion),
                ],
              ),
            ),
          if (first.occasionId != null && title != null)
            const Divider(height: 1),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final problem = const {'email_problem', 'bank_problem'}.contains(item.kind);
    final locale =
        (EasyLocalization.of(context)?.locale ??
                Localizations.localeOf(context))
            .toLanguageTag();
    final presentation = NotificationItemPresenter(item, locale: locale);
    final radius = BorderRadius.circular(problem ? 12 : 4);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: problem ? 8 : 0),
      child: Material(
        key: ValueKey('notification-item-${item.id}'),
        color: problem ? colors.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: problem
              ? BorderSide(color: colors.outlineVariant)
              : BorderSide.none,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: radius,
              onTap: presentation.hasDetail
                  ? () => widget.onDetail(item)
                  : null,
              child: problem
                  ? _incident(context, item, presentation, locale)
                  : _feedRow(context, item, presentation, locale),
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
            if (!problem) const Divider(height: 1),
          ],
        ),
      ),
    );
  }

  Widget _timestamp(
    BuildContext context,
    NotificationItem item,
    String locale, {
    bool compact = false,
  }) {
    final value = item.occurredAt!;
    final local = value.toLocal();
    return Tooltip(
      message: NotificationCenterTime.exact(value, locale),
      child: Text(
        compact
            ? '${NotificationCenterTime.day(local, locale)}\n${DateFormat.jm(locale).format(local)}'
            : NotificationCenterTime.timestamp(value, locale),
        textAlign: compact ? TextAlign.right : TextAlign.start,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _feedRow(
    BuildContext context,
    NotificationItem item,
    NotificationItemPresenter presentation,
    String locale,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final timeBeside =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) >=
            320;
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        presentation.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colors.onSurface,
                          fontWeight:
                              const {
                                'form_opened',
                                'form_closed',
                              }.contains(item.kind)
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                      if (presentation.details.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          presentation.details.join(' · '),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (!timeBeside && item.occurredAt != null) ...[
                        const SizedBox(height: 6),
                        _timestamp(context, item, locale),
                      ],
                    ],
                  ),
                ),
                if (timeBeside && item.occurredAt != null) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 76,
                    child: _timestamp(context, item, locale, compact: true),
                  ),
                ],
                const SizedBox(width: 8),
                SizedBox(
                  width: 18,
                  child: presentation.hasDetail
                      ? Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        )
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _incident(
    BuildContext context,
    NotificationItem item,
    NotificationItemPresenter presentation,
    String locale,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final details = presentation.details;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                item.kind == 'email_problem'
                    ? Icons.mark_email_unread_outlined
                    : Icons.account_balance_outlined,
                size: 20,
                color: presentation.isError
                    ? colors.error
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  presentation.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          for (var i = 0; i < details.length; i++) ...[
            SizedBox(height: i == 0 ? 12 : 6),
            if (details[i] == presentation.reason)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    presentation.isError
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    size: 18,
                    color: presentation.isError
                        ? colors.error
                        : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      details[i],
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: presentation.isError
                            ? colors.error
                            : colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(
                details[i],
                style: i == 0
                    ? theme.textTheme.titleMedium?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      )
                    : theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (item.occurredAt != null) _timestamp(context, item, locale),
              if (presentation.hasDetail)
                TextButton.icon(
                  onPressed: () => widget.onDetail(item),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(s('detail')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

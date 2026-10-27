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
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
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
                  title: Text(
                    NotificationCenterStrings.title,
                    textAlign: TextAlign.start,
                    style: const TextStyle(
                      fontSize: 28,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
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
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
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
                      ..._section(context, c.items),
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
      (byOccasion[item.occasionId ?? 'organization'] ??= []).add(item);
    }
    var firstSection = true;
    for (final entry in byOccasion.entries) {
      final first = entry.value.first;
      final occasion = widget.controller.occasions
          .where((item) => item['id'] == first.occasionId)
          .firstOrNull;
      final title = first.occasionTitle ?? occasion?['title']?.toString();
      yield Column(
        key: ValueKey('notification-occasion-${entry.key}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!firstSection)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
              child: Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          if (first.occasionId != null && title != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 0, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontSize: 20,
                              height: 1.25,
                              letterSpacing: 0,
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
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
      firstSection = false;
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

  Widget _unreadDot(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    child: Tooltip(
      message: s('newNotification'),
      excludeFromSemantics: true,
      child: Semantics(
        label: s('newNotification'),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    ),
  );

  IconData _kindIcon(String kind) => switch (kind) {
    'order_created' => Icons.confirmation_number_outlined,
    'order_cancelled' => Icons.cancel_outlined,
    'waitlist_registered' => Icons.hourglass_empty,
    'offer_accepted' => Icons.check_circle_outline,
    'offer_declined' || 'offer_expired' => Icons.event_busy_outlined,
    'email_problem' => Icons.mail_outline,
    'bank_problem' => Icons.account_balance_outlined,
    'capacity_warning' ||
    'capacity_full' ||
    'capacity_reopened' ||
    'event_capacity_full' ||
    'occasion_joined' => Icons.people_outline,
    _ => Icons.event_note_outlined,
  };

  Widget _summarySubtitle(
    BuildContext context,
    NotificationItemPresenter presentation,
    List<String> details,
  ) {
    final names = presentation.previewNames;
    final total = presentation.item.data['activityCount'] as int;
    // Reuse existing copyWith call shapes. A new nullable named-argument call
    // shape adds a forwarding stub to every dart2js closure in deferred chunks.
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          height: 1.4,
          letterSpacing: 0,
        )
        .copyWith(fontSize: 15);
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final prefix = details.isEmpty ? '' : '${details.join(' · ')} · ';
    bool fits(String text, double width) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: textScaler,
        maxLines: 1,
      )..layout(maxWidth: width);
      final fits = !painter.didExceedMaxLines;
      painter.dispose();
      return fits;
    }

    String preview(double width, String prefix) {
      for (var count = names.length; count > 0; count--) {
        final text =
            '$prefix${names.take(count).join(', ')}${total > count ? ' …' : ''}';
        if (fits(text, width)) return text;
      }
      return '$prefix${names.first} …';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wrapPlaces =
            prefix.isNotEmpty && !fits('$prefix${names.first}', width);
        final text = preview(width, wrapPlaces ? '' : prefix);
        final namesText = Text(
          text,
          key: ValueKey('notification-preview-${presentation.item.id}'),
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        return Semantics(
          label: '$prefix${names.join(', ')}',
          excludeSemantics: true,
          child: wrapPlaces
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(details.join(' · '), style: style),
                    const SizedBox(height: 4),
                    namesText,
                  ],
                )
              : namesText,
        );
      },
    );
  }

  Widget _item(BuildContext context, NotificationItem item) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final unread = widget.controller.isUnread(item);
    final locale =
        (EasyLocalization.of(context)?.locale ??
                Localizations.localeOf(context))
            .toLanguageTag();
    final presentation = NotificationItemPresenter(item, locale: locale);
    final details = presentation.details;
    final day = item.day ?? item.occurredAt?.toLocal();
    const radius = BorderRadius.all(Radius.circular(4));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        key: ValueKey('notification-item-${item.id}'),
        color: Colors.transparent,
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: radius,
              onTap: presentation.hasDetail
                  ? () => widget.onDetail(item)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A stable leading anchor separates rows without cards.
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            (presentation.isError
                                    ? colors.error
                                    : unread
                                    ? colors.primary
                                    : colors.onSurfaceVariant)
                                .withValues(alpha: .10),
                      ),
                      child: Icon(
                        _kindIcon(item.kind),
                        size: 22,
                        color: presentation.isError
                            ? colors.error
                            : unread
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            presentation.title,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 17,
                              height: 1.3,
                              color: unread
                                  ? colors.onSurface
                                  : colors.onSurfaceVariant,
                              fontWeight: unread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              letterSpacing: 0,
                            ),
                          ),
                          if (item.isSummary &&
                              (item.data['activityCount'] as int) > 1 &&
                              presentation.previewNames.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            _summarySubtitle(context, presentation, details),
                          ] else if (details.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text.rich(
                              TextSpan(
                                children: [
                                  for (var i = 0; i < details.length; i++) ...[
                                    if (i > 0)
                                      TextSpan(
                                        text:
                                            details[i] == presentation.reason &&
                                                presentation.isError
                                            ? '\n'
                                            : ' · ',
                                      ),
                                    TextSpan(
                                      text: details[i],
                                      style: TextStyle(
                                        color:
                                            details[i] == presentation.reason &&
                                                presentation.isError
                                            ? colors.error
                                            : colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                          ],
                          if (day != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              NotificationCenterTime.dayHeading(
                                day,
                                locale,
                                now:
                                    widget.controller.snapshotDay ??
                                    widget.controller.snapshotAt,
                              ),
                              key: ValueKey('notification-age-${item.id}'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 13,
                                height: 1.35,
                                letterSpacing: 0,
                                color: unread
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                                fontWeight: unread
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (unread) ...[
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _unreadDot(context),
                      ),
                    ],
                  ],
                ),
              ),
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
          ],
        ),
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/news/news_strings.dart';

enum NewsNotificationAudience { none, everyone, selfTest }

extension NewsNotificationAudienceBehavior on NewsNotificationAudience {
  bool get sendsNotification => this != NewsNotificationAudience.none;

  bool get publishesNews => this != NewsNotificationAudience.selfTest;

  bool get sendsToSelfOnly => this == NewsNotificationAudience.selfTest;

  Map<String, Object> deliveryFields({
    required String currentUserId,
    bool forceSelfOnly = false,
  }) {
    final selfOnly = sendsNotification && (sendsToSelfOnly || forceSelfOnly);
    return {
      'with_notification': sendsNotification,
      if (!publishesNews) 'add_to_news': false,
      if (selfOnly) 'to': [currentUserId],
    };
  }
}

/// A single decision point for the delivery mode. Keeping "no push" alongside
/// the two audiences avoids contradictory checkbox + recipient states.
class NewsNotificationAudienceSelector extends StatelessWidget {
  final NewsNotificationAudience? selected;
  final ValueChanged<NewsNotificationAudience> onChanged;
  final String currentUserIdentity;
  final bool allowEveryone;

  const NewsNotificationAudienceSelector({
    required this.selected,
    required this.onChanged,
    required this.currentUserIdentity,
    required this.allowEveryone,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          NewsStrings.recipientChoiceTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          NewsStrings.recipientChoiceRequired,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        _AudienceOption(
          selected: selected == NewsNotificationAudience.none,
          icon: Icons.notifications_off_outlined,
          title: NewsStrings.newsWithoutNotification,
          detail: NewsStrings.newsWithoutNotificationDetail,
          onTap: () => onChanged(NewsNotificationAudience.none),
        ),
        if (allowEveryone) ...[
          const SizedBox(height: 8),
          _AudienceOption(
            selected: selected == NewsNotificationAudience.everyone,
            icon: Icons.groups_outlined,
            title: NewsStrings.notificationAudienceEveryone(
              AppConfig.appName,
            ),
            detail: NewsStrings.notificationAudienceEveryoneDetail,
            onTap: () => onChanged(NewsNotificationAudience.everyone),
          ),
        ],
        const SizedBox(height: 8),
        _AudienceOption(
          selected: selected == NewsNotificationAudience.selfTest,
          icon: Icons.person_outline,
          title: NewsStrings.notificationAudienceSelf,
          detail: NewsStrings.notificationAudienceSelfDetail(
            currentUserIdentity,
          ),
          onTap: () => onChanged(NewsNotificationAudience.selfTest),
        ),
      ],
    );
  }
}

class _AudienceOption extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  const _AudienceOption({
    required this.selected,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selectedBackground = Color.alphaBlend(
      colors.primary.withAlpha(18),
      colors.surface,
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? selectedBackground : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? colors.primary.withAlpha(150)
                : colors.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primary.withAlpha(24)
                        : colors.onSurface.withAlpha(10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: selected ? colors.primary : null,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'email_delivery_strings.dart';
import 'email_delivery_history.dart';

class EmailDeliveryIndicator extends StatelessWidget {
  // Lucide Check / Check Check (ISC license, see LICENSE-lucide.txt).
  static const _singleCheck =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
      'fill="none" stroke="currentColor" stroke-width="2.5" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M20 6 9 17l-5-5"/></svg>';
  static const _doubleCheck =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
      'fill="none" stroke="currentColor" stroke-width="2.5" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M18 6 7 17l-5-5"/>'
      '<path d="m22 10-7.5 7.5L13 16"/></svg>';

  final Map<String, dynamic>? summary;
  final int? orderId;
  final int? occasionId;
  final VoidCallback? onHistory;
  const EmailDeliveryIndicator(
      {super.key, this.summary, this.orderId, this.occasionId, this.onHistory});

  String _description(Map<String, dynamic> entry) {
    final kind = entry['kind']?.toString();
    final state =
        EmailDeliveryStrings.state(entry['state']?.toString() ?? 'unavailable');
    final at = DateTime.tryParse(entry['at']?.toString() ?? '');
    return '${kind == null ? '' : '${EmailDeliveryStrings.kind(kind)}: '}$state${at == null ? '' : ' (${DateFormat.yMd().add_Hm().format(at.toLocal())})'}';
  }

  @override
  Widget build(BuildContext context) {
    final state = summary?['state']?.toString() ?? 'unavailable';
    final warning = [
      'retry_wait',
      'unknown',
      'dead',
      'bounce',
      'complaint',
      'suppressed',
      'reject',
      'rendering_failure',
      'delay',
      'post_action_failed'
    ].contains(state);
    final waiting =
        ['pending', 'preparing', 'sending', 'blocked'].contains(state);
    final delivered = state == 'delivery';
    final opened = ['open', 'click'].contains(state);
    final icon = warning
        ? Icons.mark_email_unread_outlined
        : waiting
            ? Icons.schedule_send_outlined
            : state == 'accepted'
                ? Icons.forward_to_inbox
                : Icons.mail_outline;
    final entries = (summary?['messages'] as List?) ?? [];
    final loadedAt = DateTime.tryParse(summary?['loaded_at']?.toString() ?? '');
    final entriesDescription = entries.isEmpty
        ? _description(summary ?? {'state': 'unavailable'})
        : entries
            .take(5)
            .map((e) => _description(Map<String, dynamic>.from(e as Map)))
            .join('\n');
    final description = entriesDescription +
        (loadedAt == null
            ? ''
            : '\n${EmailDeliveryStrings.refreshed(DateFormat.yMd().add_Hms().format(loadedAt.toLocal()))}');
    final attention = (summary?['attention_count'] as num?)?.toInt() ?? 0;
    return Tooltip(
      message: description,
      child: SizedBox(
          width: 48,
          height: 48,
          child: IconButton(
            tooltip: null,
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => _showExplanation(context),
            icon: Semantics(
                label: description,
                child: Badge(
                    isLabelVisible: attention > 0,
                    label: Text('$attention'),
                    child: opened || delivered
                        ? SvgPicture.string(
                            opened ? _doubleCheck : _singleCheck,
                            key: ValueKey(opened
                                ? 'email-opened-checks'
                                : 'email-delivered-check'),
                            width: 24,
                            height: 24,
                            colorFilter: ColorFilter.mode(
                                IconTheme.of(context).color ??
                                    Theme.of(context).colorScheme.onSurface,
                                BlendMode.srcIn),
                          )
                        : Icon(icon,
                            color: warning
                                ? Theme.of(context).colorScheme.error
                                : null))),
          )),
    );
  }

  void _showExplanation(BuildContext context) {
    final messages = (summary?['messages'] as List?) ?? [];
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(EmailDeliveryStrings.title,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (messages.isEmpty) Text(EmailDeliveryStrings.unavailable),
            for (final entry in messages)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                      _description(Map<String, dynamic>.from(entry as Map)))),
            if (onHistory != null || (orderId != null && occasionId != null))
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  if (onHistory != null) {
                    onHistory!();
                  } else {
                    showDialog<void>(
                        context: context,
                        builder: (_) => EmailDeliveryHistory(
                            occasionId: occasionId!, orderId: orderId));
                  }
                },
                child: Text(EmailDeliveryStrings.history),
              ),
          ]),
    );
    if (MediaQuery.sizeOf(context).width < 600) {
      showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) =>
              SafeArea(child: SingleChildScrollView(child: content)));
    } else {
      showDialog<void>(
          context: context,
          builder: (_) => Dialog(child: SingleChildScrollView(child: content)));
    }
  }
}

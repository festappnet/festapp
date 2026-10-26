import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/event_feedback/db_event_feedback.dart';
import 'package:fstapp/components/event_feedback/event_feedback_model.dart';
import 'package:fstapp/components/event_feedback/event_feedback_strings.dart';

/// Inline feedback results shown to editors on the event page (and reused in the
/// Program → Feedback admin subtab). Mirrors the deployed layout: a
/// "feedbackResults (N)" header, smiley count chips, and a respondent list.
class EventFeedbackResults extends StatefulWidget {
  final int eventId;
  const EventFeedbackResults({super.key, required this.eventId});

  static IconData ratingIcon(String rating) {
    switch (rating) {
      case EventFeedbackModel.ratingHappy:
        return Icons.sentiment_very_satisfied;
      case EventFeedbackModel.ratingNeutral:
        return Icons.sentiment_neutral;
      case EventFeedbackModel.ratingSad:
        return Icons.sentiment_very_dissatisfied;
      default:
        return Icons.help_outline;
    }
  }

  static Color ratingColor(String rating, BuildContext context) {
    switch (rating) {
      case EventFeedbackModel.ratingHappy:
        return Colors.green;
      case EventFeedbackModel.ratingNeutral:
        return Colors.amber.shade700;
      case EventFeedbackModel.ratingSad:
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  @override
  State<EventFeedbackResults> createState() => _EventFeedbackResultsState();
}

class _EventFeedbackResultsState extends State<EventFeedbackResults> {
  EventFeedbackForEdit? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await DbEventFeedback.getForEdit(widget.eventId);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final s = _data?.summary ?? EventFeedbackSummary();
    final items = _data?.items ?? const <EventFeedbackItem>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${EventFeedbackStrings.feedbackResults} (${s.total})',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _countChip(context, EventFeedbackModel.ratingHappy, s.happy),
            _countChip(context, EventFeedbackModel.ratingNeutral, s.neutral),
            _countChip(context, EventFeedbackModel.ratingSad, s.sad),
          ],
        ),
        if (items.isNotEmpty) ...[
          const Divider(height: 24),
          ...items.map((i) => _respondentTile(context, i)),
        ],
      ],
    );
  }

  Widget _countChip(BuildContext context, String rating, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(EventFeedbackResults.ratingIcon(rating), size: 18, color: EventFeedbackResults.ratingColor(rating, context)),
        const SizedBox(width: 4),
        Text('$count'),
      ],
    );
  }

  Widget _respondentTile(BuildContext context, EventFeedbackItem i) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(EventFeedbackResults.ratingIcon(i.rating), color: EventFeedbackResults.ratingColor(i.rating, context)),
      title: Text(i.isAnonymous || (i.userName?.isEmpty ?? true)
          ? EventFeedbackStrings.anonymous
          : i.userName!),
      subtitle: (i.note?.isNotEmpty ?? false) ? Text(i.note!) : null,
    );
  }
}

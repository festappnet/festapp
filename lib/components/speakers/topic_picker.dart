import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/speakers/speaker_topic_model.dart';

/// A single-select radio list of counseling areas. Exactly one topic can be
/// selected at a time — picking another deselects the previous one (the shared
/// [selectedTopicId] group value guarantees this). Extracted so it can be
/// pumped and asserted directly in widget tests.
class TopicPicker extends StatelessWidget {
  final List<SpeakerTopicModel> topics;
  final int? selectedTopicId;
  final ValueChanged<int> onSelected;

  /// Ids of areas that currently have at least one free future slot. Areas not
  /// in this set are shown greyed out (but stay tappable, revealing the empty
  /// state). When null (overview not loaded), no area is greyed.
  final Set<int>? availableTopicIds;

  /// Occupancy per area (occupied, total future slots), shown as the same
  /// capacity badge normal events use. Absent / total 0 → no badge.
  final Map<int, ({int occupied, int total})>? occupancyByTopic;

  const TopicPicker({
    super.key,
    required this.topics,
    required this.selectedTopicId,
    required this.onSelected,
    this.availableTopicIds,
    this.occupancyByTopic,
  });

  @override
  Widget build(BuildContext context) {
    // Selection is managed by the RadioGroup ancestor (the per-tile groupValue /
    // onChanged were deprecated after Flutter 3.32).
    return RadioGroup<int>(
      groupValue: selectedTopicId,
      onChanged: (value) {
        if (value != null) onSelected(value);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final topic in topics)
            if (topic.id != null)
              Opacity(
                // Grey out areas with no free slots; still clickable.
                opacity: (availableTopicIds == null ||
                        availableTopicIds!.contains(topic.id))
                    ? 1.0
                    : 0.45,
                child: RadioListTile<int>(
                  value: topic.id!,
                  title: Text(topic.title ?? ""),
                  secondary: _capacityBadge(topic.id!),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                ),
              ),
        ],
      ),
    );
  }

  /// Occupancy shown exactly like the program's capacity badge
  /// (light_timeline_view `_CapacityChip` unsigned state): a plain grey
  /// "occupied/total + people" inline, tabular figures, no pill. No badge when
  /// the area has no slots at all.
  Widget? _capacityBadge(int topicId) {
    final occ = occupancyByTopic?[topicId];
    if (occ == null || occ.total <= 0) return null;
    const fg = Colors.grey;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('${occ.occupied}/${occ.total}',
              style: const TextStyle(
                fontSize: 13,
                height: 1.0,
                color: fg,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
              )),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.people, size: 14, color: fg),
      ],
    );
  }
}

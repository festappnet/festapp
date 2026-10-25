import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/speakers/admin/speaker_picker_field.dart';
import 'package:fstapp/components/speakers/speaker_avatar.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/theme_config.dart';

/// Compact schedule-grid cell for attaching speakers to an event.
///
/// Shows the attached speakers as small avatars (or an "add speaker"
/// affordance when empty) and opens the shared speaker picker on tap.
/// Persistence is delegated to [onSave] (the grid calls set_event_speakers) so
/// the change saves immediately, outside the grid's row Save/Discard model —
/// matching how the intro-image and HTML-content cells already persist.
class EventSpeakersCell extends StatefulWidget {
  /// The persisted event id, or null for a not-yet-saved row.
  final int? eventId;
  final int aggregateVersion;

  /// All selectable speakers for the occasion (shared list instance so a
  /// speaker created inline becomes visible to every cell).
  final List<SpeakerModel> allSpeakers;

  /// Speaker ids currently attached to this event.
  final List<int> initialSelectedIds;

  /// Persists the new selection (set_event_speakers). Called on confirm.
  final Future<int?> Function(
      int eventId, int expectedVersion, List<int> speakerIds) onSave;

  /// Opens the "add speaker" editor and returns the new speaker's id to
  /// pre-select, or null. When null, the add affordance is hidden.
  final Future<int?> Function()? onAddSpeaker;

  const EventSpeakersCell({
    super.key,
    required this.eventId,
    required this.aggregateVersion,
    required this.allSpeakers,
    required this.initialSelectedIds,
    required this.onSave,
    this.onAddSpeaker,
  });

  @override
  State<EventSpeakersCell> createState() => _EventSpeakersCellState();
}

class _EventSpeakersCellState extends State<EventSpeakersCell> {
  late List<int> _selected;
  late int _aggregateVersion;

  @override
  void initState() {
    super.initState();
    _selected = List.of(widget.initialSelectedIds);
    _aggregateVersion = widget.aggregateVersion;
  }

  @override
  void didUpdateWidget(covariant EventSpeakersCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trina reuses cell widgets across rows on scroll; when the bound event
    // changes, resync the selection from the new row's data.
    if (oldWidget.eventId != widget.eventId) {
      _selected = List.of(widget.initialSelectedIds);
      _aggregateVersion = widget.aggregateVersion;
    } else if (oldWidget.aggregateVersion != widget.aggregateVersion) {
      _aggregateVersion = widget.aggregateVersion;
    }
  }

  List<SpeakerModel> get _selectedSpeakers => widget.allSpeakers
      .where((s) => s.id != null && _selected.contains(s.id))
      .toList();

  Future<void> _open() async {
    final eventId = widget.eventId;
    if (eventId == null) return;
    final result = await showSpeakerPickerDialog(
      context,
      allSpeakers: widget.allSpeakers,
      selectedIds: _selected,
      onAddSpeaker: widget.onAddSpeaker,
    );
    if (result == null) return;
    setState(() => _selected = result);
    final version = await widget.onSave(eventId, _aggregateVersion, result);
    if (version != null) _aggregateVersion = version;
  }

  @override
  Widget build(BuildContext context) {
    // New, unsaved rows have no id yet — set_event_speakers needs a persisted
    // event, so defer the affordance until the row's been saved.
    if (widget.eventId == null || widget.eventId! <= 0) {
      return Center(
        child: Text('—', style: TextStyle(color: ThemeConfig.grey500(context))),
      );
    }

    final selected = _selectedSpeakers;
    return InkWell(
      onTap: _open,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: selected.isEmpty
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_add_alt_1,
                      size: 18, color: ThemeConfig.grey700(context)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      SpeakersStrings.selectSpeakers,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: ThemeConfig.grey700(context)),
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._buildAvatars(selected),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      selected.length == 1
                          ? (selected.first.title ?? '')
                          : '${selected.length}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildAvatars(List<SpeakerModel> selected) {
    const maxShown = 3;
    final shown = selected.take(maxShown).toList();
    return [
      for (int i = 0; i < shown.length; i++)
        Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
          child: SpeakerAvatar(imageUrl: shown[i].image, radius: 12),
        ),
    ];
  }
}

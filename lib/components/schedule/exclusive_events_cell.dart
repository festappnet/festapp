import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/theme_config.dart';

/// Compact exclusivity-grid cell for the events of an exclusive group.
///
/// Shows the selected events as small titled chips (instead of raw ids) and
/// opens a searchable multi-select picker on tap. The widget is pure: it only
/// reports the new id list through [onChanged] — the grid cell keeps owning
/// the value, so the row saves through the normal Save/Discard flow.
class ExclusiveEventsCell extends StatelessWidget {
  /// All selectable events of the occasion, sorted by start time.
  final List<EventModel> allEvents;

  /// Ids of the events currently in the group.
  final List<int> selectedIds;

  /// Called with the new id list when the picker is confirmed.
  final ValueChanged<List<int>> onChanged;

  const ExclusiveEventsCell({
    super.key,
    required this.allEvents,
    required this.selectedIds,
    required this.onChanged,
  });

  /// Selected events in chronological order, so chips read like the schedule.
  List<EventModel> get _selectedEvents => allEvents
      .where((e) => e.id != null && selectedIds.contains(e.id))
      .toList();

  Future<void> _open(BuildContext context) async {
    final result = await showEventPickerDialog(
      context,
      allEvents: allEvents,
      selectedIds: selectedIds,
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedEvents;
    return InkWell(
      onTap: () => _open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: selected.isEmpty
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.playlist_add,
                      size: 18, color: ThemeConfig.grey700(context)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      ScheduleStrings.selectEvents,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: ThemeConfig.grey700(context)),
                    ),
                  ),
                ],
              )
            : Tooltip(
                message: selected
                    .map((e) => "${e.title ?? ''} (${_timeLabel(context, e)})")
                    .join("\n"),
                child: _buildChips(context, selected),
              ),
      ),
    );
  }

  Widget _buildChips(BuildContext context, List<EventModel> selected) {
    const maxShown = 3;
    final shown = selected.take(maxShown).toList();
    final rest = selected.length - shown.length;
    return Row(
      children: [
        for (final e in shown)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ThemeConfig.grey200(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  e.title ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
        if (rest > 0)
          Text(
            "+$rest",
            style: TextStyle(
                fontSize: 12, color: ThemeConfig.grey700(context)),
          ),
      ],
    );
  }
}

String _timeLabel(BuildContext context, EventModel e) =>
    "${DateFormat("E d. M. HH:mm", context.locale.languageCode).format(e.startTime)}"
    "–${DateFormat.Hm().format(e.endTime)}";

/// Opens the searchable multi-select event dialog and returns the chosen id
/// list (chronological), or null if cancelled.
Future<List<int>?> showEventPickerDialog(
  BuildContext context, {
  required List<EventModel> allEvents,
  required List<int> selectedIds,
}) {
  return showDialog<List<int>>(
    context: context,
    builder: (_) => _EventPickerDialog(
      allEvents: allEvents,
      initialSelected: selectedIds,
    ),
  );
}

/// Searchable multi-select dialog. Pops the chosen id list (or null on cancel).
class _EventPickerDialog extends StatefulWidget {
  final List<EventModel> allEvents;
  final List<int> initialSelected;

  const _EventPickerDialog({
    required this.allEvents,
    required this.initialSelected,
  });

  @override
  State<_EventPickerDialog> createState() => _EventPickerDialogState();
}

class _EventPickerDialogState extends State<_EventPickerDialog> {
  late final Set<int> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelected.toSet();
  }

  List<EventModel> get _filtered {
    final q = Utilities.removeDiacritics(_query.trim().toLowerCase());
    if (q.isEmpty) return widget.allEvents;
    return widget.allEvents.where((e) {
      final hay = Utilities.removeDiacritics((e.title ?? '').toLowerCase());
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return AlertDialog(
      title: Text("${CommonStrings.events} (${_selected.length})"),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: ScheduleStrings.searchEvents,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('—'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: filtered
                          .where((e) => e.id != null)
                          .map((e) => CheckboxListTile(
                                dense: true,
                                value: _selected.contains(e.id),
                                title: Text(e.title ?? ''),
                                subtitle: Text(_timeLabel(context, e)),
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _selected.add(e.id!);
                                  } else {
                                    _selected.remove(e.id);
                                  }
                                }),
                              ))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(CommonStrings.storno),
        ),
        FilledButton(
          // Keep chronological order so the saved list matches the schedule.
          onPressed: () => Navigator.of(context).pop(widget.allEvents
              .where((e) => e.id != null && _selected.contains(e.id))
              .map((e) => e.id!)
              .toList()),
          child: Text(CommonStrings.ok),
        ),
      ],
    );
  }
}

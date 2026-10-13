import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/speakers/speaker_avatar.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/theme_config.dart';

/// A form-style field for attaching speakers to an event (decision R6).
///
/// Selected speakers render as avatar chips (avatar + name, × to remove);
/// tapping the field opens a searchable multi-select dialog. The widget is a
/// pure, testable state container: all speaker data and the "add speaker"
/// action are injected — it never performs RPC itself (the caller does, and
/// passes a refreshed [allSpeakers] / [selectedIds] back in).
class SpeakerPickerField extends StatelessWidget {
  /// All selectable speakers for the occasion (already loaded by the caller).
  final List<SpeakerModel> allSpeakers;

  /// Currently attached speaker ids.
  final List<int> selectedIds;

  /// Called with the new selection whenever it changes.
  final ValueChanged<List<int>> onChanged;

  /// Opens the "add speaker" editor and returns the id of a newly created
  /// speaker to pre-select (or null if none was created). RPC lives in the
  /// caller — never here. When null, the add affordance is hidden.
  final Future<int?> Function()? onAddSpeaker;

  const SpeakerPickerField({
    super.key,
    required this.allSpeakers,
    required this.selectedIds,
    required this.onChanged,
    this.onAddSpeaker,
  });

  List<SpeakerModel> get _selectedSpeakers => allSpeakers
      .where((s) => s.id != null && selectedIds.contains(s.id))
      .toList();

  Future<void> _openDialog(BuildContext context) async {
    final result = await showSpeakerPickerDialog(
      context,
      allSpeakers: allSpeakers,
      selectedIds: selectedIds,
      onAddSpeaker: onAddSpeaker,
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedSpeakers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          SpeakersStrings.speakersOnEvent,
          style: theme.textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _openDialog(context),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: ThemeConfig.grey500(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: selected.isEmpty
                ? Text(
                    SpeakersStrings.selectSpeakers,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: ThemeConfig.grey700(context)),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: selected
                        .map((s) => InputChip(
                              avatar: SpeakerAvatar(imageUrl: s.image, radius: 12),
                              label: Text(s.title ?? ''),
                              deleteIcon: const Icon(Icons.close, size: 18),
                              onDeleted: () => onChanged(
                                selectedIds.where((id) => id != s.id).toList(),
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Opens the searchable multi-select speaker dialog and returns the chosen id
/// list, or null if cancelled. Shared by [SpeakerPickerField] (the event
/// editor) and the schedule grid's speaker cell so both use the exact same
/// picker, search and "add speaker" affordances.
Future<List<int>?> showSpeakerPickerDialog(
  BuildContext context, {
  required List<SpeakerModel> allSpeakers,
  required List<int> selectedIds,
  Future<int?> Function()? onAddSpeaker,
}) {
  return showDialog<List<int>>(
    context: context,
    builder: (_) => _SpeakerPickerDialog(
      allSpeakers: allSpeakers,
      initialSelected: selectedIds,
      onAddSpeaker: onAddSpeaker,
    ),
  );
}

/// Searchable multi-select dialog. Pops the chosen id list (or null on cancel).
class _SpeakerPickerDialog extends StatefulWidget {
  final List<SpeakerModel> allSpeakers;
  final List<int> initialSelected;
  final Future<int?> Function()? onAddSpeaker;

  const _SpeakerPickerDialog({
    required this.allSpeakers,
    required this.initialSelected,
    this.onAddSpeaker,
  });

  @override
  State<_SpeakerPickerDialog> createState() => _SpeakerPickerDialogState();
}

class _SpeakerPickerDialogState extends State<_SpeakerPickerDialog> {
  late final Set<int> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelected.toSet();
  }

  List<SpeakerModel> get _filtered {
    final q = Utilities.removeDiacritics(_query.trim().toLowerCase());
    if (q.isEmpty) return widget.allSpeakers;
    return widget.allSpeakers.where((s) {
      final hay = Utilities.removeDiacritics((s.title ?? '').toLowerCase());
      return hay.contains(q);
    }).toList();
  }

  Future<void> _addSpeaker() async {
    final newId = await widget.onAddSpeaker?.call();
    if (newId != null && mounted) {
      // Pre-select the freshly created speaker and hand control back so the
      // caller can refresh its speaker list (decision R6).
      Navigator.of(context).pop([..._selected, newId]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return AlertDialog(
      title: Text(SpeakersStrings.speakersOnEvent),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: SpeakersStrings.searchSpeakers,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('—'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: filtered
                          .where((s) => s.id != null)
                          .map((s) => CheckboxListTile(
                                dense: true,
                                value: _selected.contains(s.id),
                                secondary:
                                    SpeakerAvatar(imageUrl: s.image, radius: 18),
                                title: Text(s.title ?? ''),
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _selected.add(s.id!);
                                  } else {
                                    _selected.remove(s.id);
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
        if (widget.onAddSpeaker != null)
          TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            onPressed: _addSpeaker,
            label: Text(SpeakersStrings.addSpeaker),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(CommonStrings.storno),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
          child: Text(CommonStrings.ok),
        ),
      ],
    );
  }
}

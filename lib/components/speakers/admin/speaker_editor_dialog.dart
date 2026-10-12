import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/components/images/db_images.dart';
import 'package:fstapp/components/images/image_area.dart';
import 'package:fstapp/components/images/image_compression_helper.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/map/db_places.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:fstapp/components/speakers/admin/counseling_slot_dialog.dart';
import 'package:fstapp/components/speakers/db_speakers.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speaker_topic_model.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/services/toast_helper.dart';

/// Admin dialog to create or edit a speaker (lecturer / counselor).
///
/// For an existing speaker it also exposes the counseling-slot generator and
/// the current slot grid. Pops `true` when anything was persisted so the parent
/// tab can reload. All writes go through [DbSpeakers] wrapped in
/// [ExceptionHandler.guard].
class SpeakerEditorDialog extends StatefulWidget {
  final SpeakerModel speaker;
  final List<SpeakerTopicModel> topics;

  const SpeakerEditorDialog({
    super.key,
    required this.speaker,
    required this.topics,
  });

  @override
  State<SpeakerEditorDialog> createState() => _SpeakerEditorDialogState();
}

class _SpeakerEditorDialogState extends State<SpeakerEditorDialog> {
  final _htmlSave = HtmlSaveCoordinator();
  @override
  Widget build(BuildContext context) => HtmlEditingScope(
    coordinator: _htmlSave, child: _buildHtmlParent(context));

  late final TextEditingController _nameController;
  late final TextEditingController _subtitleController;
  late final TextEditingController _orderController;

  String? _image;
  String? _description;
  bool _isHidden = false;
  late Set<int> _selectedTopics;
  bool _changed = false;

  // Places catalog, loaded for the slot dialog's place picker.
  List<PlaceModel> _places = [];

  int get _occasionId => RightsService.currentOccasionId()!;

  bool get _isExisting => widget.speaker.id != null;

  @override
  void initState() {
    super.initState();
    final s = widget.speaker;
    _nameController = TextEditingController(text: s.title ?? '');
    _subtitleController = TextEditingController(text: s.subtitle ?? '');
    _orderController = TextEditingController(text: s.order.toString());
    _image = s.image;
    _description = s.description;
    _isHidden = s.isHidden;
    _selectedTopics = s.topics.toSet();
    if (_isExisting) {
      _loadPlaces();
    }
  }

  @override
  void dispose() {
    _htmlSave.dispose();
    _nameController.dispose();
    _subtitleController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces() async {
    final places = await ExceptionHandler.guard<List<PlaceModel>>(
      context,
      futureFunction: () => DbPlaces.getAllPlaces(),
    );
    if (places != null && mounted) {
      setState(() => _places = places);
    }
  }

  Future<void> _save() async {
    await ExceptionHandler.guardVoid(context, futureFunction: () =>
      _htmlSave.save(() => _performHtmlSave(), context: context));
  }

  Future<void> _performHtmlSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ToastHelper.Show(context, CommonStrings.fieldCannotBeEmpty,
          severity: ToastSeverity.NotOk);
      return;
    }

    _description = await _htmlSave.prepare(_description ?? '', HtmlMediaOwner.occasion(_occasionId));
    final subtitle = _subtitleController.text.trim();
    final model = widget.speaker
      ..title = name
      ..subtitle = subtitle.isEmpty ? null : subtitle
      ..description = _description
      ..image = _image
      ..order = int.tryParse(_orderController.text.trim()) ?? 0
      ..isHidden = _isHidden
      ..topics = _selectedTopics.toList();

    final saved = await ExceptionHandler.guard<SpeakerModel>(
      context,
      futureFunction: () => DbSpeakers.updateSpeaker(_occasionId, model),
    );
    if (saved != null && mounted) {
      _htmlSave.markSaved();
      ToastHelper.Show(context, CommonStrings.saved);
      // Pop the saved model so callers (e.g. the event edit speaker picker) can
      // pre-select the freshly created speaker (decision R6b). The close button
      // still pops _changed (bool); callers treat any truthy result as reload.
      Navigator.of(context).pop(saved);
    }
  }

  /// Adds a single slot via the quick dialog (mirrors "Add to schedule").
  /// One slot is created by asking [createCounselingSlots] for a slot length
  /// equal to the whole picked range.
  Future<void> _addSlot() async {
    final res = await CounselingSlotDialog.show(context, places: _places);
    if (res == null || !mounted) return;

    final minutes = res.end.difference(res.start).inMinutes;
    if (minutes < 5) {
      ToastHelper.Show(context, SpeakersStrings.slotTooShort,
          severity: ToastSeverity.NotOk);
      return;
    }

    final result =
        await ExceptionHandler.guard<({int created, List<int> eventIds})>(
      context,
      futureFunction: () => DbSpeakers.createCounselingSlots(
        speakerId: widget.speaker.id!,
        // The picker yields occasion-local wall-clock times; convert to UTC
        // through the occasion timezone (same convention as event editing).
        start: res.start.toUtcFromOccasionTime(),
        end: res.end.toUtcFromOccasionTime(),
        slotMinutes: minutes,
        placeId: res.placeId,
        capacity: res.capacity,
      ),
    );
    if (result != null && mounted) {
      _changed = true;
      ToastHelper.Show(context, CommonStrings.saved);
      await _reloadSpeaker();
    }
  }

  /// Edits an existing slot in place. Loads the full event (the admin slot
  /// grid carries no place/type/data), lets the user re-pick, then updates —
  /// preserving the counseling tag, type and speaker link.
  Future<void> _editSlot(SpeakerEventRef slot) async {
    final event = await ExceptionHandler.guard<EventModel>(
      context,
      futureFunction: () => DbEvents.getEvent(slot.id),
    );
    if (event == null || !mounted) return;

    final res = await CounselingSlotDialog.show(
      context,
      places: _places,
      initialStart: event.startTime,
      initialEnd: event.endTime,
      initialPlaceId: event.place?.id,
      initialCapacity: event.maxParticipants ?? 1,
    );
    if (res == null || !mounted) return;

    final minutes = res.end.difference(res.start).inMinutes;
    if (minutes < 5) {
      ToastHelper.Show(context, SpeakersStrings.slotTooShort,
          severity: ToastSeverity.NotOk);
      return;
    }

    event
      ..startTime = res.start
      ..endTime = res.end
      ..maxParticipants = res.capacity
      ..place = _places.firstWhereOrNull((p) => p.id == res.placeId);

    final saved = await ExceptionHandler.guard<EventModel>(
      context,
      futureFunction: () => DbEvents.updateEvent(event),
    );
    if (saved != null && mounted) {
      _changed = true;
      ToastHelper.Show(context, CommonStrings.saved);
      await _reloadSpeaker();
    }
  }

  Future<void> _deleteSlot(SpeakerEventRef slot) async {
    final confirm = await DialogHelper.showConfirmationDialog(
      context,
      SpeakersStrings.counselingSlots,
      CommonStrings.confirmRemoval,
    );
    if (confirm != true || !mounted) return;

    final ok = await ExceptionHandler.guardVoid(
      context,
      // The slot-specific server command rejects ordinary events and the
      // counseling entry point even if a stale/wrong row id reaches this UI.
      futureFunction: () => DbSpeakers.deleteCounselingSlot(
        widget.speaker.id!,
        slot,
      ),
    );
    if (ok && mounted) {
      _changed = true;
      ToastHelper.Show(context, CommonStrings.deleted);
      await _reloadSpeaker();
    }
  }

  /// Refreshes the in-dialog slot grid after a slot mutation.
  Future<void> _reloadSpeaker() async {
    final data = await ExceptionHandler.guard(
      context,
      futureFunction: () => DbSpeakers.getSpeakersForEdit(_occasionId),
    );
    if (data == null || !mounted) return;
    final fresh =
        data.speakers.where((s) => s.id == widget.speaker.id).toList();
    if (fresh.isNotEmpty) {
      setState(() => widget.speaker.events = fresh.first.events);
    }
  }


  Widget _buildHtmlParent(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isExisting
          ? SpeakersStrings.editSpeaker
          : SpeakersStrings.addSpeaker),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(CommonStrings.hide),
                value: _isHidden,
                onChanged: (v) => setState(() => _isHidden = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(labelText: SpeakersStrings.name),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _subtitleController,
                decoration:
                    InputDecoration(labelText: SpeakersStrings.roleSubtitle),
              ),
              const SizedBox(height: 16),
              Text(SpeakersStrings.avatar, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              ImageArea(
                imageUrl: _image,
                onFileSelected: (file) async {
                  try {
                    final bytes = await file.readAsBytes();
                    final compressed =
                        await ImageCompressionHelper.compress(bytes, 400);
                    final url = await DbImages.uploadImage(
                        compressed, RightsService.currentOccasionId(), null);
                    if (mounted) setState(() => _image = url);
                    return url;
                  } catch (e) {
                    AppLogger.error('Speaker avatar upload failed: $e');
                    if (mounted) {
                      ToastHelper.Show(context, CommonStrings.unexpectedError,
                          severity: ToastSeverity.NotOk);
                    }
                    return null;
                  }
                },
                onRemove: () async {
                  final imageUrl = _image;
                  if (imageUrl == null || imageUrl.isEmpty) return;
                  final confirm = await DialogHelper.showConfirmationDialog(
                    context,
                    CommonStrings.confirmRemoval,
                    SpeakersStrings.avatar,
                  );
                  if (confirm != true) return;
                  await ExceptionHandler.guardVoid(
                    context,
                    futureFunction: () => DbImages.removeImage(imageUrl),
                  );
                  if (mounted) setState(() => _image = null);
                },
              ),
              const SizedBox(height: 16),
              Text(SpeakersStrings.bio, style: theme.textTheme.labelMedium),
              EditableHtmlField(html: _description, coordinator: _htmlSave,
                owner: HtmlMediaOwner.occasion(_occasionId),
                onChanged: (html) => setState(() => _description = html)),
              const SizedBox(height: 16),
              // Counseling competence areas only matter when counseling is on (R5).
              if (FeatureService.isCounselingEnabled()) ...[
                Text(SpeakersStrings.topics, style: theme.textTheme.labelLarge),
                if (widget.topics.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('—', style: theme.textTheme.bodySmall),
                  ),
                ...widget.topics.map((t) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _selectedTopics.contains(t.id),
                      title: Text(t.title ?? ''),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selectedTopics.add(t.id!);
                        } else {
                          _selectedTopics.remove(t.id);
                        }
                      }),
                    )),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _orderController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: CommonStrings.order),
              ),
              // The counseling slot generator is gated on the counseling
              // feature (R5); an unsaved speaker has no id to attach slots to.
              if (_isExisting && FeatureService.isCounselingEnabled()) ...[
                const Divider(height: 32),
                _buildCounselingSection(theme),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async { if (await confirmHtmlDiscard(context, _htmlSave) && context.mounted) Navigator.of(context).pop(_changed); },
          child: Text(CommonStrings.storno),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(CommonStrings.save),
        ),
      ],
    );
  }

  Widget _buildCounselingSection(ThemeData theme) {
    final slots = widget.speaker.events
        .where((e) => e.isCounselingSlot)
        .toList()
      ..sort((a, b) =>
          (a.startTime ?? DateTime(0)).compareTo(b.startTime ?? DateTime(0)));
    final fmt = DateFormat.MMMd(context.locale.languageCode).add_Hm();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(SpeakersStrings.counselingSlots,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              onPressed: _addSlot,
              label: Text(SpeakersStrings.addSlot),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (slots.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text('—', style: theme.textTheme.bodySmall),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: slots.map((slot) {
              final label = slot.startTime != null
                  ? '${fmt.format(slot.startTime!)} · ${slot.occupied}/${slot.maxParticipants ?? 1}'
                  : '${slot.occupied}/${slot.maxParticipants ?? 1}';
              final full = slot.maxParticipants != null &&
                  slot.occupied >= slot.maxParticipants!;
              final chipColor = full
                  ? ThemeConfig.redColor(context)
                  : ThemeConfig.indicatorColor(context);
              final onChip = ThemeConfig.textColorForBackground(chipColor);
              return InputChip(
                label: Text(label),
                labelStyle: TextStyle(
                  color: onChip,
                  fontWeight: FontWeight.w600,
                ),
                onPressed: () => _editSlot(slot),
                onDeleted: () => _deleteSlot(slot),
                deleteIcon: const Icon(Icons.close, size: 18),
                deleteIconColor: onChip.withValues(alpha: 0.7),
                deleteButtonTooltipMessage: CommonStrings.delete,
                backgroundColor: chipColor,
                side: BorderSide(color: chipColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/speakers/admin/speaker_editor_dialog.dart';
import 'package:fstapp/components/speakers/db_speakers.dart';
import 'package:fstapp/components/speakers/speaker_avatar.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speaker_topic_model.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/theme_config.dart';

/// Admin tab: manage speakers (lecturers / counselors) and the counseling area
/// catalog. Data comes from [DbSpeakers.getSpeakersForEdit]; every mutation is
/// wrapped in [ExceptionHandler.guard] and reloads the tab on success.
class SpeakersTab extends StatefulWidget {
  const SpeakersTab({super.key});

  @override
  State<SpeakersTab> createState() => _SpeakersTabState();
}

class _SpeakersTabState extends State<SpeakersTab> {
  List<SpeakerModel> _speakers = [];
  List<SpeakerTopicModel> _topics = [];
  bool _loading = true;

  int get _occasionId => RightsService.currentOccasionId()!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await ExceptionHandler.guard(
      context,
      futureFunction: () => DbSpeakers.getSpeakersForEdit(_occasionId),
    );
    if (!mounted) return;
    setState(() {
      if (data != null) {
        _speakers = data.speakers;
        _topics = data.topics;
      }
      _loading = false;
    });
  }

  Future<void> _openSpeakerEditor(SpeakerModel speaker) async {
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) => SpeakerEditorDialog(speaker: speaker, topics: _topics),
    );
    // _save pops the saved SpeakerModel; the close button pops _changed (bool).
    // Reload on any truthy signal (decision R6b).
    if (result == true || result is SpeakerModel) await _load();
  }

  Future<void> _deleteSpeaker(SpeakerModel speaker) async {
    final confirm = await DialogHelper.showConfirmationDialog(
      context,
      CommonStrings.confirmRemoval,
      speaker.title ?? '',
    );
    if (confirm != true) return;
    final ok = await ExceptionHandler.guardVoid(
      context,
      futureFunction: () => DbSpeakers.deleteSpeaker(speaker),
    );
    if (ok && mounted) {
      ToastHelper.Show(context, CommonStrings.deleted);
      await _load();
    }
  }

  Future<void> _openTopicEditor(SpeakerTopicModel topic) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _TopicEditorDialog(topic: topic),
    );
    if (changed == true) await _load();
  }

  Future<void> _deleteTopic(SpeakerTopicModel topic) async {
    final confirm = await DialogHelper.showConfirmationDialog(
      context,
      CommonStrings.confirmRemoval,
      topic.title ?? '',
    );
    if (confirm != true) return;
    final ok = await ExceptionHandler.guardVoid(
      context,
      futureFunction: () => DbSpeakers.deleteTopic(topic),
    );
    if (ok && mounted) {
      ToastHelper.Show(context, CommonStrings.deleted);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.record_voice_over, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                SpeakersStrings.manageSpeakers,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              onPressed: () => _openSpeakerEditor(SpeakerModel()),
              label: Text(SpeakersStrings.addSpeaker),
            ),
          ],
        ),
        const Divider(height: 24),
        if (_speakers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(SpeakersStrings.manageSpeakers,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: ThemeConfig.grey700(context))),
            ),
          )
        else
          ..._speakers.map(_buildSpeakerTile),
        // The counseling areas catalog only matters when counseling is on (R5).
        if (FeatureService.isCounselingEnabled()) ...[
          const SizedBox(height: 24),
          _buildTopicsCatalog(theme),
        ],
      ],
    );
  }

  Widget _buildSpeakerTile(SpeakerModel speaker) {
    final mutedIcon = ThemeConfig.grey700(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: ThemeConfig.whiteColor(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: ThemeConfig.grey300(context)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: SpeakerAvatar(imageUrl: speaker.image, radius: 22),
        title: Text(
          speaker.title ?? '',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: speaker.isHidden ? mutedIcon : null,
          ),
        ),
        onTap: () => _openSpeakerEditor(speaker),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (speaker.isHidden)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.visibility_off, size: 18, color: mutedIcon),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: CommonStrings.edit,
              color: mutedIcon,
              onPressed: () => _openSpeakerEditor(speaker),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: CommonStrings.delete,
              color: mutedIcon,
              onPressed: () => _deleteSpeaker(speaker),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicsCatalog(ThemeData theme) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.category_outlined),
        title: Text(SpeakersStrings.manageTopics,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          ..._topics.map((topic) => ListTile(
                dense: true,
                title: Text(
                  topic.title ?? '',
                  style: topic.isHidden
                      ? TextStyle(color: ThemeConfig.grey700(context))
                      : null,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (topic.isHidden)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(Icons.visibility_off,
                            size: 18, color: ThemeConfig.grey700(context)),
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: CommonStrings.edit,
                      color: ThemeConfig.grey700(context),
                      onPressed: () => _openTopicEditor(topic),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: CommonStrings.delete,
                      color: ThemeConfig.grey700(context),
                      onPressed: () => _deleteTopic(topic),
                    ),
                  ],
                ),
              )),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add_circle_outline, size: 18),
                onPressed: () =>
                    _openTopicEditor(SpeakerTopicModel(order: _topics.length)),
                label: Text(SpeakersStrings.addTopic),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small dialog for creating/editing a counseling area (topic).
class _TopicEditorDialog extends StatefulWidget {
  final SpeakerTopicModel topic;
  const _TopicEditorDialog({required this.topic});

  @override
  State<_TopicEditorDialog> createState() => _TopicEditorDialogState();
}

class _TopicEditorDialogState extends State<_TopicEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _orderController;
  bool _isHidden = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.topic.title ?? '');
    _orderController =
        TextEditingController(text: widget.topic.order.toString());
    _isHidden = widget.topic.isHidden;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ToastHelper.Show(context, CommonStrings.fieldCannotBeEmpty,
          severity: ToastSeverity.NotOk);
      return;
    }
    final model = widget.topic
      ..title = title
      ..order = int.tryParse(_orderController.text.trim()) ?? 0
      ..isHidden = _isHidden;

    final saved = await ExceptionHandler.guard<SpeakerTopicModel>(
      context,
      futureFunction: () =>
          DbSpeakers.updateTopic(RightsService.currentOccasionId()!, model),
    );
    if (saved != null && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.topic.id == null
          ? SpeakersStrings.addTopic
          : SpeakersStrings.manageTopics),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration:
                  InputDecoration(labelText: SpeakersStrings.topicTitle),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _orderController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: CommonStrings.order),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(CommonStrings.hide),
              value: _isHidden,
              onChanged: (v) => setState(() => _isHidden = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(CommonStrings.storno),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(CommonStrings.save),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:html/parser.dart' as html;
import 'occasion_setup_due_settings.dart';
import 'occasion_setup_story.dart';
import '../../features/ticket_feature.dart';
import '../../ticket_layout/views/ticket_delivery_selector.dart';
import '../../ticket_layout/views/ticket_delivery_preview.dart';
import 'occasion_setup_strings.dart';

/// Returns the server-rendered subject/html for a detached current draft.
typedef SetupEmailPreviewLoader = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> draft);

class OccasionSetupCommunicationSettings extends StatefulWidget {
  const OccasionSetupCommunicationSettings(
      {super.key,
      required this.draft,
      required this.onChanged,
      required this.loadPreview,
      this.inheritedTone = 'formal',
      this.inheritedReplyTo});
  final Map<String, dynamic> draft;
  final SetupDraftChange onChanged;
  final SetupEmailPreviewLoader loadPreview;
  final String inheritedTone;
  final String? inheritedReplyTo;

  @override
  State<OccasionSetupCommunicationSettings> createState() =>
      _OccasionSetupCommunicationSettingsState();
}

class _OccasionSetupCommunicationSettingsState
    extends State<OccasionSetupCommunicationSettings> {
  Timer? _debounce;
  int _generation = 0;
  String? _requestedDraft;
  Map<String, dynamic>? _preview;
  bool _loading = true;
  bool _failed = false;
  String t(String key) => OccasionSetupStrings.story(key);

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant OccasionSetupCommunicationSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    final snapshot = jsonEncode(widget.draft);
    if (snapshot == _requestedDraft) return;
    _requestedDraft = snapshot;
    final generation = ++_generation;
    _debounce?.cancel();
    _loading = true;
    _failed = false;
    _preview = null;
    _debounce = Timer(
        const Duration(milliseconds: 300), () => _load(snapshot, generation));
  }

  Future<void> _load(String snapshot, int generation) async {
    try {
      final result = await widget
          .loadPreview(jsonDecode(snapshot) as Map<String, dynamic>);
      if (!mounted || generation != _generation) return;
      setState(() {
        _preview = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    super.dispose();
  }

  /// Render through the existing Flutter HTML renderer, with no executable
  /// browser document, external resources, forms, or navigable links.
  String _safePreview(String source) {
    final document = html.parse(source);
    for (final element in document.querySelectorAll(
        'script,style,iframe,object,embed,form,input,button,video,audio,source,img,svg,link,meta,base')) {
      element.remove();
    }
    for (final element in document.querySelectorAll('*')) {
      element.attributes.removeWhere((key, _) =>
          key.toString().startsWith('on') ||
          const ['href', 'src', 'srcset', 'action', 'formaction', 'style']
              .contains(key));
    }
    return document.body?.innerHtml ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final data = (widget.draft['formDraft'] as Map?)?['data'] as Map? ?? {};
    final tone = data['communication_tone'] as String? ?? widget.inheritedTone;
    final reply = widget.draft['replyTo'] as String? ??
        data['reply_to'] as String? ??
        widget.inheritedReplyTo ??
        '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        key: ValueKey('${widget.draft['id']}-reply-${widget.inheritedReplyTo}'),
        initialValue: reply,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
            labelText: t('replyTo'),
            helperText: t('replyToHelp'),
            helperMaxLines: 3),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (value) => (value ?? '').trim().isEmpty
            ? null
            : FormBuilderValidators.email(errorText: t('invalidEmail'))(
                value!.trim()),
        onChanged: (value) => widget.onChanged((next) {
          next['replyToMode'] = value.trim().isEmpty ? 'inherit' : 'custom';
          next['replyTo'] = value;
          final form = next['formDraft'] as Map;
          final meta = Map<String, dynamic>.from(form['data'] as Map? ?? {});
          if (value.trim().isEmpty) {
            meta.remove('reply_to');
          } else {
            meta['reply_to'] = value.trim();
          }
          form['data'] = meta;
        }),
      ),
      const SizedBox(height: 24),
      Text(t('addressParticipants'),
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final value in ['formal', 'informal'])
          ChoiceChip(
              label: Text(t(value)),
              selected: tone == value,
              onSelected: (_) => widget.onChanged((next) {
                    next['communicationTone'] = value;
                    final form = next['formDraft'] as Map;
                    form['data'] = {
                      ...?form['data'] as Map?,
                      'communication_tone': value
                    };
                  })),
      ]),
      if (!data.containsKey('communication_tone')) Text(t('inheritedSetting')),
      const SizedBox(height: 24),
      if (OccasionSetupStory.tickets(widget.draft)) ...[
        TicketDeliverySelector(
            value: TicketDeliveryMode.parse(
                (widget.draft['ticketDraft'] as Map?)?['delivery_mode'],
                present: (widget.draft['ticketDraft'] as Map?)
                        ?.containsKey('delivery_mode') ??
                    false),
            enabled:
                (widget.draft['ticketDraft'] as Map?)?['is_enabled'] != false,
            onChanged: (mode) => widget.onChanged((next) {
                  next['ticketDraft'] = {
                    ...?next['ticketDraft'] as Map?,
                    'code': 'ticket',
                    'is_enabled':
                        (next['ticketDraft'] as Map?)?['is_enabled'] ?? true,
                    'delivery_mode': mode.value
                  };
                })),
        const SizedBox(height: 24),
        if ((widget.draft['ticketDraft'] as Map?)?['is_enabled'] != false)
          TicketDeliveryPreview(
              title: widget.draft['title'] as String?,
              revision: jsonEncode({
                'id': widget.draft['id'],
                'sourceId': widget.draft['sourceId'],
                'copyEmails': widget.draft['copyEmails'],
              }),
              mode: TicketDeliveryMode.parse(
                  (widget.draft['ticketDraft'] as Map?)?['delivery_mode'],
                  present: (widget.draft['ticketDraft'] as Map?)
                          ?.containsKey('delivery_mode') ??
                      false),
              load: () => widget.loadPreview({
                    ...jsonDecode(jsonEncode(widget.draft))
                        as Map<String, dynamic>,
                    'previewMessageType': 'order_tickets',
                  })),
        const SizedBox(height: 24),
      ],
      Text(t('confirmationPreview'),
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (_loading) const LinearProgressIndicator(),
      if (_failed) ...[
        Text(t('previewFailed')),
        TextButton(
            onPressed: () => setState(() {
                  _requestedDraft = null;
                  _schedule();
                }),
            child: Text(OccasionSetupStrings.retry)),
      ],
      if (_preview != null) ...[
        Text('${_preview!['subject'] ?? ''}',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8)),
            child: HtmlWidget(_safePreview('${_preview!['html'] ?? ''}'),
                onTapUrl: (_) => true)),
        if (_preview!['has_custom_template'] == true)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(t('customTemplateToneHelp'))),
      ],
    ]);
  }
}

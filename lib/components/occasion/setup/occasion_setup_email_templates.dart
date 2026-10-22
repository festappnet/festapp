import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:festapp_core/email_templates.dart';
import '../../email_templates/db_email_templates.dart';
import '../../email_templates/email_preview_examples.dart';
import '../../email_templates/email_template_model.dart';
import '../../email_templates/email_templates_strings.dart';
import '../../email_templates/views/email_template_card.dart';
import '../../email_templates/views/email_templates_settings_page.dart';
import 'occasion_setup_email_preview.dart';

/// Reuses the standard authoring UI; writes remain in the private setup draft.
class OccasionSetupEmailTemplates extends StatefulWidget {
  const OccasionSetupEmailTemplates(
      {super.key,
      required this.draft,
      required this.loadPreview,
      required this.onChanged});
  final Map<String, dynamic> draft;
  final SetupEmailPreviewLoader loadPreview;
  final ValueChanged<Map<String, dynamic>> onChanged;
  @override
  State<OccasionSetupEmailTemplates> createState() =>
      _OccasionSetupEmailTemplatesState();
}

class _OccasionSetupEmailTemplatesState
    extends State<OccasionSetupEmailTemplates> {
  Map<String, dynamic>? _catalog;
  bool _loading = false;
  bool _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OccasionSetupEmailTemplates oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft['sourceId'] != widget.draft['sourceId'] ||
        oldWidget.draft['copyEmails'] != widget.draft['copyEmails']) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final result = await widget.loadPreview(widget.draft);
      if (!mounted || generation != _generation) return;
      if (result['emailTemplates'] is! List || result['emailScope'] is! Map)
        throw StateError('Email templates unavailable');
      setState(() {
        _catalog = result;
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() {
          _failed = true;
          _loading = false;
        });
    }
  }

  Future<void> _edit(Map entry) async {
    final catalog = _catalog!;
    final scope = EmailTemplatesResponse.fromJson(
        {...Map<String, dynamic>.from(catalog['emailScope']), 'templates': []});
    final template = EmailTemplateModel.fromJson({
      ...Map<String, dynamic>.from(entry['template']),
      'code': entry['code']
    });
    final code = entry['code'] as String;
    final preview = Map<String, dynamic>.from(catalog['previewContext'] ?? {});
    final deadline = DateTime.tryParse(preview['deadline'] ?? '');
    Future<void> persist(Map<String, dynamic>? value) async {
      final overrides = Map<String, dynamic>.from(
          widget.draft['emailTemplateOverrides'] as Map? ?? {});
      if (value == null) {
        overrides.remove(code);
      } else {
        overrides[code] = value;
      }
      widget.onChanged({'emailTemplateOverrides': overrides});
      // The owner flushes its revision-checked draft before reading the catalog.
      await widget
          .loadPreview({...widget.draft, 'emailTemplateOverrides': overrides});
    }

    await showDialog<void>(
        context: context,
        builder: (_) => EmailTemplateSettingsPage(
              template: template,
              emailTemplatesResponse: scope,
              saveTemplate: (edited) => persist(
                  {'subject': edited.subject ?? '', 'html': edited.html ?? ''}),
              resetTemplate:
                  entry['customized'] == true ? () => persist(null) : null,
              authoringContextLoader: () async =>
                  EmailAuthoringContext.fromJson(
                      Map<String, dynamic>.from(catalog['authoringContext'])),
              previewExamplesLoader: () async => EmailPreviewExamples.fromJson(
                  jsonDecode(await rootBundle.loadString(
                      'assets/email_templates/preview_examples.json')),
                  context: EmailPreviewContext(
                    occasionTitle: preview['title'],
                    ticketsEnabled: preview['ticketsEnabled'],
                    deadline: deadline != null
                        ? DateFormat('d. M. y').format(deadline.toLocal())
                        : null,
                    products: [
                      for (final p in (preview['products'] as List? ?? [])
                          .whereType<Map>())
                        if (p['price'] is num)
                          EmailPreviewProduct(
                              title: '${p['title'] ?? ''}',
                              typeTitle: '${p['type_title'] ?? ''}',
                              price: (p['price'] as num).toDouble(),
                              currency: '${p['currency_code'] ?? 'CZK'}')
                    ],
                  )),
            ));
    if (mounted) await _load();
  }

  String _contextTitle(Map entry) {
    if (entry['customized'] == true) return 'Vlastní návrh';
    final template = entry['template'] as Map;
    if (template['occasion'] != null) return 'Převzatá šablona';
    final scope = _catalog!['emailScope'] as Map;
    if (template['unit'] != null) return '${scope['unit']['title'] ?? ''}';
    if (template['organization'] != null)
      return '${scope['organization']['title'] ?? ''}';
    return '';
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(EmailTemplatesStrings.title,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
            'E-maily můžete upravit přímo zde. Změny se uloží do konceptu a použijí se po vytvoření akce.'),
        const SizedBox(height: 16),
        if (_loading) const LinearProgressIndicator(),
        if (_failed) ...[
          const Text('Šablony e-mailů se nepodařilo načíst.'),
          TextButton(onPressed: _load, child: const Text('Zkusit znovu')),
        ],
        if (_catalog != null)
          LayoutBuilder(builder: (context, constraints) {
            final columns = (constraints.maxWidth / 280).floor().clamp(1, 5);
            final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
            final height =
                220 * MediaQuery.textScalerOf(context).scale(14) / 14;
            return Wrap(spacing: 16, runSpacing: 16, children: [
              for (final entry
                  in (_catalog!['emailTemplates'] as List).whereType<Map>())
                SizedBox(
                    width: width,
                    height: height,
                    child: EmailTemplateCard(
                      template: EmailTemplateModel.fromJson({
                        ...Map<String, dynamic>.from(entry['template']),
                        'code': entry['code']
                      }),
                      contextTitle: _contextTitle(entry),
                      onEdit: _loading ? () {} : () => _edit(entry),
                    )),
            ]);
          }),
      ]);
}

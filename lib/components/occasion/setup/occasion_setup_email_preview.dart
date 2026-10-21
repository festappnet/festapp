import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/parser.dart' as html;
import 'occasion_setup_strings.dart';

/// Returns the server-rendered subject/html for a detached current draft.
typedef SetupEmailPreviewLoader = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> draft);

class OccasionSetupEmailPreview extends StatefulWidget {
  const OccasionSetupEmailPreview({
    super.key,
    required this.draft,
    required this.loadPreview,
  });
  final Map<String, dynamic> draft;
  final SetupEmailPreviewLoader loadPreview;

  @override
  State<OccasionSetupEmailPreview> createState() =>
      _OccasionSetupEmailPreviewState();
}

class _OccasionSetupEmailPreviewState extends State<OccasionSetupEmailPreview> {
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
  void didUpdateWidget(covariant OccasionSetupEmailPreview oldWidget) {
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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

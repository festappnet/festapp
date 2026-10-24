import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/forms/views/form_public_link.dart';
import 'occasion_setup_strings.dart';

class OccasionSetupFormLink extends StatefulWidget {
  final String draftId, title, value;
  final bool automatic;
  final void Function(String, bool) onChanged;
  const OccasionSetupFormLink(
      {super.key,
      required this.draftId,
      required this.title,
      required this.value,
      required this.automatic,
      required this.onChanged});
  @override
  State<OccasionSetupFormLink> createState() => _OccasionSetupFormLinkState();
}

class _OccasionSetupFormLinkState extends State<OccasionSetupFormLink> {
  bool _editing = false, _checking = false;
  bool? _available;
  String? _error;
  Timer? _timer;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.value.isEmpty) _schedule();
  }

  @override
  void didUpdateWidget(OccasionSetupFormLink old) {
    super.didUpdateWidget(old);
    if ((old.title != widget.title && widget.automatic) ||
        old.value != widget.value) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _generation++;
    _timer = Timer(const Duration(milliseconds: 400), _check);
  }

  Future<void> _check() async {
    final token = ++_generation;
    if (!mounted) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final row = Map<String, dynamic>.from(await Supabase.instance.client
          .rpc('suggest_occasion_setup_form_link', params: {
        'p_id': widget.draftId,
        'p_title': widget.title,
        'p_requested_link': _editing ? widget.value : null
      }));
      if (!mounted || token != _generation) return;
      if (widget.automatic && !_editing) {
        final next = row['suggestion'] as String;
        if (next != widget.value) widget.onChanged(next, true);
      }
      setState(() => _available = row['available'] as bool?);
    } catch (_) {
      if (mounted && token == _generation)
        setState(() => _error = OccasionSetupStrings.story('linkCheckFailed'));
    } finally {
      if (mounted && token == _generation) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text(OccasionSetupStrings.story('formLink')),
              ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width - 96),
                  child: SelectableText(publicLinkUrl(widget.value))),
              TextButton(
                  onPressed: () => setState(() {
                        _editing = !_editing;
                        if (_editing) _schedule();
                      }),
                  child: Text(OccasionSetupStrings.story('editLink'))),
            ]),
        Text(OccasionSetupStrings.story('linkAfterCreation'),
            style: Theme.of(context).textTheme.bodySmall),
        if (_editing) ...[
          TextFormField(
              key: ValueKey('${widget.draftId}-slug'),
              initialValue: widget.value,
              decoration: InputDecoration(
                  labelText: OccasionSetupStrings.story('formLink'),
                  errorText: !isValidPublicSlug(widget.value, allowEmpty: true)
                      ? OccasionSetupStrings.story('invalidLink')
                      : _available == false
                          ? OccasionSetupStrings.story('linkTaken')
                          : null),
              onChanged: (value) {
                widget.onChanged(value, false);
                _schedule();
              }),
          if (_checking) const LinearProgressIndicator(),
          if (_available == true)
            Text(OccasionSetupStrings.story('linkAvailable')),
          if (_error != null)
            TextButton(onPressed: _check, child: Text(_error!)),
          TextButton(
              onPressed: () {
                widget.onChanged('', true);
                setState(() => _editing = false);
                _schedule();
              },
              child: Text(OccasionSetupStrings.story('suggestLink'))),
        ],
      ]);
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/forms/views/form_public_link.dart';
import 'occasion_setup_details_strings.dart';

typedef SuggestSetupLink = Future<Map<String, dynamic>> Function(
    String title, String? requested);

/// Availability is only a preview. The canonical allocator checks again during
/// finalization and can choose the next suffix for an automatic suggestion.
class OccasionSetupFormLink extends StatefulWidget {
  final String draftId, title, value;
  final bool automatic;
  final void Function(String value, bool automatic) onChanged;
  final SuggestSetupLink? suggest;
  final ValueChanged<bool?>? onValidityChanged;
  const OccasionSetupFormLink(
      {super.key,
      required this.draftId,
      required this.title,
      required this.value,
      required this.automatic,
      required this.onChanged,
      this.suggest,
      this.onValidityChanged});
  @override
  State<OccasionSetupFormLink> createState() => _OccasionSetupFormLinkState();
}

class _OccasionSetupFormLinkState extends State<OccasionSetupFormLink> {
  late final _controller = TextEditingController(text: widget.value);
  Timer? _debounce;
  int _request = 0;
  bool _checking = false;
  bool _forceSuggestion = false;
  bool? _available;
  String? _error;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(OccasionSetupFormLink old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text) _controller.text = widget.value;
    if (old.title != widget.title && widget.automatic) _forceSuggestion = true;
    if (old.title != widget.title ||
        old.value != widget.value ||
        old.automatic != widget.automatic) _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _request++;
    _debounce = Timer(const Duration(milliseconds: 450), _check);
  }

  Future<void> _check() async {
    final token = ++_request;
    final value = _controller.text;
    final force = _forceSuggestion;
    if (!isValidPublicSlug(value, allowEmpty: true)) {
      widget.onValidityChanged?.call(false);
      setState(() {
        _available = false;
        _checking = false;
        _error = OccasionSetupDetailsStrings.text('invalidLink');
      });
      return;
    }
    widget.onValidityChanged?.call(null);
    setState(() {
      _checking = true;
      _error = null;
      _available = null;
    });
    try {
      final result = widget.suggest != null
          ? await widget.suggest!(widget.title, value)
          : Map<String, dynamic>.from(await Supabase.instance.client
              .rpc('suggest_occasion_setup_form_link', params: {
              'p_id': widget.draftId,
              'p_title': widget.title,
              'p_requested_link': value,
            }));
      if (!mounted || token != _request) return;
      if (widget.automatic) {
        final next = !force && result['available'] == true && value.isNotEmpty
            ? value
            : result['suggestion'] as String;
        _controller.text = next;
        _available = true;
        _forceSuggestion = false;
        if (next != widget.value) widget.onChanged(next, true);
      } else {
        _available = value.isEmpty ? null : result['available'] == true;
      }
      widget.onValidityChanged?.call(_available);
    } catch (_) {
      if (mounted && token == _request)
        _error = OccasionSetupDetailsStrings.text('linkCheckFailed');
    } finally {
      if (mounted && token == _request) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _request++;
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: OccasionSetupDetailsStrings.text('formAddress'),
            helperText: OccasionSetupDetailsStrings.text('linkPreviewHint'),
            helperMaxLines: 3,
            errorText: _error ??
                (_available == false
                    ? OccasionSetupDetailsStrings.text('linkTaken')
                    : null),
          ),
          onChanged: (value) {
            setState(() {
              _available = null;
              _error = null;
            });
            widget.onValidityChanged?.call(null);
            widget.onChanged(value, false);
            _schedule();
          },
        ),
        const SizedBox(height: 8),
        if (_checking) const LinearProgressIndicator(),
        if (_available == true)
          Text(OccasionSetupDetailsStrings.text('linkAvailable')),
        TextButton.icon(
          onPressed: _checking
              ? null
              : () {
                  _forceSuggestion = true;
                  widget.onValidityChanged?.call(null);
                  widget.onChanged('', true);
                  _controller.clear();
                  _schedule();
                },
          icon: const Icon(Icons.auto_fix_high),
          label: Text(OccasionSetupDetailsStrings.text('suggestLink')),
        ),
        PublicLink(link: _controller.text),
      ]);
}

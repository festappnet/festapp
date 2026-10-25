import 'package:material_ui/material_ui.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/organization/organization_admin_guard.dart';
import 'package:fstapp/components/forms/widgets_view/organization_identity_footer.dart';
import 'db_unit_verification.dart';
import 'unit_legal_profile.dart';
import 'verification_strings.dart';

class VerificationQueue extends StatefulWidget {
  final int organizationId;
  const VerificationQueue({super.key, required this.organizationId});
  @override
  State<VerificationQueue> createState() => _VerificationQueueState();
}

class _VerificationQueueState extends State<VerificationQueue> {
  final _db = DbUnitVerification();
  String _status = 'pending';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _cursor;
  String t(String key) => VerificationStrings.text(key);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _db.queue(widget.organizationId, _status,
          cursor: more ? _cursor : null);
      if (!mounted) return;
      setState(() {
        final rows =
            (result['items'] as List).map((v) => Map<String, dynamic>.from(v));
        _items = more ? [..._items, ...rows] : rows.toList();
        _cursor = result['nextCursor'] == null
            ? null
            : Map<String, dynamic>.from(result['nextCursor']);
      });
    } catch (_) {
      if (mounted) setState(() => _error = t('failed'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(int unit) async {
    await showDialog<void>(
        context: context,
        builder: (context) =>
            UnitVerificationReviewDialog(unitId: unit, db: _db));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => OrganizationAdminGuard(
      targetOrganizationId: widget.organizationId,
      builder: (context, _) => Scaffold(
          appBar: AppBar(title: Text(t('queue'))),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Wrap(spacing: 8, children: [
              for (final status in ['pending', 'verified'])
                ChoiceChip(
                    label: Text(t(status)),
                    selected: _status == status,
                    onSelected: _loading
                        ? null
                        : (_) {
                            setState(() => _status = status);
                            _load();
                          })
            ]),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(_error!),
              TextButton(onPressed: () => _load(), child: Text(t('retry')))
            ],
            if (!_loading && _items.isEmpty && _error == null)
              Padding(
                  padding: const EdgeInsets.all(24), child: Text(t('empty'))),
            for (final row in _items)
              ListTile(
                  title: Text(row['legalName'] as String? ?? ''),
                  subtitle: Text(
                      '${row['unitTitle'] ?? '${t('unit')} ${row['unitId']}'} · ${row['registrationNumber'] ?? ''}\n${row['submittedAt'] ?? ''}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _review(row['unitId'] as int)),
            if (_cursor != null)
              TextButton(
                  onPressed: _loading ? null : () => _load(more: true),
                  child: Text(t('more'))),
          ])));
}

class UnitVerificationReviewDialog extends StatefulWidget {
  final int unitId;
  final DbUnitVerification db;
  const UnitVerificationReviewDialog(
      {super.key, required this.unitId, required this.db});
  @override
  State<UnitVerificationReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<UnitVerificationReviewDialog> {
  final _feedback = TextEditingController(),
      _note = TextEditingController(),
      _source = TextEditingController();
  final _focus = {
    for (final key in ['source', 'feedback', 'note']) key: FocusNode()
  };
  final _anchors = {
    for (final key in ['source', 'feedback', 'note']) key: GlobalKey()
  };
  final Map<String, String> _fieldErrors = {};
  String? _decision;
  UnitLegalProfile? _profile;
  bool _busy = false;
  String? _message;
  bool _canRetry = false;
  String t(String k) => VerificationStrings.text(k);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final node in _focus.values) node.dispose();
    _feedback.dispose();
    _note.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _message = null;
      _canRetry = false;
    });
    try {
      final p = await widget.db.get(widget.unitId);
      if (mounted)
        setState(() {
          if (_profile == null) {
            _feedback.text = p.feedback ?? '';
            _note.text = p.note ?? '';
            _source.text = p.source ?? '';
          }
          _profile = p;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _message = t('failed');
          _canRetry = true;
        });
    }
  }

  Map<String, TextEditingController> get _inputs => {
        'source': _source,
        'feedback': _feedback,
        'note': _note,
      };

  String? _errorFor(String field) {
    final text = _inputs[field]!.text;
    if (text.runes.length > (field == 'source' ? 2000 : 4000)) {
      return t(field == 'source' ? 'sourceTooLong' : 'reviewTextTooLong');
    }
    if (field == 'source' && _decision == 'approve' && text.trim().isEmpty) {
      return t('sourceRequired');
    }
    if (field == 'feedback' &&
        ['reject', 'revoke'].contains(_decision) &&
        text.trim().isEmpty) {
      return t('feedbackRequired');
    }
    return null;
  }

  void _focusFirstError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _fieldErrors.isEmpty) return;
      final field =
          _inputs.keys.firstWhere((key) => _fieldErrors.containsKey(key));
      _focus[field]!.requestFocus();
      final target = _anchors[field]!.currentContext;
      if (target != null) Scrollable.ensureVisible(target, alignment: 0.5);
    });
  }

  Future<void> _decide(String decision) async {
    if (_busy || _profile == null) return;
    setState(() {
      _decision = decision;
      _message = null;
      _canRetry = false;
      _fieldErrors.clear();
      for (final field in _inputs.keys) {
        final error = _errorFor(field);
        if (error != null) _fieldErrors[field] = error;
      }
    });
    if (_fieldErrors.isNotEmpty) {
      _focusFirstError();
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _canRetry = false;
    });
    try {
      final result = await widget.db.review(_profile!, decision,
          feedback: _feedback.text, note: _note.text, source: _source.text);
      if (!mounted) return;
      if (result.code == 200) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _profile = result.profile ?? _profile;
        if (result.code == 409) {
          _message = t('conflict');
          _canRetry = true;
        } else {
          for (final error in result.fieldErrors.entries) {
            final field = switch (error.key) {
              'reviewSource' => 'source',
              'feedbackToApplicant' => 'feedback',
              'reviewNote' => 'note',
              _ => null,
            };
            if (field != null) {
              _fieldErrors[field] = error.value == 'REQUIRED'
                  ? t(field == 'source' ? 'sourceRequired' : 'feedbackRequired')
                  : error.value == 'TOO_LONG'
                      ? t(field == 'source'
                          ? 'sourceTooLong'
                          : 'reviewTextTooLong')
                      : t('invalid');
            }
          }
          if (result.fieldErrors.containsKey('review')) {
            for (final field in _inputs.keys) {
              final error = _errorFor(field);
              if (error != null) _fieldErrors[field] = error;
            }
          }
          if (_fieldErrors.isEmpty ||
              result.fieldErrors.keys.any((key) => ![
                    'reviewSource',
                    'feedbackToApplicant',
                    'reviewNote',
                    'review'
                  ].contains(key))) {
            _message = t('invalid');
            _canRetry = false;
          }
        }
      });
      if (result.code == 409) {
        await _load();
        if (mounted)
          setState(() {
            _message = t('conflict');
            _canRetry = true;
          });
      } else {
        _focusFirstError();
      }
    } catch (_) {
      await _load();
      if (mounted)
        setState(() {
          _message = t('uncertain');
          _canRetry = true;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AppDialog(
          dismissible: !_busy,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppDialogHeader(
                                title: Text(
                                    _profile?.details['legalName'] as String? ??
                                        t('queue')),
                                closeEnabled: !_busy),
                            if (_profile == null && _message == null)
                              const LinearProgressIndicator(),
                            if (_message != null) ...[
                              Text(_message!),
                              if (_canRetry)
                                TextButton(
                                    onPressed: _busy ? null : _load,
                                    child: Text(t('retry')))
                            ],
                            if (_profile != null) ...[
                              Text(
                                  '${t(_profile!.status)} · ${t('revision')} ${_profile!.revision}'),
                              OrganizationIdentityDetails(
                                  details: _profile!.details),
                              const SizedBox(height: 16),
                              Text(t('reviewNotice')),
                              for (final entry in _inputs.entries)
                                Padding(
                                    key: _anchors[entry.key],
                                    padding: const EdgeInsets.only(top: 16),
                                    child: TextField(
                                        key: ValueKey(
                                            'verification-review-${entry.key}'),
                                        controller: entry.value,
                                        focusNode: _focus[entry.key],
                                        enabled: !_busy,
                                        minLines: 2,
                                        maxLines: 4,
                                        onChanged: (_) => setState(() {
                                              _fieldErrors.remove(entry.key);
                                              final error =
                                                  _errorFor(entry.key);
                                              if (error != null)
                                                _fieldErrors[entry.key] = error;
                                            }),
                                        decoration: InputDecoration(
                                            labelText: t(switch (entry.key) {
                                              'source' => 'sourceRequiredLabel',
                                              'feedback' =>
                                                'feedbackRequiredLabel',
                                              _ => 'noteOptionalLabel',
                                            }),
                                            helperText: entry.key == 'note'
                                                ? null
                                                : t(entry.key == 'source'
                                                    ? 'sourceHelp'
                                                    : 'feedbackHelp'),
                                            helperMaxLines: 8,
                                            errorText: _fieldErrors[entry.key],
                                            errorMaxLines: 4,
                                            counterText:
                                                '${entry.value.text.runes.length}/${entry.key == 'source' ? 2000 : 4000}',
                                            border:
                                                const OutlineInputBorder()))),
                              if (_busy) Text(t('saving')),
                              const SizedBox(height: 16),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final action
                                    in _profile!.status == 'pending'
                                        ? ['approve', 'reject']
                                        : _profile!.status == 'verified'
                                            ? ['revoke']
                                            : <String>[])
                                  OutlinedButton(
                                      onPressed:
                                          _busy ? null : () => _decide(action),
                                      child: Text(t(action))),
                              ]),
                            ],
                          ]))))));
}

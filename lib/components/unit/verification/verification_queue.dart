import 'package:flutter/material.dart';
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
        builder: (context) => _ReviewDialog(unitId: unit, db: _db));
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

class _ReviewDialog extends StatefulWidget {
  final int unitId;
  final DbUnitVerification db;
  const _ReviewDialog({required this.unitId, required this.db});
  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _feedback = TextEditingController(),
      _note = TextEditingController(),
      _source = TextEditingController();
  UnitLegalProfile? _profile;
  bool _busy = false;
  String? _message;
  String t(String k) => VerificationStrings.text(k);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _feedback.dispose();
    _note.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
      if (mounted) setState(() => _message = t('failed'));
    }
  }

  Future<void> _decide(String decision) async {
    if (_busy || _profile == null) return;
    if ((decision == 'approve' ? _source : _feedback).text.trim().isEmpty) {
      setState(() => _message = t('required'));
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
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
        _message = t(result.code == 409 ? 'conflict' : 'invalid');
      });
      if (result.code == 409) await _load();
    } catch (_) {
      await _load();
      if (mounted) setState(() => _message = t('uncertain'));
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
                              for (final entry in {
                                'feedback': _feedback,
                                'note': _note,
                                'source': _source
                              }.entries)
                                Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: TextField(
                                        controller: entry.value,
                                        enabled: !_busy,
                                        minLines: 2,
                                        maxLines: 4,
                                        decoration: InputDecoration(
                                            labelText: t(entry.key),
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

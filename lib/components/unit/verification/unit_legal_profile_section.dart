import 'package:fstapp/services/connectivity_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/forms/widgets_view/organization_identity_footer.dart';
import 'db_unit_verification.dart';
import 'unit_legal_profile.dart';
import 'verification_strings.dart';

class UnitLegalProfileSection extends StatefulWidget {
  final int unitId;
  final bool canEdit;
  final DbUnitVerification? service;
  const UnitLegalProfileSection(
      {super.key, required this.unitId, required this.canEdit, this.service});
  @override
  State<UnitLegalProfileSection> createState() =>
      _UnitLegalProfileSectionState();
}

class _UnitLegalProfileSectionState extends State<UnitLegalProfileSection> {
  final _form = GlobalKey<FormState>();
  final _controllers = {
    for (final key in [
      'legalName',
      'countryCode',
      'registrationNumber',
      'vatId',
      'street',
      'city',
      'postalCode',
      'contactEmail',
      'phone',
      'website'
    ])
      key: TextEditingController()
  };
  late final DbUnitVerification _db = widget.service ?? DbUnitVerification();
  UnitLegalProfile? _profile;
  bool _loading = true, _busy = false, _dirty = false;
  String? _message;
  Map<String, String> _errors = {};
  String t(String key) => VerificationStrings.text(key);
  @override
  void initState() {
    super.initState();
    _load();
    ConnectivityService.isOfflineNotifier.addListener(_connectionChanged);
  }

  void _connectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ConnectivityService.isOfflineNotifier.removeListener(_connectionChanged);
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  void _fill(UnitLegalProfile p) {
    for (final e in _controllers.entries)
      e.value.text = (['street', 'city', 'postalCode'].contains(e.key)
              ? (p.details['address'] as Map)[e.key]
              : p.details[e.key]) as String? ??
          '';
    _dirty = false;
  }

  Future<void> _load({bool preserve = false}) async {
    try {
      final p = await _db.get(widget.unitId);
      if (!mounted) return;
      setState(() {
        _profile = p;
        if (!preserve) _fill(p);
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _message = t('failed');
        });
    }
  }

  Map<String, dynamic> get _draft => {
        for (final key in UnitLegalProfile.fields)
          key: key == 'address'
              ? {
                  for (final k in ['street', 'city', 'postalCode'])
                    k: _controllers[k]!.text
                }
              : _controllers[key]!.text
      };
  Future<void> _write(bool submit) async {
    if (_busy ||
        _profile == null ||
        ConnectivityService.isOfflineNotifier.value) return;
    if (!submit &&
        _dirty &&
        ['pending', 'verified'].contains(_profile!.status)) {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (context) =>
              AppAlertDialog(title: Text(t('confirmChange')), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(t('cancel'))),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(t('save')))
              ]));
      if (confirm != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _errors = {};
      _message = null;
    });
    try {
      final result = submit
          ? await _db.submit(_profile!)
          : await _db.save(_profile!, _draft);
      if (!mounted) return;
      setState(() {
        if (result.profile != null) _profile = result.profile;
        if (result.code == 200) {
          _fill(_profile!);
          _message = t('saved');
        } else if (result.code == 409) {
          _message = t('conflict');
        } else {
          _errors = result.fieldErrors;
          _message = t('invalid');
        }
      });
      _form.currentState?.validate();
    } catch (_) {
      await _load(preserve: true);
      if (mounted) setState(() => _message = t('uncertain'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final offline = ConnectivityService.isOfflineNotifier.value;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Form(
            key: _form,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t('title'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Text(t('publicNotice')),
                  if (offline) Text(t('offline')),
                  if (_loading) const LinearProgressIndicator(),
                  if (_message != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_message!, semanticsLabel: _message)),
                  if (p == null && !_loading)
                    TextButton(
                        onPressed: () => _load(), child: Text(t('retry'))),
                  if (p != null) ...[
                    const SizedBox(height: 16),
                    Text('${t(p.status)} · ${t('revision')} ${p.revision}'),
                    if (p.status == 'verified' && p.verifiedAt != null)
                      Text('${t('verified')}: ${p.verifiedAt}'),
                    if (p.submittedAt != null)
                      Text('${t('submittedAt')}: ${p.submittedAt}'),
                    if (p.feedback?.isNotEmpty == true) Text(p.feedback!),
                    if (!widget.canEdit) Text(t('noPermission')),
                    for (final entry in _controllers.entries)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: TextFormField(
                            controller: entry.value,
                            enabled: widget.canEdit && !_busy,
                            keyboardType: entry.key == 'contactEmail'
                                ? TextInputType.emailAddress
                                : entry.key == 'website'
                                    ? TextInputType.url
                                    : entry.key == 'phone'
                                        ? TextInputType.phone
                                        : TextInputType.text,
                            decoration: InputDecoration(
                                labelText: t(entry.key),
                                border: const OutlineInputBorder()),
                            validator: (_) => _errors.containsKey(entry.key) ||
                                    _errors.containsKey('address.${entry.key}')
                                ? t('invalid')
                                : null,
                            onChanged: (_) => setState(() {
                              _errors.remove(entry.key);
                              _errors.remove('address.${entry.key}');
                              _dirty =
                                  jsonEncode(_draft) != jsonEncode(p.details);
                            }),
                          )),
                    if (_dirty && ['pending', 'verified'].contains(p.status))
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(t('changeWarning'))),
                    if (_dirty)
                      Text(t('saveFirst'))
                    else if (!p.complete)
                      Text(t('completeFirst')),
                    if (_busy) Text(t('saving')),
                    const SizedBox(height: 16),
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      TextButton(
                          onPressed: () =>
                              showOrganizationDetails(context, _draft),
                          child: Text(t('preview'))),
                      if (widget.canEdit)
                        OutlinedButton(
                            onPressed:
                                _busy || offline ? null : () => _write(false),
                            child: Text(t('save'))),
                      if (widget.canEdit &&
                          !['pending', 'verified'].contains(p.status))
                        FilledButton(
                            onPressed: _busy || offline || _dirty || !p.complete
                                ? null
                                : () => _write(true),
                            child: Text(t('submit'))),
                      TextButton(
                          onPressed: _busy ? null : () => _load(),
                          child: Text(t('reload'))),
                    ]),
                  ],
                ])));
  }
}

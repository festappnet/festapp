import 'package:fstapp/services/connectivity_service.dart';
import 'dart:convert';
import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'ares_lookup_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/forms/widgets_view/organization_identity_footer.dart';
import 'db_unit_verification.dart';
import 'unit_legal_profile.dart';
import 'verification_strings.dart';

class UnitLegalProfileSection extends StatefulWidget {
  final int unitId;
  final bool canEdit;
  final DbUnitVerification? service;
  final AresLookupService? aresService;
  final VoidCallback? onBack;
  const UnitLegalProfileSection(
      {super.key,
      required this.unitId,
      required this.canEdit,
      this.service,
      this.aresService,
      this.onBack});
  @override
  State<UnitLegalProfileSection> createState() =>
      _UnitLegalProfileSectionState();
}

class _UnitLegalProfileSectionState extends State<UnitLegalProfileSection>
    with WidgetsBindingObserver {
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
  late final AresLookupService _ares =
      widget.aresService ?? AresLookupService();
  UnitLegalProfile? _profile;
  bool _lookingUp = false, _allowPop = false, _confirming = false;
  String? _aresError, _aresNotice;
  String _baseline = '';
  bool _selectedOtherCountry = false;
  static const _legalFields = [
    'legalName',
    'countryCode',
    'registrationNumber',
    'vatId',
    'street',
    'city',
    'postalCode'
  ];
  bool _loading = true, _busy = false, _dirty = false;
  String? _message;
  Map<String, String> _errors = {};
  String t(String key) => VerificationStrings.text(key);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    ConnectivityService.isOfflineNotifier.addListener(_connectionChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        !_dirty &&
        !_busy &&
        !_lookingUp &&
        !_loading &&
        !ConnectivityService.isOfflineNotifier.value) {
      _reload();
    }
  }

  void _connectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (p.revision == 0 && _controllers['countryCode']!.text.trim().isEmpty) {
      _controllers['countryCode']!.text = 'CZ';
    }
    _selectedOtherCountry = !['CZ', 'SK']
        .contains(_controllers['countryCode']!.text.trim().toUpperCase());
    _baseline = jsonEncode(_draft);
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
        _lookingUp ||
        !widget.canEdit ||
        _profile == null ||
        ConnectivityService.isOfflineNotifier.value) return;
    if (!submit &&
        _dirty &&
        ['pending', 'verified'].contains(_profile!.status)) {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AppAlertDialog(
                  onClose: () => Navigator.pop(context, false),
                  title: Text(t('confirmChange')),
                  actions: [
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

  Future<bool> _confirmDiscard({bool navigation = false}) async {
    if (_busy || _lookingUp || _confirming) return false;
    if (!_dirty) return true;
    _confirming = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        onClose: () => Navigator.pop(context, false),
        title: Text(t('discardTitle')),
        content: Text(t('discardDescription')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('discard'))),
        ],
      ),
    );
    _confirming = false;
    if (!mounted || confirmed != true) return false;
    if (navigation) setState(() => _allowPop = true);
    return true;
  }

  Future<void> _reload() async {
    if (!await _confirmDiscard() || !mounted) return;
    setState(() {
      _loading = true;
      _message = null;
      _aresError = null;
      _aresNotice = null;
    });
    await _load();
  }

  String get _legalSnapshot => jsonEncode({
        for (final key in _legalFields) key: _controllers[key]!.text,
      });

  Future<void> _lookup() async {
    if (_lookingUp ||
        _busy ||
        !widget.canEdit ||
        ConnectivityService.isOfflineNotifier.value) return;
    final snapshot = _legalSnapshot;
    setState(() {
      _lookingUp = true;
      _aresError = null;
      _aresNotice = null;
    });
    try {
      final company =
          await _ares.lookup(_controllers['registrationNumber']!.text);
      if (!mounted ||
          !widget.canEdit ||
          snapshot != _legalSnapshot ||
          _controllers['countryCode']!.text.trim().toUpperCase() != 'CZ')
        return;
      final hasDetails = ['legalName', 'vatId', 'street', 'city', 'postalCode']
          .any((key) => _controllers[key]!.text.trim().isNotEmpty);
      if (hasDetails) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AppAlertDialog(
            onClose: () => Navigator.pop(context, false),
            title: Text(t('aresReplaceTitle')),
            content: Text(t('aresReplaceDescription')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(t('cancel'))),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(t('aresReplace'))),
            ],
          ),
        );
        if (!mounted ||
            replace != true ||
            !widget.canEdit ||
            snapshot != _legalSnapshot) return;
      }
      final values = company.toProfileDraft();
      setState(() {
        for (final key in _legalFields) {
          _controllers[key]!.text =
              (['street', 'city', 'postalCode'].contains(key)
                      ? (values['address'] as Map)[key]
                      : values[key]) as String? ??
                  '';
          _errors.remove(key);
          _errors.remove('address.$key');
        }
        _dirty = jsonEncode(_draft) != _baseline;
        _allowPop = false;
        _selectedOtherCountry = !['CZ', 'SK'].contains(company.countryCode);
        _aresNotice = t('aresLoaded');
      });
    } on AresLookupException catch (error) {
      if (mounted && snapshot == _legalSnapshot) {
        setState(() => _aresError = t(switch (error.failure) {
              AresLookupFailure.invalidRegistrationNumber => 'aresInvalidIco',
              AresLookupFailure.notFound => 'aresNotFound',
              AresLookupFailure.unavailable => 'aresUnavailable',
              AresLookupFailure.invalidResponse => 'aresInvalidResponse',
            }));
      }
    } catch (_) {
      if (mounted) setState(() => _aresError = t('aresUnavailable'));
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Widget _field(String key) => TextFormField(
        key: ValueKey('legal-profile-$key'),
        controller: _controllers[key],
        enabled: widget.canEdit &&
            !_busy &&
            !_loading &&
            !(_lookingUp && _legalFields.contains(key)),
        keyboardType: switch (key) {
          'contactEmail' => TextInputType.emailAddress,
          'website' => TextInputType.url,
          'phone' => TextInputType.phone,
          _ => TextInputType.text,
        },
        textCapitalization: key == 'countryCode'
            ? TextCapitalization.characters
            : TextCapitalization.none,
        decoration: InputDecoration(
          labelText: t(key),
          helperText: key == 'countryCode' ? t('countryHelp') : null,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (_) =>
            _errors.containsKey(key) || _errors.containsKey('address.$key')
                ? t('invalid')
                : null,
        onChanged: (_) => setState(() {
          _errors.remove(key);
          _errors.remove('address.$key');
          _dirty = jsonEncode(_draft) != _baseline;
          _allowPop = false;
          if (_legalFields.contains(key)) {
            _aresError = null;
            _aresNotice = null;
          }
        }),
      );

  Widget _countryField() {
    final code = _controllers['countryCode']!.text.trim().toUpperCase();
    final selection = _selectedOtherCountry ? 'other' : code;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(
        key: ValueKey('legal-profile-country-selector-$selection'),
        value: selection,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: t('countryLabel'),
          border: const OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem(value: 'CZ', child: Text(t('countryCzechia'))),
          DropdownMenuItem(value: 'SK', child: Text(t('countrySlovakia'))),
          DropdownMenuItem(value: 'other', child: Text(t('countryOther'))),
        ],
        validator: (_) =>
            !_selectedOtherCountry && _errors.containsKey('countryCode')
                ? t('invalid')
                : null,
        onChanged: !widget.canEdit || _busy || _loading || _lookingUp
            ? null
            : (value) {
                if (value == null) return;
                setState(() {
                  _selectedOtherCountry = value == 'other';
                  _controllers['countryCode']!.text =
                      _selectedOtherCountry ? '' : value;
                  _errors.remove('countryCode');
                  _dirty = jsonEncode(_draft) != _baseline;
                  _allowPop = false;
                  _aresError = null;
                  _aresNotice = null;
                });
              },
      ),
      if (_selectedOtherCountry) ...[
        const SizedBox(height: 16),
        _field('countryCode'),
      ],
    ]);
  }

  Widget _control(String key) =>
      key == 'countryCode' ? _countryField() : _field(key);

  Widget _pair(String first, String second) =>
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 560)
          return Column(children: [
            _control(first),
            const SizedBox(height: 16),
            _control(second),
          ]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _control(first)),
          const SizedBox(width: 16),
          Expanded(child: _control(second)),
        ]);
      });

  Widget _heading(String key) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 16),
        child: Text(t(key), style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _verificationStatus(UnitLegalProfile profile) {
    final colors = Theme.of(context).colorScheme;
    final verified = profile.status == 'verified';
    final verifiedAt = DateTime.tryParse(profile.verifiedAt ?? '')?.toLocal();
    final icon = switch (profile.status) {
      'verified' => Icons.verified_outlined,
      'pending' => Icons.schedule,
      'rejected' || 'revoked' => Icons.warning_amber_rounded,
      _ => Icons.info_outline,
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const ValueKey('legal-profile-verification-status'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: verified
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          border: Border.all(
              color: verified ? colors.primary : colors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon,
                size: 28,
                color: verified ? colors.primary : colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(t(profile.status),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(t(verified
                      ? 'verifiedDescription'
                      : profile.status == 'pending'
                          ? 'pendingDescription'
                          : 'publicNotice')),
                  if (verified && verifiedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                        '${t('verifiedOn')}: ${MaterialLocalizations.of(context).formatMediumDate(verifiedAt)}'),
                  ],
                ])),
          ]),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ||
                    _lookingUp ||
                    _loading ||
                    ConnectivityService.isOfflineNotifier.value
                ? null
                : _reload,
            icon: const Icon(Icons.refresh),
            label: Text(t('reload')),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final offline = ConnectivityService.isOfflineNotifier.value;
    final blocked = _busy || _lookingUp || _loading;
    final isCzech =
        _controllers['countryCode']!.text.trim().toUpperCase() == 'CZ';
    return NavigationDraftBoundary(
      isDirty: () => (_dirty && !_allowPop) || _busy || _lookingUp,
      confirm: () => _confirmDiscard(navigation: true),
      child: PopScope(
        canPop: !blocked && (!_dirty || _allowPop),
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop || blocked) return;
          if (await _confirmDiscard(navigation: true) && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (widget.onBack != null) {
                widget.onBack!();
              } else {
                Navigator.of(context).pop(result);
              }
            });
          }
        },
        child: Form(
          key: _form,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (p == null) Text(t('publicNotice')),
            if (offline)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(t('offline'))),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator()),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(liveRegion: true, child: Text(_message!)),
              ),
            if (p == null && !_loading)
              TextButton(onPressed: _reload, child: Text(t('retry'))),
            if (p != null) ...[
              const SizedBox(height: 16),
              _verificationStatus(p),
              if (p.feedback?.isNotEmpty == true)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(p.feedback!)),
              if (!widget.canEdit)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(t('noPermission'))),
              _heading('organizationDetails'),
              _pair('registrationNumber', 'countryCode'),
              if (isCzech) ...[
                const SizedBox(height: 12),
                Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: blocked || offline || !widget.canEdit
                          ? null
                          : _lookup,
                      icon: _lookingUp
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.search),
                      label: Text(t(_lookingUp ? 'aresLoading' : 'aresLookup')),
                    )),
                const SizedBox(height: 8),
                Text(t('aresHelp'),
                    style: Theme.of(context).textTheme.bodySmall),
                if (_aresError != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(
                          liveRegion: true,
                          child: Text(_aresError!,
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.error)))),
                if (_aresNotice != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(
                          liveRegion: true, child: Text(_aresNotice!))),
              ],
              const SizedBox(height: 16),
              _field('legalName'),
              const SizedBox(height: 16),
              _field('vatId'),
              _heading('address'),
              _field('street'),
              const SizedBox(height: 16),
              _pair('city', 'postalCode'),
              _heading('contactDetails'),
              _field('contactEmail'),
              const SizedBox(height: 16),
              _pair('phone', 'website'),
              const SizedBox(height: 24),
              if (_dirty && ['pending', 'verified'].contains(p.status))
                Text(t('changeWarning')),
              if (_dirty)
                Text(t('saveFirst'))
              else if (!p.complete)
                Text(t('completeFirst')),
              if (_busy) Text(t('saving')),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 8, children: [
                if (widget.canEdit &&
                    (_dirty ||
                        !p.complete ||
                        ['pending', 'verified'].contains(p.status)))
                  FilledButton(
                      onPressed: blocked || offline || !_dirty
                          ? null
                          : () => _write(false),
                      child: Text(t('save'))),
                if (widget.canEdit &&
                    !['pending', 'verified'].contains(p.status) &&
                    !_dirty &&
                    p.complete)
                  FilledButton(
                      onPressed: blocked || offline ? null : () => _write(true),
                      child: Text(t('submit'))),
                TextButton(
                    onPressed: () => showOrganizationDetails(context, _draft),
                    child: Text(t('preview'))),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

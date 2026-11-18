import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:fstapp/widgets/help_widget.dart';

import 'unit_measurement_help.dart';

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/copy_button.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/services/exception_handler.dart';

import '../db_units.dart';
import '../complianz_policy_probe.dart';
import '../unit_website_consent.dart';

/// The saved Unit and server scope are the only authoring/export authority.
class UnitWebsiteConsentSettings extends StatefulWidget {
  final Future<String> Function(String)? detectPolicy;
  final Future<UnitWebsiteConsent> Function(
    String,
    String,
    String,
    int,
    String,
  )?
  confirmDetected;
  final int unitId;
  final List<String> websites;

  final bool saved;
  final Future<UnitWebsiteConsent> Function()? load;
  final Future<UnitWebsiteConsent> Function(
    String,
    String,
    Map<String, dynamic>,
    int,
    String,
    bool,
  )?
  save;
  final Future<Map<String, dynamic>> Function(String, int)? export;
  final Future<UnitWebsiteConsent> Function(String, int)? disable;

  const UnitWebsiteConsentSettings({
    super.key,
    required this.unitId,
    required this.websites,
    required this.saved,
    this.load,
    this.detectPolicy,
    this.confirmDetected,
    this.save,
    this.export,
    this.disable,
  });

  @override
  State<UnitWebsiteConsentSettings> createState() =>
      _UnitWebsiteConsentSettingsState();
}

class _UnitWebsiteConsentSettingsState
    extends State<UnitWebsiteConsentSettings> {
  bool _expanded = false;
  UnitWebsiteConsent? _data;
  String? _origin;
  String _platform = 'wordpress', _provider = 'complianz';
  bool _busy = false, _failed = false, _coverage = false, _edited = false;
  final _exports = <String, String>{};
  final _editFocus = FocusNode(debugLabel: 'Edit website consent');
  int _scopeGeneration = 0;
  bool _reloadWhenIdle = false;
  bool _policyChanged = false;
  bool _hasLocalEdits = false;
  late final _probe = ComplianzPolicyProbe(onChanged: _probeChanged);
  int _scheduledProbe = 0;
  bool get _detecting => _probe.status == ComplianzProbeStatus.loading;
  bool get _detectionFailed =>
      _probe.status == ComplianzProbeStatus.unavailable;
  String? get _detectedPolicy => _probe.policyId;

  bool get _canDetect =>
      widget.saved &&
      _origin != null &&
      widget.websites.contains(_origin) &&
      _provider == 'complianz';

  void _cancelDetection() {
    ++_scheduledProbe;
    _probe.cancel();
  }

  void _probeChanged() {
    if (!mounted) return;
    setState(() {
      final detected = _detectedPolicy;
      if (detected != null) {
        _policy.text = detected;
        if (detected != _binding?.providerConfig['policyId']) _edited = true;
      }
    });
  }

  Future<void> _detect() async {
    if (!mounted || !_canDetect) return;
    setState(() {
      _coverage = false;
      _exports.remove(_origin);
    });
    await _probe.detect(
      _origin!,
      widget.detectPolicy ??
          (origin) => DbUnits.detectComplianzPolicy(widget.unitId, origin),
    );
  }

  void _scheduleDetection() {
    _cancelDetection();
    final generation = _scheduledProbe;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _scheduledProbe) _detect();
    });
  }

  final _policy = TextEditingController();
  final _analytics = TextEditingController();
  final _marketing = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UnitWebsiteConsentSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    final unitChanged = widget.unitId != oldWidget.unitId;
    final scopeChanged =
        unitChanged ||
        widget.saved != oldWidget.saved ||
        !listEquals(widget.websites, oldWidget.websites);
    if (!scopeChanged) return;
    ++_scopeGeneration;
    _cancelDetection();
    _coverage = false;
    _exports.clear();
    if (unitChanged) {
      _data = null;
      _failed = false;
      _origin = null;
    }
    if (!widget.websites.contains(_origin)) {
      _expanded = false;
      if (widget.websites.isNotEmpty) {
        _select(widget.websites.first, detect: false);
      } else {
        _origin = null;
      }
    }
    if (unitChanged || widget.saved) {
      _reloadWhenIdle = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reloadIfIdle());
    }
  }

  void _reloadIfIdle() {
    if (!mounted || _busy || !_reloadWhenIdle) return;
    _reloadWhenIdle = false;
    _load();
  }

  @override
  void dispose() {
    _cancelDetection();
    _editFocus.dispose();
    for (final controller in [_policy, _analytics, _marketing]) {
      controller.dispose();
    }
    super.dispose();
  }

  UnitWebsiteConsentBinding? get _binding => _data?.forWebsite(_origin ?? '');
  bool get _canSaveDraft =>
      _binding == null || {'draft', 'disabled'}.contains(_binding!.state);
  bool get _needsConfirmation => _edited || _binding?.state != 'ready';
  bool get _validPolicy =>
      RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(_policy.text.trim());
  bool get _validCategories =>
      _analytics.text.isNotEmpty &&
      _analytics.text.length <= 128 &&
      _marketing.text.isNotEmpty &&
      _marketing.text.length <= 128 &&
      _analytics.text != _marketing.text;
  bool get _validConfig => switch (_provider) {
    'complianz' => _validPolicy,
    'cookieconsent' => _validCategories,
    _ => true,
  };
  void _select(String origin, {bool detect = true}) {
    _origin = origin;
    _policyChanged = false;
    final b = _binding;
    final c = b?.providerConfig ?? <String, dynamic>{};
    _platform = b?.platform ?? 'wordpress';
    _provider = c['provider'] as String? ?? 'complianz';
    _policy.text = c['policyId']?.toString() ?? '';
    _analytics.text =
        (c['categories'] as Map?)?['analytics'] as String? ?? 'analytics';
    _marketing.text =
        (c['categories'] as Map?)?['marketing'] as String? ?? 'marketing';
    _coverage = false;
    _exports.remove(_origin);
    _edited = false;
    _hasLocalEdits = false;
    if (detect) {
      _scheduleDetection();
    } else {
      _cancelDetection();
    }
  }

  Future<void> _run(
    Future<void> Function(bool Function() isCurrent) action,
  ) async {
    if (_busy) return;
    final generation = _scopeGeneration;
    bool isCurrent() => mounted && _scopeGeneration == generation;

    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await ExceptionHandler.guard(
      context,
      defaultErrorMessage: FormStrings.cmsUnavailable,
      futureFunction: () async {
        try {
          await action(isCurrent);
        } catch (_) {
          if (isCurrent()) rethrow;
        }
        return true;
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = isCurrent() && ok != true;
    });
    _reloadIfIdle();
  }

  Future<void> _load() => _run((isCurrent) async {
    final data =
        await (widget.load?.call() ?? DbUnits.getWebsiteConsent(widget.unitId));
    if (!isCurrent()) return;
    setState(() {
      _data = data;
      _exports.clear();
      if (widget.websites.isNotEmpty) {
        _select(
          widget.websites.contains(_origin) ? _origin! : widget.websites.first,
        );
      }
    });
  });

  Future<void> _openEditor(String origin) async {
    if (_origin != origin && (_hasLocalEdits || _coverage)) {
      final generation = _scopeGeneration;
      if (!await confirmDiscardChanges(context) ||
          !mounted ||
          _scopeGeneration != generation ||
          _busy) {
        return;
      }
    }
    setState(() {
      if (_origin != origin) _select(origin);
      _expanded = true;
    });
  }

  void _closeEditor() {
    setState(() => _expanded = false);
    final origin = _origin;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_expanded && _origin == origin) _editFocus.requestFocus();
    });
  }

  Map<String, dynamic> get _config => {
    'provider': _provider,
    if (_provider == 'complianz') 'policyId': _policy.text.trim(),
    if (_provider == 'cookieconsent') ...{
      'categories': {
        'analytics': _analytics.text,
        'marketing': _marketing.text,
      },
    },
  };
  Future<void> _save(bool confirm) => _run((isCurrent) async {
    final snapshot = _data!;
    final origin = _origin!;
    final unitId = widget.unitId;
    final platform = _platform;
    final policy = _detectedPolicy;
    final config = _config;
    final version = _binding?.version ?? 0;
    final revision = snapshot.consentRevision;
    UnitWebsiteConsent data;
    try {
      if (confirm && _provider == 'complianz' && policy != null) {
        data =
            await (widget.confirmDetected?.call(
                  origin,
                  platform,
                  policy,
                  version,
                  revision,
                ) ??
                DbUnits.confirmDetectedComplianz(
                  unitId,
                  origin,
                  platform,
                  policy,
                  version,
                  revision,
                ));
      } else {
        data =
            await (widget.save?.call(
                  origin,
                  platform,
                  config,
                  version,
                  revision,
                  confirm,
                ) ??
                DbUnits.saveWebsiteConsent(
                  unitId,
                  origin,
                  platform,
                  config,
                  version,
                  revision,
                  confirm,
                ));
      }
    } on ComplianzPolicyChanged {
      if (!isCurrent() || !identical(_data, snapshot) || _origin != origin) {
        return;
      }
      setState(() {
        _policyChanged = true;
        _edited = true;
        _coverage = false;
        _exports.remove(origin);
      });
      await _detect();
      return;
    }
    if (!isCurrent() || !identical(_data, snapshot)) return;
    setState(() {
      _data = data;
      _exports.clear();
      if (_origin == origin) _select(origin, detect: false);
    });
  });

  Future<void> _disable(UnitWebsiteConsentBinding binding) =>
      _run((isCurrent) async {
        final snapshot = _data!;
        final data =
            await (widget.disable?.call(binding.id, binding.version) ??
                DbUnits.disableWebsiteConsent(binding.id, binding.version));
        if (!isCurrent() || !identical(_data, snapshot)) return;
        setState(() {
          _data = data;
          _exports.clear();
          if (_origin == binding.websiteOrigin) _select(binding.websiteOrigin);
        });
      });

  void _changed() => setState(() {
    _coverage = false;
    _exports.remove(_origin);
    _edited = true;
    _hasLocalEdits = true;
  });
  Widget _field(
    TextEditingController controller,
    String label, {
    String? helper,
    String? error,
    TextInputType? keyboardType,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextField(
      key: PageStorageKey('consent-field-$label'),
      controller: controller,
      enabled: !_busy && widget.saved,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        helperMaxLines: 8,
        errorMaxLines: 4,
        helper: helper == null ? null : Text(helper),
        error: error == null ? null : Text(error),
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => _changed(),
    ),
  );
  Future<void> _copyConfiguration(UnitWebsiteConsentBinding binding) => _run((
    isCurrent,
  ) async {
    final snapshot = _data!;
    final origin = binding.websiteOrigin;
    final data =
        await (widget.export?.call(binding.id, binding.version) ??
            DbUnits.exportWebsiteConsent(binding.id, binding.version));
    if (!mounted || !isCurrent() || !identical(_data, snapshot)) return;
    final value = const JsonEncoder.withIndent('  ').convert(data);
    setState(() => _exports[origin] = value);
    final copied = await CopyButton.copy(context, value);
    if (!mounted || !isCurrent() || !copied || _exports[origin] != value) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(CommonStrings.copiedToClipboard)));
  });

  String _platformName(String value) => switch (value) {
    'wordpress' => 'WordPress',
    'joomla' => 'Joomla',
    'wix' => 'Wix',
    'html' => FormStrings.cmsHtml,
    _ => value,
  };
  String _providerName(String? value) => switch (value) {
    'complianz' => 'Complianz',
    'cookiebot' => 'Cookiebot',
    'cookieconsent' => 'CookieConsent v3',
    'wix' => 'Wix',
    _ => value ?? '',
  };
  @override
  Widget build(BuildContext context) {
    final allowed =
        widget.saved && !_busy && !_failed && _data != null && _origin != null;
    return TextButtonTheme(
      data: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(48, 48),
          alignment: Alignment.centerLeft,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.saved) Text(FormStrings.measurementWebsitesSaveFirst),
          if (_failed) ...[
            Semantics(
              liveRegion: true,
              child: Text(FormStrings.cmsUnavailable),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed: _busy ? null : _load,
                child: Text(CommonStrings.retry),
              ),
            ),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (_data != null && widget.websites.isNotEmpty) ...[
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                for (final origin in widget.websites)
                  _websiteCard(context, origin, allowed),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _websiteCard(BuildContext context, String origin, bool allowed) {
    final binding = _data?.forWebsite(origin);
    final selected = _origin == origin;
    final platform = binding?.platform ?? 'wordpress';
    final platformName = _platformName(platform);
    final canExport =
        binding?.state == 'ready' && (!selected || !_needsConfirmation);
    final configuration = widget.saved ? _exports[origin] : null;
    final field = FormStrings.cmsInstallField(platform);
    final theme = Theme.of(context);
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.45,
    );
    final policyId = binding?.providerConfig['policyId']?.toString();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The help target uses the top inset so its icon can align with
            // the address without adding a 48 px row above the summary.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 16, right: 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Text(
                          origin.replaceFirst('https://', ''),
                          style: theme.textTheme.titleSmall,
                        ),
                        if (binding != null)
                          Text(
                            '$platformName · ${_providerName(binding.providerConfig['provider'] as String?)}'
                            '${policyId == null ? '' : ' · ${FormStrings.cmsPolicyNumber(policyId)}'}',
                            style: hintStyle,
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: UnitMeasurementHelpButton(
                      UnitMeasurementHelp.forPlatform(
                        selected && _expanded ? _platform : platform,
                      ),
                      label: FormStrings.measurementConsentBridge,
                    ),
                  ),
                ],
              ),
            ),
            if (binding != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Chip(
                        avatar: Icon(
                          binding.state == 'ready'
                              ? Icons.check_circle_outline
                              : Icons.info_outline,
                          size: 18,
                        ),
                        label: Text(FormStrings.cmsState(binding.state)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    HelpWidget(
                      targetSize: 48,
                      title: FormStrings.cmsState(binding.state),
                      content: FormStrings.cmsStateHelp(binding.state),
                    ),
                  ],
                ),
              ),
            ],
            if (canExport || !selected || !_expanded) ...[
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (canExport)
                      SizedBox(
                        width: constraints.maxWidth < 480
                            ? constraints.maxWidth
                            : null,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: allowed && (!selected || !_detecting)
                              ? () => _copyConfiguration(binding!)
                              : null,
                          child: Text(
                            FormStrings.cmsCopyFor(platformName),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    if (!selected || !_expanded)
                      TextButton(
                        focusNode: selected ? _editFocus : null,
                        onPressed: !_busy && !_failed
                            ? () => _openEditor(origin)
                            : null,
                        child: Text(CommonStrings.edit),
                      ),
                  ],
                ),
              ),
            ],
            if (canExport && widget.saved && configuration == null) ...[
              const SizedBox(height: 12),
              Text(
                platform == 'html'
                    ? FormStrings.cmsHtmlInstallHint(field)
                    : FormStrings.cmsInstallHint(field),
                style: hintStyle,
              ),
            ],
            if (configuration != null) ...[
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  for (final step in FormStrings.cmsInstallSteps(platform))
                    Text(step, style: hintStyle),
                ],
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                key: PageStorageKey('website-consent-export-details-$origin'),
                title: Text(FormStrings.cmsShowConfiguration),
                children: [
                  SelectableText(
                    configuration,
                    key: const PageStorageKey('website-consent-export-text'),
                  ),
                ],
              ),
            ],
            if (selected)
              Offstage(
                key: ValueKey(origin),
                offstage: !_expanded,
                child: ExcludeFocus(
                  excluding: !_expanded,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        DropdownButtonFormField<String>(
                          key: ValueKey('platform-$_platform'),
                          initialValue: _platform,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: FormStrings.cmsPlatform,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'wordpress',
                              child: Text('WordPress'),
                            ),
                            DropdownMenuItem(
                              value: 'joomla',
                              child: Text('Joomla'),
                            ),
                            DropdownMenuItem(value: 'wix', child: Text('Wix')),
                            DropdownMenuItem(
                              value: 'html',
                              child: Text(FormStrings.cmsHtml),
                            ),
                          ],
                          onChanged: allowed
                              ? (v) {
                                  _platform = v!;
                                  if (_platform == 'wix') {
                                    _provider = 'wix';
                                  }
                                  if (_platform != 'wix' &&
                                      _provider == 'wix') {
                                    _provider = 'complianz';
                                  }
                                  _changed();
                                  _scheduleDetection();
                                }
                              : null,
                        ),
                        DropdownButtonFormField<String>(
                          key: ValueKey('provider-$_provider'),
                          initialValue: _provider,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: FormStrings.cmsProvider,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'complianz',
                              child: Text('Complianz'),
                            ),
                            const DropdownMenuItem(
                              value: 'cookiebot',
                              child: Text('Cookiebot'),
                            ),
                            if (_platform == 'wix' || _provider == 'wix')
                              const DropdownMenuItem(
                                value: 'wix',
                                child: Text('Wix'),
                              ),
                            const DropdownMenuItem(
                              value: 'cookieconsent',
                              child: Text('CookieConsent v3'),
                            ),
                          ],
                          onChanged: allowed
                              ? (v) {
                                  _provider = v!;
                                  _changed();
                                  _scheduleDetection();
                                }
                              : null,
                        ),
                        if (_provider == 'complianz') ...[
                          if (_binding?.providerConfig['provider'] ==
                                  'complianz' &&
                              _binding!.providerConfig['policyId'] !=
                                  _detectedPolicy)
                            Text(
                              '${FormStrings.cmsPolicySaved}: ${_binding!.providerConfig['policyId']}',
                            ),
                          if (_policyChanged)
                            Semantics(
                              liveRegion: true,
                              child: Text(FormStrings.cmsPolicyChanged),
                            ),
                          if (_detecting)
                            Semantics(
                              liveRegion: true,
                              child: Text(CommonStrings.loading),
                            ),
                          if (_detectionFailed)
                            Semantics(
                              liveRegion: true,
                              child: Text(FormStrings.cmsPolicyDetectionFailed),
                            ),
                          if (_detectedPolicy == null && !_detecting)
                            ExpansionTile(
                              key: PageStorageKey("consent-$_origin-manual"),
                              title: Text(FormStrings.cmsPolicyManual),
                              children: [
                                _field(
                                  _policy,
                                  FormStrings.cmsPolicyId,
                                  helper: FormStrings.cmsPolicyIdHelp,
                                  error: (_edited || _coverage) && !_validPolicy
                                      ? FormStrings.cmsPolicyIdInvalid
                                      : null,
                                  keyboardType: TextInputType.number,
                                ),
                              ],
                            ),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (_detectedPolicy != null) ...[
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    '${FormStrings.cmsPolicyNumber(_detectedPolicy!)} · ${FormStrings.cmsPolicyFromWebsite}',
                                  ),
                                ),
                              ],
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: TextButton(
                                      onPressed:
                                          _canDetect && !_busy && !_detecting
                                          ? _detect
                                          : null,
                                      child: Text(FormStrings.cmsPolicyReload),
                                    ),
                                  ),
                                  HelpWidget(
                                    targetSize: 48,
                                    title: FormStrings.cmsPolicyReload,
                                    content:
                                        '${FormStrings.cmsReloadHelp}\n\n${FormStrings.cmsPolicyMeaning}',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                        if (_provider == 'cookieconsent')
                          ExpansionTile(
                            key: PageStorageKey("consent-$_origin-categories"),
                            title: Text(FormStrings.cmsAdvancedCategories),
                            children: [
                              _field(
                                _analytics,
                                FormStrings.cmsAnalyticsCategory,
                              ),
                              _field(
                                _marketing,
                                FormStrings.cmsMarketingCategory,
                                error: _edited && !_validCategories
                                    ? FormStrings.cmsCategoriesInvalid
                                    : null,
                              ),
                            ],
                          ),
                        if (_edited || _binding == null) ...[
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              FormStrings.cmsState(
                                _edited ? 'draft' : _binding?.state ?? 'draft',
                              ),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ],
                        if (_edited && !_canSaveDraft) ...[
                          Text(FormStrings.cmsChangesPending),
                        ],
                        if (_needsConfirmation) ...[
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _coverage,
                            title: Text(FormStrings.cmsCoverage),
                            onChanged: allowed && !_detecting
                                ? (v) => setState(() => _coverage = v == true)
                                : null,
                          ),
                          Text(
                            FormStrings.cmsCoverageDetails,
                            style: hintStyle,
                          ),
                        ],
                        if (_provider != 'complianz') ...[
                          Text(FormStrings.cmsFreshChoiceHelp),
                        ],
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (_needsConfirmation)
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed:
                                    allowed &&
                                        !_detecting &&
                                        _validConfig &&
                                        _coverage
                                    ? () => _save(true)
                                    : null,
                                child: Text(FormStrings.cmsConfirm),
                              ),
                            if (_needsConfirmation && _canSaveDraft)
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed:
                                    allowed &&
                                        !_detecting &&
                                        _validConfig &&
                                        _edited
                                    ? () => _save(false)
                                    : null,
                                child: Text(FormStrings.cmsSaveDraft),
                              ),
                            if (_edited && _binding != null)
                              TextButton(
                                onPressed: allowed
                                    ? () => setState(
                                        () => _select(_origin!, detect: false),
                                      )
                                    : null,
                                child: Text(CommonStrings.discardChanges),
                              ),
                            if (_binding != null &&
                                !{
                                  'draft',
                                  'disabled',
                                }.contains(_binding!.state))
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: TextButton(
                                      onPressed: allowed && !_detecting
                                          ? () => _disable(_binding!)
                                          : null,
                                      child: Text(FormStrings.cmsDisable),
                                    ),
                                  ),
                                  HelpWidget(
                                    targetSize: 48,
                                    title: FormStrings.cmsDisable,
                                    content: FormStrings.cmsDisableHelp,
                                  ),
                                ],
                              ),
                            TextButton(
                              onPressed: _busy ? null : _closeEditor,
                              child: Text(CommonStrings.close),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

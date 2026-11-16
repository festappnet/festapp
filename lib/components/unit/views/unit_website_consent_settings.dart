import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/copy_button.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/services/exception_handler.dart';

import '../db_units.dart';
import '../unit_website_consent.dart';

/// The saved Unit and server scope are the only authoring/export authority.
class UnitWebsiteConsentSettings extends StatefulWidget {
  final Future<String> Function(String)? detectPolicy;
  final int unitId;
  final List<String> websites;

  /// Saved, currently approved origins supplied by the owning settings screen.
  /// Unknown or unavailable approval must not start an external website probe.
  final List<String> approvedWebsites;
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
    this.approvedWebsites = const [],
    required this.saved,
    this.load,
    this.detectPolicy,
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
  UnitWebsiteConsent? _data;
  String? _origin;
  String _platform = 'wordpress', _provider = 'complianz';
  bool _busy = false, _failed = false, _coverage = false, _edited = false;
  String? _export;
  bool _detecting = false, _detectionFailed = false;
  String? _detectedPolicy;
  int _probeGeneration = 0;
  Timer? _probeDeadline;

  bool get _canDetect =>
      widget.saved &&
      _origin != null &&
      widget.websites.contains(_origin) &&
      widget.approvedWebsites.contains(_origin) &&
      _provider == 'complianz';

  void _cancelDetection() {
    ++_probeGeneration;
    _probeDeadline?.cancel();
    _probeDeadline = null;
    _detecting = false;
    _detectedPolicy = null;
    _detectionFailed = false;
  }

  void _completeDetection(int generation, String origin, String? policy) {
    if (!mounted ||
        generation != _probeGeneration ||
        _origin != origin ||
        !_canDetect) {
      return;
    }
    _probeDeadline?.cancel();
    _probeDeadline = null;
    ++_probeGeneration;
    setState(() {
      _detecting = false;
      _detectionFailed = policy == null;
      _detectedPolicy = policy;
      _policy.text = policy ?? '';
      if (policy != null && policy != _binding?.providerConfig['policyId']) {
        _edited = true;
      }
    });
  }

  Future<void> _detect() async {
    if (!mounted || !_canDetect) return;
    final origin = _origin!;
    _cancelDetection();
    final generation = _probeGeneration;
    setState(() {
      _detecting = true;
      _detectionFailed = false;
      _detectedPolicy = null;
      _policy.clear();
      _coverage = false;
      _export = null;
    });
    // Optional detection must release the editor even if transport never resolves.
    _probeDeadline = Timer(
      const Duration(seconds: 20),
      () => _completeDetection(generation, origin, null),
    );
    String? policy;
    try {
      policy =
          await (widget.detectPolicy?.call(origin) ??
              DbUnits.detectComplianzPolicy(widget.unitId, origin));
      if (!RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(policy)) policy = null;
    } catch (_) {
      // Detection is optional; the existing explicit manual pin remains available.
    }
    _completeDetection(generation, origin, policy);
  }

  void _scheduleDetection() {
    _cancelDetection();
    final generation = _probeGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _probeGeneration) _detect();
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
    final wasApproved = oldWidget.approvedWebsites.contains(_origin);
    final isApproved = widget.approvedWebsites.contains(_origin);
    if (!widget.saved || !isApproved) {
      _cancelDetection();
    } else if (!wasApproved) {
      _scheduleDetection();
    }
    if (!widget.saved) {
      _coverage = false;
      _export = null;
    }
    if (!widget.websites.contains(_origin)) {
      if (widget.websites.isEmpty) {
        _origin = null;
        _coverage = false;
        _export = null;
      } else {
        _select(widget.websites.first);
      }
    }
    if (widget.saved && !oldWidget.saved) {
      _coverage = false;
      _export = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.saved && !_busy) _load();
      });
    }
  }

  @override
  void dispose() {
    _cancelDetection();
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
  void _select(String origin) {
    _origin = origin;
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
    _export = null;
    _edited = false;
    _scheduleDetection();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await ExceptionHandler.guard(
      context,
      defaultErrorMessage: FormStrings.cmsUnavailable,
      futureFunction: () async {
        await action();
        return true;
      },
    );
    if (mounted) {
      setState(() {
        _busy = false;
        _failed = ok != true;
      });
    }
  }

  Future<void> _load() => _run(() async {
    final data =
        await (widget.load?.call() ?? DbUnits.getWebsiteConsent(widget.unitId));
    if (!mounted) return;
    setState(() {
      _data = data;
      if (widget.websites.isNotEmpty) {
        _select(
          widget.websites.contains(_origin) ? _origin! : widget.websites.first,
        );
      }
    });
  });
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
  Future<void> _save(bool confirm) => _run(() async {
    final config = _config;
    final version = _binding?.version ?? 0;
    final data =
        await (widget.save?.call(
              _origin!,
              _platform,
              config,
              version,
              _data!.consentRevision,
              confirm,
            ) ??
            (confirm && _provider == 'complianz' && _detectedPolicy != null
                ? DbUnits.confirmDetectedComplianz(
                    widget.unitId,
                    _origin!,
                    _platform,
                    _detectedPolicy!,
                    version,
                    _data!.consentRevision,
                  )
                : DbUnits.saveWebsiteConsent(
                    widget.unitId,
                    _origin!,
                    _platform,
                    config,
                    version,
                    _data!.consentRevision,
                    confirm,
                  )));
    if (!mounted) return;
    setState(() {
      _data = data;
      _select(_origin!);
    });
  });
  void _changed() => setState(() {
    _coverage = false;
    _export = null;
    _edited = true;
  });
  Future<void> _copyConfiguration() async {
    final value = _export;
    if (value == null) return;
    final copied = await CopyButton.copy(context, value);
    if (!mounted || !copied || _export != value) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(CommonStrings.copiedToClipboard)));
  }

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
        helper: helper == null ? null : Text(helper),
        error: error == null ? null : Text(error),
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => _changed(),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final allowed =
        widget.saved &&
        !_busy &&
        !_detecting &&
        !_failed &&
        _data != null &&
        _origin != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(
          FormStrings.cmsTransfer,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(FormStrings.cmsTransferHelp),
        if (!widget.saved) Text(FormStrings.measurementWebsitesSaveFirst),
        if (_failed) ...[
          Semantics(liveRegion: true, child: Text(FormStrings.cmsUnavailable)),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: _busy ? null : _load,
              child: Text(CommonStrings.retry),
            ),
          ),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_data != null && widget.websites.isNotEmpty) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('website-${widget.websites.join("\n")}'),
            initialValue: _origin,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: FormStrings.measurementWebsites,
              border: const OutlineInputBorder(),
            ),
            items: widget.websites
                .map(
                  (origin) => DropdownMenuItem(
                    value: origin,
                    child: Tooltip(
                      message: origin,
                      child: Text(
                        origin,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: allowed ? (v) => setState(() => _select(v!)) : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('platform-$_platform'),
            initialValue: _platform,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: FormStrings.cmsPlatform,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: 'wordpress', child: Text('WordPress')),
              DropdownMenuItem(value: 'joomla', child: Text('Joomla')),
              DropdownMenuItem(value: 'wix', child: Text('Wix')),
              DropdownMenuItem(
                value: 'html',
                child: Text(
                  FormStrings.cmsHtml,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            onChanged: allowed
                ? (v) {
                    _platform = v!;
                    if (_platform == 'wix') _provider = 'wix';
                    if (_platform != 'wix' && _provider == 'wix') {
                      _provider = 'complianz';
                    }
                    _changed();
                    _scheduleDetection();
                  }
                : null,
          ),
          const SizedBox(height: 16),
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
                const DropdownMenuItem(value: 'wix', child: Text('Wix')),
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
            if (_detecting) Text(CommonStrings.loading),
            if (_detectedPolicy != null) ...[
              Text('${FormStrings.cmsPolicyId}: $_detectedPolicy'),
              Text(FormStrings.cmsPolicyDetected),
            ],
            if (_detectionFailed) ...[
              Text(FormStrings.cmsPolicyDetectionFailed),
              ExpansionTile(
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
            ],
            TextButton(
              onPressed: _canDetect && !_busy && !_detecting ? _detect : null,
              child: Text(FormStrings.cmsPolicyReload),
            ),
          ],
          if (_provider == 'cookieconsent')
            ExpansionTile(
              title: Text(FormStrings.cmsAdvancedCategories),
              children: [
                _field(_analytics, FormStrings.cmsAnalyticsCategory),
                _field(
                  _marketing,
                  FormStrings.cmsMarketingCategory,
                  error: _edited && !_validCategories
                      ? FormStrings.cmsCategoriesInvalid
                      : null,
                ),
              ],
            ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              FormStrings.cmsState(
                _edited ? 'draft' : _binding?.state ?? 'draft',
              ),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (_edited && !_canSaveDraft) ...[
            const SizedBox(height: 8),
            Text(FormStrings.cmsChangesPending),
          ],
          if (_needsConfirmation) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _coverage,
              title: Text(FormStrings.cmsCoverage),
              onChanged: allowed
                  ? (v) => setState(() => _coverage = v == true)
                  : null,
            ),
            Text(
              FormStrings.cmsCoverageDetails,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_provider != 'complianz') ...[
            const SizedBox(height: 8),
            Text(FormStrings.cmsFreshChoiceHelp),
          ],
          const SizedBox(height: 12),
          if (_export != null && widget.saved) ...[
            Text(FormStrings.cmsExportHelp),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy ? null : _copyConfiguration,
                icon: const Icon(Icons.copy),
                label: Text(FormStrings.cmsCopy),
              ),
            ),
            ExpansionTile(
              key: const PageStorageKey('website-consent-export-details'),
              title: Text(FormStrings.cmsShowConfiguration),
              children: [
                SelectableText(
                  _export!,
                  key: const PageStorageKey('website-consent-export-text'),
                ),
              ],
            ),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (_needsConfirmation)
                FilledButton(
                  onPressed: allowed && _validConfig && _coverage
                      ? () => _save(true)
                      : null,
                  child: Text(FormStrings.cmsConfirm),
                ),
              if (_needsConfirmation && _canSaveDraft)
                OutlinedButton(
                  onPressed: allowed && _validConfig && _edited
                      ? () => _save(false)
                      : null,
                  child: Text(FormStrings.cmsSaveDraft),
                ),
              if (!_needsConfirmation && _export == null)
                FilledButton(
                  onPressed: allowed
                      ? () => _run(() async {
                          final b = _binding!;
                          final data =
                              await (widget.export?.call(b.id, b.version) ??
                                  DbUnits.exportWebsiteConsent(
                                    b.id,
                                    b.version,
                                  ));
                          if (mounted) {
                            setState(
                              () =>
                                  _export = const JsonEncoder.withIndent('  ')
                                      .convert(data),
                            );
                          }
                        })
                      : null,
                  child: Text(FormStrings.cmsExport),
                ),
              if (_edited && _binding != null)
                TextButton(
                  onPressed: allowed
                      ? () => setState(() => _select(_origin!))
                      : null,
                  child: Text(CommonStrings.discardChanges),
                ),
              if (_binding != null &&
                  !{'draft', 'disabled'}.contains(_binding!.state))
                TextButton(
                  onPressed: allowed
                      ? () => _run(() async {
                          final b = _binding!;
                          final data =
                              await (widget.disable?.call(b.id, b.version) ??
                                  DbUnits.disableWebsiteConsent(
                                    b.id,
                                    b.version,
                                  ));
                          if (mounted) {
                            setState(() {
                              _data = data;
                              _select(_origin!);
                            });
                          }
                        })
                      : null,
                  child: Text(FormStrings.cmsDisable),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

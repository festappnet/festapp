import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/services/exception_handler.dart';

import '../db_units.dart';
import '../unit_website_consent.dart';

/// The saved Unit and server scope are the only authoring/export authority.
class UnitWebsiteConsentSettings extends StatefulWidget {
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
    for (final controller in [_analytics, _marketing]) {
      controller.dispose();
    }
    super.dispose();
  }

  UnitWebsiteConsentBinding? get _binding => _data?.forWebsite(_origin ?? '');
  void _select(String origin) {
    _origin = origin;
    final b = _binding;
    final c = b?.providerConfig ?? <String, dynamic>{};
    _platform = b?.platform ?? 'wordpress';
    _provider = c['provider'] as String? ?? 'complianz';
    _analytics.text =
        (c['categories'] as Map?)?['analytics'] as String? ?? 'analytics';
    _marketing.text =
        (c['categories'] as Map?)?['marketing'] as String? ?? 'marketing';
    _coverage = false;
    _export = null;
    _edited = false;
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
            DbUnits.saveWebsiteConsent(
              widget.unitId,
              _origin!,
              _platform,
              config,
              version,
              _data!.consentRevision,
              confirm,
            ));
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
  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextField(
      key: PageStorageKey('consent-field-$label'),
      controller: controller,
      enabled: !_busy && widget.saved,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => _changed(),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final allowed =
        widget.saved && !_busy && !_failed && _data != null && _origin != null;
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
          Text(FormStrings.cmsUnavailable),
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
                  (origin) =>
                      DropdownMenuItem(value: origin, child: Text(origin)),
                )
                .toList(),
            onChanged: allowed ? (v) => setState(() => _select(v!)) : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('platform-$_platform'),
            initialValue: _platform,
            decoration: InputDecoration(
              labelText: FormStrings.cmsPlatform,
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(value: 'wordpress', child: Text('WordPress')),
              DropdownMenuItem(value: 'joomla', child: Text('Joomla')),
              DropdownMenuItem(value: 'wix', child: Text('Wix')),
              DropdownMenuItem(value: 'html', child: Text(FormStrings.cmsHtml)),
            ],
            onChanged: allowed
                ? (v) {
                    _platform = v!;
                    if (_platform == 'wix') _provider = 'wix';
                    _changed();
                  }
                : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey('provider-$_provider'),
            initialValue: _provider,
            decoration: InputDecoration(
              labelText: FormStrings.cmsProvider,
              border: const OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'complianz', child: Text('Complianz')),
              DropdownMenuItem(value: 'cookiebot', child: Text('Cookiebot')),
              DropdownMenuItem(value: 'wix', child: Text('Wix')),
              DropdownMenuItem(
                value: 'cookieconsent',
                child: Text('CookieConsent v3'),
              ),
            ],
            onChanged: allowed
                ? (v) {
                    _provider = v!;
                    _changed();
                  }
                : null,
          ),
          if (_provider == 'cookieconsent')
            ExpansionTile(
              title: Text(FormStrings.cmsAdvancedCategories),
              children: [
                _field(_analytics, FormStrings.cmsAnalyticsCategory),
                _field(_marketing, FormStrings.cmsMarketingCategory),
              ],
            ),
          const SizedBox(height: 16),
          Text(
            FormStrings.cmsState(
              _edited ? 'draft' : _binding?.state ?? 'draft',
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _coverage,
            title: Text(FormStrings.cmsCoverage),
            onChanged: allowed
                ? (v) => setState(() => _coverage = v == true)
                : null,
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: allowed ? () => _save(false) : null,
                child: Text(CommonStrings.save),
              ),
              FilledButton(
                onPressed: allowed && _coverage ? () => _save(true) : null,
                child: Text(FormStrings.cmsConfirm),
              ),
              OutlinedButton(
                onPressed: allowed && !_edited && _binding?.state == 'ready'
                    ? () => _run(() async {
                        final b = _binding!;
                        final data =
                            await (widget.export?.call(b.id, b.version) ??
                                DbUnits.exportWebsiteConsent(b.id, b.version));
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
              if (_binding != null)
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
          if (_export != null && widget.saved) ...[
            const SizedBox(height: 16),
            Text(FormStrings.cmsExportHelp),
            SelectableText(
              _export!,
              key: const PageStorageKey('website-consent-export-text'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _export!)),
                icon: const Icon(Icons.copy),
                label: Text(FormStrings.cmsCopy),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

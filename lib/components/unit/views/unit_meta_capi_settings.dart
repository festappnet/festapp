import 'package:material_ui/material_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/theme_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import '../db_units.dart';
import '../meta_capi_strings.dart';

class UnitMetaCapiSettings extends StatefulWidget {
  final int unitId;
  final Future<Map<String, dynamic>> Function(int)? load;
  final Future<void> Function(String, Map<String, dynamic>)? mutate;
  const UnitMetaCapiSettings({
    super.key,
    required this.unitId,
    this.load,
    this.mutate,
  });
  @override
  State<UnitMetaCapiSettings> createState() => _UnitMetaCapiSettingsState();
}

class _UnitMetaCapiSettingsState extends State<UnitMetaCapiSettings> {
  Map<String, dynamic>? _data;
  final _dataset = TextEditingController();
  final _testCode = TextEditingController();
  final _token = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _website;
  bool _enabled = false;
  bool _busy = false;
  bool _loadFailed = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _token.addListener(_tokenChanged);
    _load();
  }

  Future<void> _load({bool preserveDraft = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final data = await (widget.load ?? DbUnits.getMetaPurchase)(
        widget.unitId,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        if (!preserveDraft) {
          _dataset.text = data['dataset'] as String? ?? '';
          _testCode.text = data['test_event_code'] as String? ?? '';
          _website = data['website_origin'] as String?;
          _enabled = data['enabled'] == true;
        }
        if (data['allowed'] != true) _token.clear();
        _loadFailed = false;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      if (error.code == '42501') {
        setState(() {
          _data = {'allowed': false};
          _token.clear();
          _loadFailed = false;
        });
      } else {
        setState(() => _loadFailed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _validDraftToken =>
      _token.text.length >= 16 &&
      _token.text.length <= 4096 &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(_token.text);

  void _tokenChanged() {
    setState(() {
      if (_data?['token_saved'] != true && !_validDraftToken) _enabled = false;
    });
  }

  Future<void> _mutate(String operation, Map<String, dynamic> params) =>
      (widget.mutate ?? DbUnits.mutateMetaPurchase)(operation, {
        'p_unit': widget.unitId,
        ...params,
      });

  Future<void> _perform(
    Future<void> Function() action, {
    bool preserveDraft = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    await ExceptionHandler.guard(
      context,
      defaultErrorMessage: MetaCapiStrings.unavailable,
      futureFunction: () async {
        try {
          await action();
        } finally {
          // Clear credentials even if a later stage fails; reload partial saves.
          if (mounted) {
            if (!preserveDraft) _token.clear();
            await _load(preserveDraft: preserveDraft);
          }
        }
      },
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _run(
    String operation,
    Map<String, dynamic> params, {
    bool preserveDraft = false,
  }) =>
      _perform(() => _mutate(operation, params), preserveDraft: preserveDraft);

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final token = _token.text;
    final enabled = _enabled;
    final needsTokenFirst = enabled && _data?['token_saved'] != true;
    if (needsTokenFirst && !_validDraftToken) return;
    final settings = <String, dynamic>{
      'p_dataset': _dataset.text,
      'p_website_origin': _website,
      'p_test_event_code': _testCode.text,
      'p_enabled': needsTokenFirst ? false : enabled,
    };
    await _perform(() async {
      // Create/save the connector before writing Vault. A first token must be
      // stored successfully before a separate call can enable the connector.
      await _mutate('save_unit_meta_purchase', settings);
      if (token.isNotEmpty) {
        await _mutate('set_unit_meta_purchase_token', {'p_token': token});
      }
      if (needsTokenFirst) {
        await _mutate('save_unit_meta_purchase', {
          ...settings,
          'p_enabled': true,
        });
      }
    });
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        onClose: () => Navigator.of(context).pop(false),
        title: Text(MetaCapiStrings.disconnect),
        content: Text(MetaCapiStrings.confirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(CommonStrings.storno),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(MetaCapiStrings.disconnect),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run('delete_unit_meta_purchase', {});
    }
  }

  @override
  void dispose() {
    _dataset.dispose();
    _testCode.dispose();
    _token.removeListener(_tokenChanged);
    _token.dispose();
    super.dispose();
  }

  Widget _section(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 32),
    child: ExpansionTile(
      key: PageStorageKey('unit-meta-capi-settings-${widget.unitId}'),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _loadFailed ? MetaCapiStrings.loadFailed : MetaCapiStrings.title,
            ),
          ),
          if (_loading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      tilePadding: EdgeInsets.zero,
      maintainState: true,
      expansionAnimationStyle: AnimationStyle.noAnimation,
      childrenPadding: const EdgeInsets.only(top: 8, bottom: 16),
      children: children,
    ),
  );

  Widget _retryLoad() => TextButton(
    onPressed: _loading || _busy
        ? null
        : () => _load(preserveDraft: _data != null),
    child: Text(CommonStrings.retry),
  );

  @override
  Widget build(BuildContext context) {
    // A known platform denial exposes only authorized disconnect cleanup.
    if (_data?['allowed'] == false) {
      if (_data?['connected'] != true) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Row(
          children: [
            Expanded(child: Text(MetaCapiStrings.platformDisabled)),
            TextButton(
              onPressed: _busy || _loading ? null : _disconnect,
              child: Text(MetaCapiStrings.disconnect),
            ),
          ],
        ),
      );
    }
    if (_data == null) {
      return _section([
        if (_loadFailed) _retryLoad(),
        if (_loading) Text(CommonStrings.loading),
      ]);
    }
    final data = _data!;
    final websites = List<String>.from(data['websites'] ?? const []);
    final selected = websites.contains(_website) ? _website : null;
    final queue = Map<String, dynamic>.from(data['queue'] ?? const {});
    final forms = data['forms'] as List? ?? const [];
    final error = data['last_error'] as Map?;
    final errorAt = DateTime.tryParse(error?['at']?.toString() ?? '');
    final errorText = error?['status'] == 'failed'
        ? MetaCapiStrings.deliveryFailed
        : switch (error?['code']) {
            'sent_in_flight' => MetaCapiStrings.sentInFlight,
            'credentials' => MetaCapiStrings.credentials,
            'rejected' => MetaCapiStrings.rejected,
            _ =>
              error?['status'] == 'pending'
                  ? MetaCapiStrings.retry
                  : MetaCapiStrings.deliveryFailed,
          };
    final paused = data['paused_at'] != null;
    final active = data['enabled'] == true;
    final statusColor = paused
        ? ThemeConfig.warningColor(context)
        : active
        ? ThemeConfig.greenColor(context)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return _section([
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(
                    paused
                        ? Icons.warning_amber_rounded
                        : active
                        ? Icons.check_circle_outline
                        : Icons.pause_circle_outline,
                    color: statusColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      paused
                          ? MetaCapiStrings.paused
                          : active
                          ? MetaCapiStrings.active
                          : MetaCapiStrings.off,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: paused
                            ? Theme.of(context).colorScheme.onSurface
                            : statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_loadFailed) _retryLoad(),
            const SizedBox(height: 12),
            TextFormField(
              // Own storage identity; the section tile stores its expanded bool.
              key: const PageStorageKey('meta-capi-dataset'),
              controller: _dataset,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: MetaCapiStrings.dataset),
              validator: (v) => RegExp(r'^[0-9]{5,30}$').hasMatch(v ?? '')
                  ? null
                  : MetaCapiStrings.invalid,
            ),
            if (websites.isEmpty) Text(MetaCapiStrings.noWebsites),
            DropdownButtonFormField<String>(
              key: ValueKey(selected),
              initialValue: selected,
              isExpanded: true,
              decoration: InputDecoration(labelText: MetaCapiStrings.website),
              items: websites
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: _busy || websites.isEmpty
                  ? null
                  : (v) => setState(() => _website = v),
              validator: (v) => v == null ? MetaCapiStrings.invalid : null,
            ),
            TextFormField(
              key: const PageStorageKey('meta-capi-test-code'),
              controller: _testCode,
              enabled: !_busy,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: MetaCapiStrings.testCode,
                counterText: '',
                helperText: MetaCapiStrings.testHelp,
                helperMaxLines: 6,
              ),
              validator: (v) =>
                  (v ?? '').isEmpty ||
                      RegExp(r'^[A-Za-z0-9_-]{1,60}$').hasMatch(v!)
                  ? null
                  : MetaCapiStrings.invalid,
            ),
            TextFormField(
              key: const PageStorageKey('meta-capi-token'),
              controller: _token,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 4096,
              decoration: InputDecoration(
                labelText: MetaCapiStrings.token,
                counterText: '',
                helperText: data['token_saved'] == true
                    ? MetaCapiStrings.saved
                    : null,
                helperMaxLines: 4,
              ),
              validator: (v) {
                if ((v ?? '').isEmpty) {
                  return _enabled && data['token_saved'] != true
                      ? MetaCapiStrings.tokenRequired
                      : null;
                }
                return _validDraftToken ? null : MetaCapiStrings.invalid;
              },
            ),
            SwitchListTile(
              title: Text(MetaCapiStrings.enabled),
              subtitle: data['token_saved'] == true || _validDraftToken
                  ? null
                  : Text(MetaCapiStrings.tokenRequired),
              value: _enabled,
              onChanged:
                  _busy ||
                      (!_enabled &&
                          data['token_saved'] != true &&
                          !_validDraftToken)
                  ? null
                  : (v) => setState(() => _enabled = v),
            ),
            FilledButton(
              onPressed: _busy || _loading || _loadFailed || websites.isEmpty
                  ? null
                  : _save,
              child: Text(CommonStrings.save),
            ),
            const SizedBox(height: 16),
            Text(MetaCapiStrings.queue),
            Wrap(
              spacing: 16,
              children: [
                Text('${MetaCapiStrings.pending}: ${queue['pending'] ?? 0}'),
                Text('${MetaCapiStrings.sent}: ${queue['sent'] ?? 0}'),
                Text('${MetaCapiStrings.failed}: ${queue['failed'] ?? 0}'),
                Text('${MetaCapiStrings.revoked}: ${queue['revoked'] ?? 0}'),
              ],
            ),
            if (error != null)
              Text(
                '$errorText${errorAt == null ? '' : ' · ${DateFormat.yMd(context.locale.toString()).add_jm().format(errorAt.toLocal())}'}',
              ),
            const SizedBox(height: 16),
            Text(
              forms.isEmpty ? MetaCapiStrings.noForms : MetaCapiStrings.forms,
            ),
            for (final item in forms)
              SwitchListTile(
                title: Text(item['title'] as String? ?? ''),
                value: item['enabled'] == true,
                onChanged: _busy || _loading || data['revision'] == null
                    ? null
                    : (v) => _run('set_form_meta_purchase', {
                        'p_form': item['id'],
                        'p_enabled': v,
                      }, preserveDraft: true),
              ),
            if (data['revision'] != null)
              TextButton(
                onPressed: _busy ? null : _disconnect,
                child: Text(MetaCapiStrings.disconnect),
              ),
          ],
        ),
      ),
    ]);
  }
}

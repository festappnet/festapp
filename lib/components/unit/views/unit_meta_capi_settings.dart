import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/theme_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import '../db_units.dart';
import '../meta_capi_strings.dart';
import '../unit_measurement_approval.dart';

class UnitMetaCapiSettings extends StatefulWidget {
  final int unitId;
  final List<String> savedWebsites;
  final Widget Function(Widget child)? sectionBuilder;
  final Future<Map<String, dynamic>> Function(int)? load;
  final Future<void> Function(String, Map<String, dynamic>)? mutate;

  /// Unit managers may ask the platform for approval; settings stay
  /// organization-administrator only.
  final bool canRequestApproval;
  final Future<UnitMeasurementApproval> Function(int)? loadApproval;
  final Future<UnitMeasurementApproval> Function(int)? requestApproval;
  const UnitMetaCapiSettings({
    super.key,
    required this.unitId,
    this.savedWebsites = const [],
    this.sectionBuilder,
    this.load,
    this.mutate,
    this.canRequestApproval = false,
    this.loadApproval,
    this.requestApproval,
  });
  @override
  State<UnitMetaCapiSettings> createState() => _UnitMetaCapiSettingsState();
}

class _UnitMetaCapiSettingsState extends State<UnitMetaCapiSettings> {
  Map<String, dynamic>? _data;
  UnitMeasurementApproval? _approval;
  final _dataset = TextEditingController();
  final _testCode = TextEditingController();
  final _token = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _website;
  bool _enabled = false;
  bool _busy = false;
  bool _loadFailed = false;
  bool _loading = false;
  bool _refreshWebsites = false;

  @override
  void initState() {
    super.initState();
    _token.addListener(_tokenChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant UnitMetaCapiSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(widget.savedWebsites, oldWidget.savedWebsites)) return;
    if (_loading) {
      _refreshWebsites = true;
    } else {
      _load(preserveDraft: _data != null);
    }
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
      if (mounted && _data?['allowed'] == false) await _loadApproval();
      if (mounted) {
        setState(() => _loading = false);
        if (_refreshWebsites) {
          _refreshWebsites = false;
          await _load(preserveDraft: _data != null);
        }
      }
    }
  }

  Future<void> _loadApproval() async {
    UnitMeasurementApproval? approval;
    try {
      approval = await (widget.loadApproval ?? DbUnits.getMetaCapiApproval)(
        widget.unitId,
      );
    } catch (_) {
      // Readers without Unit administration access keep the hidden section.
      approval = null;
    }
    if (mounted) setState(() => _approval = approval);
  }

  Future<void> _requestApproval() async {
    if (_busy || _approval?.canRequest != true) return;
    setState(() => _busy = true);
    try {
      final approval = await ExceptionHandler.guard(
        context,
        futureFunction: () async {
          try {
            return await (widget.requestApproval ??
                DbUnits.requestMetaCapiApproval)(widget.unitId);
          } catch (error) {
            final detail = error.toString();
            final message = detail.contains('meta_capi_request_no_recipient')
                ? FormStrings.measurementRequestNoRecipient
                : detail.contains('meta_capi_notification_origin_missing')
                ? FormStrings.measurementNotificationOriginMissing
                : null;
            if (message != null) {
              throw AppError(
                code: 'meta_capi_request',
                message: message,
                rawJson: '{}',
              );
            }
            rethrow;
          }
        },
      );
      if (mounted && approval != null) setState(() => _approval = approval);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _approvalStatus(BuildContext context, UnitMeasurementApproval a) {
    final requested = a.requestState == MeasurementRequestState.requested;
    final status = a.approved
        ? MetaCapiStrings.approvedByPlatform
        : requested
        ? a.requestedAt == null
              ? FormStrings.measurementPlatformPending
              : FormStrings.measurementApprovalRequested(
                  DateFormat.yMd(context.locale.toString())
                      .format(a.requestedAt!.toLocal()),
                )
        : a.requestState == MeasurementRequestState.retryAvailable &&
              a.canRequest
        ? FormStrings.measurementApprovalRetry
        : FormStrings.measurementApprovalRequired;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(liveRegion: true, child: Text(status)),
        if (widget.canRequestApproval &&
            !a.approved &&
            !requested &&
            a.canRequest) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _busy || _loading ? null : _requestApproval,
            child: Text(MetaCapiStrings.requestApproval),
          ),
        ],
      ],
    );
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
          // Clear the write-only credential after each save attempt.
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
    await _run('save_unit_meta_purchase', {
      'p_dataset': _dataset.text,
      'p_website_origin': _website,
      'p_test_event_code': _testCode.text,
      'p_enabled': enabled,
      if (token.isNotEmpty) 'p_token': token,
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
    final section = _buildSection(context);
    if (section == null) return const SizedBox.shrink();
    return widget.sectionBuilder?.call(section) ?? section;
  }

  Widget? _buildSection(BuildContext context) {
    // A known platform denial exposes only the approval request status and
    // authorized disconnect cleanup, never settings or delivery details.
    if (_data?['allowed'] == false) {
      final connected = _data?['connected'] == true;
      final approval = _approval;
      if (!connected && approval == null) return null;
      return Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (connected)
              Row(
                children: [
                  Expanded(child: Text(MetaCapiStrings.platformDisabled)),
                  TextButton(
                    onPressed: _busy || _loading ? null : _disconnect,
                    child: Text(MetaCapiStrings.disconnect),
                  ),
                ],
              )
            else
              Text(
                MetaCapiStrings.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            if (approval != null) ...[
              const SizedBox(height: 8),
              _approvalStatus(context, approval),
            ],
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
    final errorText = switch (error?['code']) {
      'connector_changed' ||
      'consent_invalid' ||
      'order_ineligible' ||
      'payment_too_old' ||
      'attempts_exhausted' ||
      'retention_expired' => MetaCapiStrings.outcomeReason(
        error!['code'] as String,
      ),
      'sent_in_flight' => MetaCapiStrings.sentInFlight,
      'credentials' =>
        error?['status'] == 'failed'
            ? MetaCapiStrings.deliveryFailed
            : MetaCapiStrings.credentials,
      'rejected' => MetaCapiStrings.rejected,
      _ =>
        error?['status'] == 'pending'
            ? MetaCapiStrings.retry
            : MetaCapiStrings.deliveryFailed,
    };
    final paused = data['paused_at'] != null;
    final pausedAt = DateTime.tryParse(data['paused_at']?.toString() ?? '');
    String withStatusDate(String message, DateTime? at) => at == null
        ? message
        : '$message · ${DateFormat.yMd(context.locale.toString()).add_jm().format(at.toLocal())}';
    final enabled = data['enabled'] == true;
    final websiteReady = data['website_ready'] != false;
    final hasReadyForm = forms.any(
      (form) => form['enabled'] == true && form['measurement_ready'] != false,
    );
    final active = enabled && websiteReady && hasReadyForm;
    final needsSetup = enabled && !active;
    final statusColor = paused || needsSetup
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
                    paused || needsSetup
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
                          : needsSetup
                          ? websiteReady
                                ? MetaCapiStrings.enableFormMeasurement
                                : MetaCapiStrings.configureWebsiteConsent
                          : MetaCapiStrings.off,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: paused || needsSetup
                            ? Theme.of(context).colorScheme.onSurface
                            : statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (paused)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  withStatusDate(MetaCapiStrings.credentials, pausedAt),
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
                Text(
                  '${MetaCapiStrings.invalidCount}: ${queue['invalid'] ?? 0}',
                ),
                Text('${MetaCapiStrings.expired}: ${queue['expired'] ?? 0}'),
              ],
            ),
            if (error != null && !(paused && error['code'] == 'credentials'))
              Text(withStatusDate(errorText, errorAt)),
            const SizedBox(height: 16),
            Text(
              forms.isEmpty ? MetaCapiStrings.noForms : MetaCapiStrings.forms,
            ),
            for (final item in forms)
              SwitchListTile(
                title: Text(item['title'] as String? ?? ''),
                subtitle:
                    item['enabled'] == true &&
                        item['measurement_ready'] == false
                    ? Text(MetaCapiStrings.formMeasurementRequired)
                    : null,
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

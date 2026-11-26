import 'package:fstapp/components/payments/payment_editor_registry.dart';
import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/components/unit/views/unit_admin_page.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/payments/payment_connection_api.dart';

import 'stripe_connection_strings.dart';

@RoutePage()
class UnitCardPaymentsPage extends StatelessWidget {
  const UnitCardPaymentsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final providers = managedPaymentEditors.toList();
    if (providers.isEmpty) return const SizedBox.shrink();
    final unitId = UnitAdministrationScope.of(context).unit.id!;
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              spacing: 16,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  StripeConnectionStrings.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(StripeConnectionStrings.text('intro')),
                for (final provider in providers)
                  Card(
                    key: ValueKey(provider.connector.id),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: UnitCardPaymentsView(
                        unitId: unitId,
                        canManage: true,
                        provider: provider,
                        api: SupabasePaymentConnectionApi(
                          connector: provider.connector,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UnitCardPaymentsView extends StatefulWidget {
  const UnitCardPaymentsView({
    super.key,
    required this.unitId,
    required this.canManage,
    required this.api,
    required this.provider,
    this.openExternal,
    this.connectSupported = kIsWeb,
  });
  final bool connectSupported;
  final int unitId;
  final bool canManage;
  final PaymentConnectionApi api;
  final PaymentEditorConnector provider;
  final Future<bool> Function(String url)? openExternal;
  @override
  State<UnitCardPaymentsView> createState() => _UnitCardPaymentsViewState();
}

class _UnitCardPaymentsViewState extends State<UnitCardPaymentsView>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _connection;
  bool _loading = true,
      _busy = false,
      _failed = false,
      _configurationRequired = false,
      _pending = false,
      _confirming = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(UnitCardPaymentsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unitId != widget.unitId ||
        oldWidget.canManage != widget.canManage) {
      _connection = null;
      _pending = false;
      _busy = false;
      _confirming = false;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (!widget.canManage) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
      _configurationRequired = false;
    });
    try {
      final value = await widget.api.status(widget.unitId);
      if (mounted && generation == _generation) {
        setState(() => _connection = value);
      }
    } on PaymentNotConfiguredException {
      if (mounted && generation == _generation) {
        setState(() {
          _configurationRequired = true;
          _connection = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    final unit = widget.unitId;
    setState(() => _busy = true);
    try {
      await operation();
    } on PaymentNotConfiguredException {
      if (mounted && widget.unitId == unit) {
        setState(() {
          _configurationRequired = true;
          _connection = null;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && widget.unitId == unit) setState(() => _failed = true);
    } finally {
      if (mounted && widget.unitId == unit) setState(() => _busy = false);
    }
  }

  Future<void> _openDashboard(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != widget.provider.dashboardHost ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      throw StateError('payment_dashboard_url_invalid');
    }
    return _open(uri);
  }

  Future<void> _open(Uri uri) async {
    final value = uri.toString();
    final opened =
        await (widget.openExternal?.call(value) ??
            LaunchUrlService.openExternalUrl(value, inCurrentWindow: true));
    if (!opened) throw StateError('payment_browser_unavailable');
  }

  Future<void> _connect({bool replace = false}) => _run(() async {
    if (!widget.connectSupported) return;
    final unit = widget.unitId, generation = _generation;
    final url = await widget.api.start(unit, replace: replace);
    if (!mounted ||
        widget.unitId != unit ||
        generation != _generation ||
        !widget.canManage) {
      return;
    }
    await _open(widget.provider.connector.authorizationUri(url.toString()));
    if (mounted && widget.unitId == unit && generation == _generation) {
      setState(() => _pending = true);
    }
  });
  Future<void> _pause(bool value) => _run(() async {
    final unit = widget.unitId;
    await widget.api.pause(unit, value);
    if (mounted && widget.unitId == unit) await _load();
  });
  Future<void> _disconnect() => _run(() async {
    final unit = widget.unitId, generation = _generation;
    final id = _connection?['connectionId'];
    if (id is! String) return;
    final impact = await widget.api.disconnectImpact(unit);
    if (!mounted ||
        generation != _generation ||
        widget.unitId != unit ||
        !widget.canManage ||
        impact['connectionId'] != id) {
      return;
    }
    final open = (impact['openAttempts'] as num?)?.toInt() ?? 0;
    setState(() => _confirming = true);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AppAlertDialog(
        onClose: () => Navigator.of(dialog).pop(false),
        title: Text(text('disconnect')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (impact['businessName'] is String)
                Text(impact['businessName']),
              const SizedBox(height: 12),
              Text(
                'CardPaymentConnection.disconnectOpen'.tr(
                  namedArgs: {'count': '$open'},
                ),
              ),
              Text(
                'CardPaymentConnection.disconnectHistory'.tr(
                  namedArgs: {'count': '${impact['historyCount'] ?? 0}'},
                ),
              ),
              const SizedBox(height: 12),
              Text(
                text(open > 0 ? 'disconnectBlocked' : 'disconnectExplanation'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(CommonStrings.close),
          ),
          if (open == 0)
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop(true),
              child: Text(text('disconnect')),
            ),
        ],
      ),
    );
    if (mounted && widget.unitId == unit) {
      setState(() => _confirming = false);
    }
    if (accepted != true ||
        !mounted ||
        generation != _generation ||
        widget.unitId != unit ||
        !widget.canManage) {
      return;
    }
    await widget.api.disconnect(unit, id);
    if (mounted && widget.unitId == unit) await _load();
  });
  String text(String key) => StripeConnectionStrings.text(key);
  @override
  Widget build(BuildContext context) {
    final connection = _connection;
    final ready =
        connection?['state'] == 'connected' &&
        connection?['modelVerified'] == true &&
        connection?['chargesEnabled'] == true &&
        connection?['cardPaymentsActive'] == true;
    final revoked = connection?['state'] == 'revoked';
    final disconnectPending = connection?['disconnectState'] != null;
    final paused = connection?['paused'] == true;
    final statusFailed =
        _failed || (connection?['statusFailures'] as num? ?? 0) > 0;
    final statusKey = switch (connection?['disconnectState']) {
      'uncertain' => 'disconnectUncertain',
      final Object _ => 'disconnectPending',
      _ when _configurationRequired => 'notConfigured',
      _ when statusFailed => 'unknown',
      _ when _pending => 'waiting',
      _ when revoked => 'revoked',
      _ when paused => 'paused',
      _ when ready => 'receiving',
      _ when connection != null => 'restricted',
      _ when !_loading => 'notConnected',
      _ => null,
    };
    final dashboardUrl = connection?['dashboardUrl'];
    final hasDashboard =
        widget.provider.dashboardHost != null && dashboardUrl is String;
    final checkedAt = connection?['checkedAt'];
    final checked = checkedAt is String ? DateTime.tryParse(checkedAt) : null;
    final canChange = !_busy && !_loading && !disconnectPending;
    final canConnect =
        canChange && !_configurationRequired && widget.connectSupported;
    final theme = Theme.of(context);

    return Column(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Semantics(
              header: true,
              child: Text(
                widget.provider.name,
                style: theme.textTheme.titleLarge,
              ),
            ),
            if (connection?['businessName'] case final String name
                when name.trim().isNotEmpty)
              Text(name),
          ],
        ),
        if (!widget.canManage)
          Text(text('managerRequired'))
        else ...[
          if (_loading || (_busy && !_confirming))
            const LinearProgressIndicator(),
          if (statusKey != null)
            Semantics(
              liveRegion: true,
              child: Text(text(statusKey), style: theme.textTheme.titleSmall),
            ),
          if (!statusFailed &&
              !paused &&
              !disconnectPending &&
              !revoked &&
              ready &&
              connection?['payoutsEnabled'] != true)
            Text(text('payoutsAttention')),
          if (checked != null)
            Text(
              '${text('lastChecked')}: ${DateFormat.yMd(context.locale.toLanguageTag()).add_jm().format(checked.toLocal())}',
              style: theme.textTheme.bodySmall,
            ),
          if (!widget.connectSupported) Text(text('nativeConnectUnavailable')),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hasDashboard)
                FilledButton.tonal(
                  onPressed: _busy
                      ? null
                      : () => _run(() => _openDashboard(dashboardUrl)),
                  child: Text(text('dashboard')),
                ),
              if (connection == null || revoked)
                if (!_loading && !_failed)
                  FilledButton(
                    onPressed: canConnect ? () => _connect() : null,
                    child: Text(text('connect')),
                  ),
              if (connection != null && !revoked) ...[
                OutlinedButton(
                  onPressed: canChange ? () => _pause(!paused) : null,
                  child: Text(text(paused ? 'resume' : 'pause')),
                ),
                TextButton(
                  onPressed: canConnect ? () => _connect(replace: true) : null,
                  child: Text(text('replace')),
                ),
                if (connection['connectionId'] is String)
                  TextButton(
                    onPressed: canChange ? _disconnect : null,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: Text(text('disconnect')),
                  ),
              ],
              TextButton.icon(
                onPressed: _loading || _busy ? null : _load,
                icon: const Icon(Icons.refresh),
                label: Text(text('reload')),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

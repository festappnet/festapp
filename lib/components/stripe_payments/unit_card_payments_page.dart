import 'stripe_feature.dart';
import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/components/unit/views/unit_admin_page.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'stripe_connection_api.dart';
import 'stripe_connection_strings.dart';

@RoutePage()
class UnitCardPaymentsPage extends StatelessWidget {
  const UnitCardPaymentsPage({super.key});
  @override
  Widget build(BuildContext context) => !StripeFeature.visible
      ? const SizedBox.shrink()
      : UnitCardPaymentsView(
          unitId: UnitAdministrationScope.of(context).unit.id!,
          canManage: StripeFeature.canManage,
          api: const SupabaseStripeConnectionApi(),
        );
}

class UnitCardPaymentsView extends StatefulWidget {
  const UnitCardPaymentsView(
      {super.key,
      required this.unitId,
      required this.canManage,
      required this.api,
      this.openExternal,
      this.connectSupported = kIsWeb});
  final bool connectSupported;
  final int unitId;
  final bool canManage;
  final StripeConnectionApi api;
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
    } on StripeNotConfiguredException {
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
    } on StripeNotConfiguredException {
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

  Future<void> _open(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        !{'connect.stripe.com', 'dashboard.stripe.com'}.contains(uri.host) ||
        uri.userInfo.isNotEmpty) {
      throw StateError('invalid_stripe_url');
    }
    final opened = await (widget.openExternal?.call(value) ??
        LaunchUrlService.openExternalUrl(value, inCurrentWindow: true));
    if (!opened) throw StateError('stripe_browser_unavailable');
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
        setState(() => _pending = true);
        await _open(url.toString());
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
                          Text('CardPaymentConnection.disconnectOpen'
                              .tr(namedArgs: {'count': '$open'})),
                          Text('CardPaymentConnection.disconnectHistory'.tr(
                              namedArgs: {
                                'count': '${impact['historyCount'] ?? 0}'
                              })),
                          const SizedBox(height: 12),
                          Text(text(open > 0
                              ? 'disconnectBlocked'
                              : 'disconnectExplanation')),
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(dialog).pop(false),
                          child: Text(CommonStrings.close)),
                      if (open == 0)
                        FilledButton(
                            onPressed: () => Navigator.of(dialog).pop(true),
                            child: Text(text('disconnect'))),
                    ]));
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
    final ready = connection?['state'] == 'connected' &&
        connection?['modelVerified'] == true &&
        connection?['chargesEnabled'] == true &&
        connection?['cardPaymentsActive'] == true;
    final revoked = connection?['state'] == 'revoked';
    final disconnectPending = connection?['disconnectState'] != null;
    String statusKey = revoked
        ? 'revoked'
        : connection?['paused'] == true
            ? 'paused'
            : ready
                ? 'receiving'
                : 'restricted';
    Widget line(String value) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(value, style: Theme.of(context).textTheme.bodyLarge));
    return SingleChildScrollView(
        child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(StripeConnectionStrings.title,
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 24),
                          line(text('intro')),
                          if (!widget.canManage)
                            line(text('managerRequired'))
                          else ...[
                            if (_loading) const LinearProgressIndicator(),
                            if (_busy && !_loading && !_confirming)
                              const LinearProgressIndicator(),
                            if (_configurationRequired)
                              Semantics(
                                  liveRegion: true,
                                  child: line(text('notConfigured'))),
                            if (_failed)
                              Semantics(
                                  liveRegion: true,
                                  child: line(text('unknown'))),
                            if (_pending)
                              Semantics(
                                  liveRegion: true,
                                  child: line(text('waiting'))),
                            if (connection != null) ...[
                              if (connection['businessName'] is String)
                                line(connection['businessName']),
                              Semantics(
                                  liveRegion: true,
                                  child: line(text(statusKey))),
                              if (disconnectPending)
                                line(text(
                                    connection['disconnectState'] == 'uncertain'
                                        ? 'disconnectUncertain'
                                        : 'disconnectPending')),
                              if ((connection['statusFailures'] as num? ?? 0) >
                                  0)
                                line(text('unknown')),
                              if (connection['paused'] == true &&
                                  !ready &&
                                  !revoked)
                                line(text('restricted')),
                              if (!revoked &&
                                  connection['chargesEnabled'] == true &&
                                  connection['payoutsEnabled'] != true)
                                line(text('payoutsAttention'))
                              else if (!revoked &&
                                  connection['payoutsEnabled'] == true)
                                line(text('payoutsActive')),
                              if (connection['checkedAt'] is String &&
                                  DateTime.tryParse(connection['checkedAt']) !=
                                      null)
                                line(
                                    '${text('lastChecked')}: ${DateFormat.yMd(context.locale.toLanguageTag()).add_Hm().format(DateTime.parse(connection['checkedAt']).toLocal())}'),
                              if (connection['dashboardUrl'] is String)
                                OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(() =>
                                            _open(connection['dashboardUrl'])),
                                    child: Text(text('dashboard'))),
                              if (!revoked)
                                FilledButton(
                                    onPressed: _busy || disconnectPending
                                        ? null
                                        : () => _pause(
                                            connection['paused'] != true),
                                    child: Text(text(
                                        connection['paused'] == true
                                            ? 'resume'
                                            : 'pause'))),
                              TextButton(
                                  onPressed: _busy ||
                                          disconnectPending ||
                                          !widget.connectSupported
                                      ? null
                                      : () => _connect(replace: !revoked),
                                  child: Text(
                                      text(revoked ? 'connect' : 'replace'))),
                              if (!revoked &&
                                  connection['connectionId'] is String)
                                TextButton(
                                    onPressed: _busy || disconnectPending
                                        ? null
                                        : _disconnect,
                                    child: Text(text('disconnect'))),
                            ] else if (!_loading && !_failed)
                              FilledButton(
                                  onPressed: _busy ||
                                          _configurationRequired ||
                                          !widget.connectSupported
                                      ? null
                                      : () => _connect(),
                                  child: Text(text('connect'))),
                            if (!widget.connectSupported)
                              line(text('nativeConnectUnavailable')),
                            TextButton(
                                onPressed: _loading || _busy ? null : _load,
                                child: Text(text('reload'))),
                          ],
                        ])))));
  }
}

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'stripe_connection_api.dart';
import 'stripe_connection_callback_owner.dart';
import 'stripe_connection_strings.dart';
import 'stripe_connection_browser_stub.dart'
    if (dart.library.html) 'stripe_connection_browser_web.dart'
    if (dart.library.js_interop) 'stripe_connection_browser_web.dart';

@RoutePage()
class StripeConnectCallbackPage extends StatelessWidget {
  const StripeConnectCallbackPage(
      {super.key,
      @QueryParam('code') this.code,
      @QueryParam('state') this.state,
      @QueryParam('error') this.error});
  final String? code, state, error;
  @override
  Widget build(BuildContext context) =>
      StripeConnectCallbackView(code: code, state: state, error: error);
}

class StripeConnectCallbackView extends StatefulWidget {
  const StripeConnectCallbackView(
      {super.key,
      this.code,
      this.state,
      this.error,
      this.callbackOwner,
      this.api,
      this.isLoggedIn});
  final String? code, state, error;
  final StripeConnectionCallbackOwner? callbackOwner;
  final StripeConnectionApi? api;
  final bool Function()? isLoggedIn;
  @override
  State<StripeConnectCallbackView> createState() =>
      _StripeConnectCallbackViewState();
}

class _StripeConnectCallbackViewState extends State<StripeConnectCallbackView> {
  Map<String, String>? _callback;
  StripeConnectionCallbackOwner get _owner =>
      widget.callbackOwner ?? StripeConnectionCallbackOwner.instance;
  bool get _loggedIn => widget.isLoggedIn?.call() ?? AuthService.isLoggedIn();
  bool _busy = false, _failed = false, _cancelled = false, _complete = false;
  int? _unit;
  @override
  void initState() {
    super.initState();
    _callback = _owner.retain(consumeStripeConnectionCallback() ??
        {
          if (widget.code != null) 'code': widget.code!,
          if (widget.state != null) 'state': widget.state!,
          if (widget.error != null) 'error': widget.error!,
        });
    WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
  }

  Future<void> _finish() async {
    if (!mounted || _busy || _complete || !_loggedIn) return;
    final callback = _callback;
    if (callback == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await (widget.api ?? const SupabaseStripeConnectionApi())
          .complete(callback);
      if (result['connected'] == true || result['status'] == 'cancelled') {
        _owner.complete(callback);
        _callback = null;
      }
      if (!mounted) return;
      setState(() {
        _unit = result['unitId'] is int ? result['unitId'] : null;
        _cancelled = result['status'] == 'cancelled';
        _complete = result['connected'] == true || _cancelled;
        _failed = !_complete;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                          spacing: 16,
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(StripeConnectionStrings.text('callbackTitle'),
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            if (_busy) const LinearProgressIndicator(),
                            Semantics(
                                liveRegion: true,
                                child: Text(StripeConnectionStrings.text(_failed
                                    ? 'callbackFailed'
                                    : _cancelled
                                        ? 'cancelled'
                                        : _complete
                                            ? 'connected'
                                            : 'waiting'))),
                            if (!_loggedIn)
                              TextButton(
                                  onPressed: () async {
                                    await context.router.push(LoginRoute(
                                        redirect: '/stripe/connect/callback'));
                                    if (mounted) _finish();
                                  },
                                  child: Text(
                                      StripeConnectionStrings.text('signIn'))),
                            if (_failed && !_busy && _loggedIn)
                              TextButton(
                                  onPressed: _finish,
                                  child: Text(
                                      StripeConnectionStrings.text('reload'))),
                            if (_unit != null)
                              FilledButton(
                                  onPressed: () => context.router.replace(
                                          UnitAdminRoute(id: _unit, children: [
                                        UnitAdministrationTabsRoute(children: [
                                          const UnitCardPaymentsRoute()
                                        ])
                                      ])),
                                  child: Text(StripeConnectionStrings.title)),
                          ]))))));
}

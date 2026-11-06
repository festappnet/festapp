import 'package:material_ui/material_ui.dart';
import 'package:festapp_core/payments.dart';
import 'package:fstapp/components/forms/card_payment_strings.dart';
import 'package:fstapp/components/forms/widgets_view/card_payment_status.dart';
import 'package:fstapp/services/launch_url_service.dart';

import 'payment_gateway.dart';

class PaymentAccessView extends StatefulWidget {
  const PaymentAccessView({
    super.key,
    required this.token,
    required this.gateway,
    required this.connector,
    this.rememberPayment,
    this.returnOnly = false,
    this.handoff = false,
    this.paymentSurface,
    this.openCheckout,
  });
  final String token;
  final PaymentGateway gateway;
  final PaymentConnector connector;
  final void Function(String)? rememberPayment;
  final bool returnOnly;
  final bool handoff;
  final String Function()? paymentSurface;
  final Future<bool> Function(String)? openCheckout;
  @override
  State<PaymentAccessView> createState() => _PaymentAccessViewState();
}

class _PaymentAccessViewState extends State<PaymentAccessView>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _payment;
  bool _busy = false, _failed = false;
  int _generation = 0;
  String get _surface => widget.paymentSurface?.call() ?? 'native';
  bool get _invalidHandoff =>
      widget.handoff && (widget.returnOnly || _surface != 'web');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read();
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(PaymentAccessView old) {
    super.didUpdateWidget(old);
    if (old.token != widget.token ||
        old.returnOnly != widget.returnOnly ||
        old.handoff != widget.handoff ||
        old.paymentSurface != widget.paymentSurface ||
        old.connector.id != widget.connector.id ||
        old.gateway != widget.gateway) {
      _generation++;
      _payment = null;
      _busy = false;
      _read();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _read();
  }

  Future<void> _read() async {
    if (_busy || _invalidHandoff) return;
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final payment = widget.handoff
          ? await widget.gateway.readHandoff(widget.token)
          : await widget.gateway.read(
              widget.token,
              returnOnly: widget.returnOnly,
            );
      if (mounted && generation == _generation) {
        setState(() {
          _payment = payment;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _pay() async {
    if (_invalidHandoff || _surface == 'embed')
      throw StateError('payment_handoff_required');
    if (_busy || widget.returnOnly) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final result = widget.handoff
          ? await widget.gateway.prepareHandoff(widget.token)
          : await widget.gateway.prepare(widget.token);
      if (!mounted || generation != _generation) return;
      final payment = result['payment'];
      if (payment is! Map || payment['method'] != widget.connector.id) {
        throw StateError('payment_payment_unavailable');
      }
      setState(() => _payment = payment.cast<String, dynamic>());
      final target = result['checkoutUrl'];
      if (target == null) return;
      final uri = widget.connector.checkoutUri(target.toString());
      // A one-use handoff must never become a recoverable order-pay capability.
      if (!widget.handoff) widget.rememberPayment?.call(widget.token);
      final opened =
          await (widget.openCheckout?.call(uri.toString()) ??
              LaunchUrlService.openExternalUrl(
                uri.toString(),
                inCurrentWindow: true,
              ));
      if (!opened) throw StateError('payment_browser_unavailable');
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
      rethrow;
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _invalidHandoff
      ? Text(CardPaymentStrings.text('protectedPaymentLink'))
      : SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                CardPaymentStrings.text('title'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              if (_busy) const LinearProgressIndicator(),
              if (_payment != null)
                CardPaymentStatus(
                  payment: {..._payment!, if (_failed) 'status': 'unknown'},
                  onPay: widget.returnOnly || _failed || _surface == 'embed'
                      ? null
                      : _pay,
                  onRefresh: _read,
                )
              else ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    CardPaymentStrings.text(_failed ? 'unknown' : 'preparing'),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _read,
                  child: Text(CardPaymentStrings.text('refresh')),
                ),
              ],
            ],
          ),
        );
}

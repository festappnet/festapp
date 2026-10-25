import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/forms/card_payment_strings.dart';
import 'package:fstapp/components/forms/widgets_view/card_payment_status.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'stripe_payment_api.dart';
import 'stripe_payment_browser_stub.dart'
    if (dart.library.html) 'stripe_payment_browser_web.dart'
    if (dart.library.js_interop) 'stripe_payment_browser_web.dart';

@RoutePage()
class StripePayPage extends StatelessWidget {
  const StripePayPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const _StripeLinkPage(returnOnly: false);
}

@RoutePage()
class StripeReturnPage extends StatelessWidget {
  const StripeReturnPage({super.key});
  @override
  Widget build(BuildContext context) => const _StripeLinkPage(returnOnly: true);
}

class _StripeLinkPage extends StatefulWidget {
  const _StripeLinkPage({required this.returnOnly});
  final bool returnOnly;
  @override
  State<_StripeLinkPage> createState() => _StripeLinkPageState();
}

class _StripeLinkPageState extends State<_StripeLinkPage> {
  Map<String, String>? _link;
  @override
  void initState() {
    super.initState();
    _link = consumeStripePaymentLink(
        expectedKind: widget.returnOnly ? 'return' : 'pay');
    stripePaymentLinkChanges?.addListener(_captureResumedLink);
  }

  void _captureResumedLink() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final link = consumeStripePaymentLink(
        expectedKind: widget.returnOnly ? 'return' : 'pay');
    if (link != null) setState(() => _link = link);
  }

  @override
  void dispose() {
    stripePaymentLinkChanges?.removeListener(_captureResumedLink);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = _link?['token'];
    final kind = _link?['kind'];
    final handoff = kind == 'handoff';
    final valid = token != null &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(token) &&
        (widget.returnOnly
            ? kind == 'return'
            : kind == 'pay' || (handoff && stripePaymentSurface() == 'web'));
    return Scaffold(
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: valid
                            ? StripePaymentAccessView(
                                token: token,
                                returnOnly: widget.returnOnly,
                                handoff: handoff,
                                gateway: const SupabaseStripePaymentGateway())
                            : Text(CardPaymentStrings.text(
                                'protectedPaymentLink')))))));
  }
}

class StripePaymentAccessView extends StatefulWidget {
  const StripePaymentAccessView(
      {super.key,
      required this.token,
      required this.gateway,
      this.returnOnly = false,
      this.handoff = false,
      this.paymentSurface,
      this.openCheckout});
  final String token;
  final StripePaymentGateway gateway;
  final bool returnOnly;
  final bool handoff;
  final String Function()? paymentSurface;
  final Future<bool> Function(String)? openCheckout;
  @override
  State<StripePaymentAccessView> createState() =>
      _StripePaymentAccessViewState();
}

class _StripePaymentAccessViewState extends State<StripePaymentAccessView>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _payment;
  bool _busy = false, _failed = false;
  int _generation = 0;
  String get _surface =>
      widget.paymentSurface?.call() ?? stripePaymentSurface();
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
  void didUpdateWidget(StripePaymentAccessView old) {
    super.didUpdateWidget(old);
    if (old.token != widget.token ||
        old.returnOnly != widget.returnOnly ||
        old.handoff != widget.handoff ||
        old.paymentSurface != widget.paymentSurface) {
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
          : await widget.gateway
              .read(widget.token, returnOnly: widget.returnOnly);
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
      throw StateError('stripe_handoff_required');
    if (_busy || widget.returnOnly) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final result = widget.handoff
          ? await widget.gateway.prepareHandoff(widget.token)
          : await widget.gateway.prepare(widget.token);
      if (!mounted || generation != _generation) return;
      final payment = result['payment'];
      if (payment is! Map || payment['method'] != 'stripe') {
        throw StateError('stripe_payment_unavailable');
      }
      setState(() => _payment = payment.cast<String, dynamic>());
      final target = result['checkoutUrl'];
      if (target == null) return;
      final uri = Uri.parse(target.toString());
      if (uri.scheme != 'https' ||
          uri.host != 'checkout.stripe.com' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort) {
        throw StateError('stripe_checkout_url_invalid');
      }
      // A one-use handoff must never become a recoverable order-pay capability.
      if (!widget.handoff) rememberStripePaymentLink(widget.token);
      final opened = await (widget.openCheckout?.call(uri.toString()) ??
          LaunchUrlService.openExternalUrl(uri.toString(),
              inCurrentWindow: true));
      if (!opened) throw StateError('stripe_browser_unavailable');
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(CardPaymentStrings.text('title'),
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          if (_busy) const LinearProgressIndicator(),
          if (_payment != null)
            CardPaymentStatus(
                payment: {..._payment!, if (_failed) 'status': 'unknown'},
                onPay: widget.returnOnly || _failed || _surface == 'embed'
                    ? null
                    : _pay,
                onRefresh: _read)
          else ...[
            Semantics(
                liveRegion: true,
                child: Text(CardPaymentStrings.text(
                    _failed ? 'unknown' : 'preparing'))),
            TextButton(
                onPressed: _busy ? null : _read,
                child: Text(CardPaymentStrings.text('refresh'))),
          ],
        ]));
}

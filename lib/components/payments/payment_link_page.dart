import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:festapp_core/payments.dart';
import 'package:fstapp/components/forms/card_payment_strings.dart';

import 'payment_gateway.dart';
import 'payment_access_view.dart';
import 'payment_browser_stub.dart'
    if (dart.library.html) 'payment_browser_web.dart'
    if (dart.library.js_interop) 'payment_browser_web.dart';

@RoutePage()
class PaymentPayPage extends StatelessWidget {
  const PaymentPayPage({
    super.key,
    @PathParam('provider') required this.providerId,
  });
  final String providerId;
  @override
  Widget build(BuildContext context) => PaymentLinkPage(
    key: ValueKey(providerId),
    connector: paymentConnectors.get(providerId),
    returnOnly: false,
  );
}

@RoutePage()
class PaymentReturnPage extends StatelessWidget {
  const PaymentReturnPage({
    super.key,
    @PathParam('provider') required this.providerId,
  });
  final String providerId;
  @override
  Widget build(BuildContext context) => PaymentLinkPage(
    key: ValueKey(providerId),
    connector: paymentConnectors.get(providerId),
    returnOnly: true,
  );
}

class PaymentLinkPage extends StatefulWidget {
  const PaymentLinkPage({
    super.key,
    required this.connector,
    required this.returnOnly,
  });
  final PaymentConnector? connector;
  final bool returnOnly;
  @override
  State<PaymentLinkPage> createState() => _PaymentLinkPageState();
}

class _PaymentLinkPageState extends State<PaymentLinkPage> {
  Map<String, String>? _link;
  Map<String, String>? _consume() => widget.connector == null
      ? null
      : consumePaymentLink(
          expectedKind: widget.returnOnly ? 'return' : 'pay',
          expectedProvider: widget.connector!.id,
        );
  @override
  void initState() {
    super.initState();
    _link = _consume();
    paymentLinkChanges?.addListener(_capture);
  }

  void _capture() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final link = _consume();
    if (link != null) setState(() => _link = link);
  }

  @override
  void dispose() {
    paymentLinkChanges?.removeListener(_capture);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = _link?['token'], kind = _link?['kind'];
    final connector = widget.connector;
    final handoff = kind == 'handoff';
    final valid =
        connector != null &&
        _link?['provider'] == connector.id &&
        token != null &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(token) &&
        (widget.returnOnly
            ? kind == 'return'
            : kind == 'pay' || (handoff && paymentSurface() == 'web'));
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: valid
                  ? PaymentAccessView(
                      token: token,
                      connector: connector,
                      returnOnly: widget.returnOnly,
                      handoff: handoff,
                      paymentSurface: paymentSurface,
                      rememberPayment: (token) =>
                          rememberPaymentLink(token, connector: connector),
                      gateway: SupabasePaymentGateway(connector),
                    )
                  : Text(CardPaymentStrings.text('protectedPaymentLink')),
            ),
          ),
        ),
      ),
    );
  }
}

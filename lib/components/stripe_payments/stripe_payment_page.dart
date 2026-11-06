import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:festapp_core/payments.dart';
import 'package:fstapp/components/payments/payment_link_page.dart';

// External compatibility routes for previously issued Stripe links.
@RoutePage()
class StripePayPage extends StatelessWidget {
  const StripePayPage({super.key});
  @override
  Widget build(BuildContext context) => const PaymentLinkPage(
    connector: stripePaymentConnector,
    returnOnly: false,
  );
}

@RoutePage()
class StripeReturnPage extends StatelessWidget {
  const StripeReturnPage({super.key});
  @override
  Widget build(BuildContext context) => const PaymentLinkPage(
    connector: stripePaymentConnector,
    returnOnly: true,
  );
}

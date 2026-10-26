import '../models/verified_organization_identity.dart';
import '../widgets_view/organization_identity_footer.dart';
import 'package:fstapp/components/forms/order_overview_strings.dart';
import '../waitlist_strings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/theme_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/forms/public_order_strings.dart';
import 'package:fstapp/components/forms/widgets_view/payment_qr_card.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import '../widgets_view/card_payment_status.dart';
import '../payment_method_strings.dart';
import 'package:fstapp/components/stripe_payments/stripe_payment_api.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'package:fstapp/components/stripe_payments/stripe_payment_browser_stub.dart'
    if (dart.library.html) 'package:fstapp/components/stripe_payments/stripe_payment_browser_web.dart'
    if (dart.library.js_interop) 'package:fstapp/components/stripe_payments/stripe_payment_browser_web.dart';

class FinishOrderScreen extends StatefulWidget {
  final Future<FunctionResponse> Function() orderFutureFunction;
  final VoidCallback? onSuccess;
  final VoidCallback? onOrderConfirmed;
  final String? tone;
  final VerifiedOrganizationIdentity? organizationIdentity;
  final bool hasTickets;
  final bool overviewAvailable;
  final String? occasionTitle;
  final Future<String?> Function(String)? deliveryStatusReader;
  final Future<void> Function()? onContinuePayment;
  final VoidCallback? onRefreshPayment;

  const FinishOrderScreen({
    super.key,
    required this.orderFutureFunction,
    this.onSuccess,
    this.onOrderConfirmed,
    this.tone,
    this.organizationIdentity,
    this.hasTickets = true,
    this.overviewAvailable = false,
    this.occasionTitle,
    this.deliveryStatusReader,
    this.onContinuePayment,
    this.onRefreshPayment,
  });

  @override
  _FinishOrderScreenState createState() => _FinishOrderScreenState();
}

class _FinishOrderScreenState extends State<FinishOrderScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _isSuccess = false;
  bool _isLoading = true;
  int? code;
  Map<String, dynamic>? _errorProduct;
  Map<String, dynamic>? _orderData;
  String _deliveryState = 'queued';
  bool _successCloseNotified = false;

  void _notifySuccessAfterClose() {
    if (!_isSuccess || _successCloseNotified) return;
    _successCloseNotified = true;
    final callback = widget.onSuccess;
    WidgetsBinding.instance.addPostFrameCallback((_) => callback?.call());
  }

  late AnimationController _mainController;
  late AnimationController _loadingController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mainController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _loadingController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainController, curve: Curves.easeOutBack),
    );
    _executeOrder();
  }

  Future<void> _executeOrder() async {
    final start = DateTime.now();
    try {
      final result = await widget.orderFutureFunction();
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      code = int.tryParse(
            result.data["code"].toString().replaceAll(RegExp(r'\D'), ''),
          ) ??
          0;
      _isSuccess = code == 200;
      _orderData = (result.data is Map)
          ? (result.data as Map).cast<String, dynamic>()
          : null;
      if (code == 1017) _errorProduct = result.data["product"];
      if (_isSuccess) {
        widget.onOrderConfirmed?.call();
      }
      if (_isSuccess && elapsed < 1000) {
        await Future.delayed(Duration(milliseconds: 1000 - elapsed));
      }
    } catch (_) {
      _isSuccess = false;
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
    _loadingController.stop();
    _mainController.forward();
    if (_isSuccess && _orderData?['payment']?['method'] != 'stripe') {
      _observeDelivery();
    }
    if (_isSuccess &&
        _orderData?['payment']?['method'] == 'stripe' &&
        _payToken != null &&
        _orderData?['checkout_url'] is String) {
      try {
        await _openCardCheckout(_orderData!['checkout_url']);
      } catch (_) {
        if (mounted)
          setState(() => _orderData!['payment'] = {
                ...?_orderData?['payment'],
                'status': 'unknown'
              });
      }
    }
  }

  String? get _payToken {
    if (_orderData?['payment_access']?['kind'] == 'handoff') return null;
    final value = _orderData?['payment_access']?['token'];
    return value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value)
        ? value
        : null;
  }

  bool _readingPayment = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_isLoading &&
        _payToken != null) {
      _refreshCardPayment();
    }
  }

  Future<void> _refreshCardPayment() async {
    final token = _payToken;
    if (token == null || _readingPayment) return;
    _readingPayment = true;
    try {
      final payment = await const SupabaseStripePaymentGateway().read(token);
      if (mounted) setState(() => _orderData!['payment'] = payment);
    } catch (_) {
      if (mounted)
        setState(() => _orderData!['payment'] = {
              ...?_orderData?['payment'],
              'status': 'unknown'
            });
    } finally {
      _readingPayment = false;
    }
  }

  Future<void> _openCardCheckout(String value) async {
    if (stripePaymentSurface() == 'embed')
      throw StateError('stripe_handoff_required');
    final uri = Uri.parse(value);
    if (uri.scheme != 'https' ||
        uri.host != 'checkout.stripe.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      throw StateError('stripe_checkout_url_invalid');
    }
    final token = _payToken;
    if (token != null) {
      rememberStripePaymentLink(token,
          payUrl: _orderData?['payment_access']?['url']);
    }
    if (!await LaunchUrlService.openExternalUrl(uri.toString(),
        inCurrentWindow: true)) {
      throw StateError('stripe_browser_unavailable');
    }
  }

  Future<void> _continueCardPayment() async {
    final token = _payToken;
    if (token == null || _readingPayment) return;
    _readingPayment = true;
    try {
      final result = await const SupabaseStripePaymentGateway().prepare(token);
      if (!mounted) return;
      if (result['payment'] is Map) {
        setState(() => _orderData!['payment'] = result['payment']);
      }
      if (result['checkoutUrl'] is String) {
        await _openCardCheckout(result['checkoutUrl']);
      }
    } finally {
      _readingPayment = false;
    }
  }

  Future<void> _observeDelivery() async {
    final capability = _orderData?['delivery_receipt'];
    if (capability is! String) return;
    final start = DateTime.now();
    for (var attempt = 0;
        attempt < 5 &&
            mounted &&
            DateTime.now().difference(start).inSeconds < 15;
        attempt++) {
      if (WidgetsBinding.instance.lifecycleState != null &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed)
        break;
      try {
        final String? state;
        if (widget.deliveryStatusReader != null) {
          state = await widget.deliveryStatusReader!(capability);
        } else {
          final response = await Supabase.instance.client.functions.invoke(
              'email-confirmation-status',
              body: {'capability': capability});
          state =
              response.data is Map ? response.data['state'] as String? : null;
        }
        if (!mounted) return;
        if (state == 'accepted') setState(() => _deliveryState = 'accepted');
        if ([
          'delivered',
          'invalid_email',
          'failed',
          'unknown',
          'dead',
          'suppressed',
          'expired',
          'cancelled',
          'retry_wait'
        ].contains(state)) {
          setState(() => _deliveryState = state as String);
          return;
        }
      } catch (_) {
        return;
      }
      if (attempt < 4)
        await Future<void>.delayed(const Duration(milliseconds: 2500));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mainController.dispose();
    _loadingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: PopScope(
        canPop: true,
        onPopInvoked: (didPop) {
          if (didPop) _notifySuccessAfterClose();
        },
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: _isLoading ? _buildLoading() : _buildResult(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return AnimatedBuilder(
      animation: _loadingController,
      builder: (context, child) => Transform.scale(
        scale: 1.0 + _loadingController.value * 0.2,
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[300],
          ),
          child: Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).primaryColor,
              strokeWidth: 4.0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResult() {
    final payment = _orderData?['payment'];
    final handoff = _orderData?['payment_access']?['kind'] == 'handoff';
    final handoffUri = handoff && stripePaymentSurface() == 'embed'
        ? stripeHandoffUri(_orderData?['payment_access']?['url'],
            _orderData?['payment_access']?['token'])
        : null;
    if (_isSuccess && payment is Map && payment['method'] == 'stripe') {
      return SingleChildScrollView(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_orderData?['ticketOrder']?['order']?['order_symbol'] is String)
            SelectableText(_orderData!['ticketOrder']['order']['order_symbol']),
          CardPaymentStatus(
            payment: {
              ...payment.cast<String, dynamic>(),
            },
            onPay: handoff
                ? null
                : widget.onContinuePayment ??
                    (_payToken == null ? null : _continueCardPayment),
            onRefresh: handoff
                ? null
                : widget.onRefreshPayment ??
                    (_payToken == null ? null : _refreshCardPayment),
          ),
          if (handoffUri != null)
            FilledButton(
                onPressed: () =>
                    LaunchUrlService.openExternalUrl(handoffUri.toString()),
                child: Text(PaymentMethodStrings.text('continueInNewTab'))),
          OrganizationIdentityFooter(identity: widget.organizationIdentity),
          OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _notifySuccessAfterClose();
              },
              child: Text(widget.overviewAvailable
                  ? OrderOverviewStrings.text('title')
                  : PublicOrderStrings.backToForm)),
        ],
      ));
    }
    String title, subtitle;
    if (_isSuccess) {
      title = PublicOrderStrings.successTitle(
        widget.tone,
        hasTickets: widget.hasTickets,
      );
      final email = ((_orderData?['ticketOrder'] as Map?)?['order']
          as Map?)?['data']?['email'];
      final formData = (((_orderData?['form'] ??
              (_orderData?['ticketOrder'] as Map?)?['order']?['form'])
          as Map?)?['data'] as Map?);
      final hasPayment = _orderData?['payment_qr'] is Map &&
          formData?[FeatureConstants.formShowPaymentQr]?.toString() == 'true';
      subtitle = PublicOrderStrings.confirmationInfo(widget.tone,
          hasPayment: hasPayment,
          email: email is String ? email.trim() : '',
          state: _deliveryState);
    } else if (_orderData?['errorCode'] == 'STRIPE_RECIPIENT_CHANGED') {
      title = PaymentMethodStrings.reason('recipient_changed');
      subtitle = WaitlistStrings.refresh;
    } else if (_orderData?['errorCode'] == 'STRIPE_PRICE_CHANGED') {
      title = PaymentMethodStrings.text('priceChanged');
      subtitle = PaymentMethodStrings.text('reviewPrices');
    } else if (code == 1017) {
      final prodTitle = _errorProduct?["title"] ?? "";
      title = PublicOrderStrings.productUnavailable(prodTitle);
      subtitle = PublicOrderStrings.chooseDifferentVariant(widget.tone);
    } else {
      title = PublicOrderStrings.orderFailed;
      subtitle = _orderData?['errorCode'] != null
          ? WaitlistStrings.text(_orderData!['errorCode'])
          : PublicOrderStrings.orderError((code ?? 0).toString());
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isSuccess
                    ? ThemeConfig.darkGreen
                    : ThemeConfig.redColor(context),
              ),
              child: Icon(
                _isSuccess ? Icons.check_circle : Icons.error,
                size: 80,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  // Use Theme text style
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _isSuccess
                      ? ThemeConfig.darkGreen
                      : ThemeConfig.redColor(context),
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  // Use Theme text style
                  fontSize: 14,
                  color: ThemeConfig.blackColor(context).withOpacity(0.7),
                ),
            textAlign: TextAlign.center,
          ),
          if (_isSuccess &&
              _orderData?['ticketOrder']?['order']?['order_symbol'] is String)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SelectableText(
                  '${OrdersStrings.gridOrderSymbol}: ${_orderData!['ticketOrder']['order']['order_symbol']}'),
            ),
          if (_isSuccess && _orderData?['conversion'] == 'split')
            Text(
                '${WaitlistStrings.remaining}: ${_orderData?['waitlistSummary']?['pendingPlaces'] ?? 0}. ${WaitlistStrings.explanation}'),
          if (_isSuccess) _buildPaymentQr(),
          if (handoffUri != null)
            FilledButton(
                onPressed: () =>
                    LaunchUrlService.openExternalUrl(handoffUri.toString()),
                child: Text(PaymentMethodStrings.text('continueInNewTab'))),
          OrganizationIdentityFooter(identity: widget.organizationIdentity),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _notifySuccessAfterClose();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
            child: Text(_isSuccess && widget.overviewAvailable
                ? OrderOverviewStrings.text('title')
                : PublicOrderStrings.backToForm),
          ),
        ],
      ),
    );
  }

  /// Renders the "Scan to pay" card when the form enabled `show_payment_qr`
  /// and the order response carries a currency-aware `payment_qr` block.
  Widget _buildPaymentQr() {
    final data = _orderData;
    if (data == null) return const SizedBox.shrink();
    final pq = (data['payment_qr'] as Map?)?.cast<String, dynamic>();
    if (pq == null) return const SizedBox.shrink();
    final formData =
        (((data['form'] ?? (data['ticketOrder'] as Map?)?['order']?['form'])
                as Map?)?['data'] as Map?)
            ?.cast<String, dynamic>();
    final showQr =
        formData?[FeatureConstants.formShowPaymentQr]?.toString() == 'true';
    if (!showQr) return const SizedBox.shrink();
    final payload = pq['payload']?.toString() ?? '';
    if (payload.isEmpty) return const SizedBox.shrink();

    final amount = pq['amount'];
    final currency = pq['currency_code']?.toString() ?? '';
    final amountFormatted = (amount is num) ? '$amount $currency'.trim() : null;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: PaymentQrCard(
          payload: payload,
          format: pq['format']?.toString() ?? '',
          occasionTitle: widget.occasionTitle,
          orderSymbol: (data['ticketOrder'] as Map?)?['order']?['order_symbol']
              ?.toString(),
          bankAccount: pq['account_number_human_readable']?.toString(),
          iban: pq['account_number']?.toString(),
          paymentReference: pq['reference']?.toString(),
          referenceKind: pq['reference_kind']?.toString(),
          amountFormatted: amountFormatted,
          note: pq['message']?.toString(),
        ),
      ),
    );
  }
}

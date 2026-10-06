import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/theme_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/forms/public_order_strings.dart';
import 'package:fstapp/components/forms/widgets_view/payment_qr_card.dart';
import 'package:fstapp/components/features/feature_constants.dart';

class FinishOrderScreen extends StatefulWidget {
  final Future<FunctionResponse> Function() orderFutureFunction;
  final VoidCallback? onSuccess;
  final VoidCallback? onOrderConfirmed;
  final String? tone;
  final bool hasTickets;
  final Future<String?> Function(String)? deliveryStatusReader;

  const FinishOrderScreen({
    super.key,
    required this.orderFutureFunction,
    this.onSuccess,
    this.onOrderConfirmed,
    this.tone,
    this.hasTickets = true,
    this.deliveryStatusReader,
  });

  @override
  _FinishOrderScreenState createState() => _FinishOrderScreenState();
}

class _FinishOrderScreenState extends State<FinishOrderScreen>
    with TickerProviderStateMixin {
  bool _isSuccess = false;
  bool _isLoading = true;
  int? code;
  Map<String, dynamic>? _errorProduct;
  Map<String, dynamic>? _orderData;
  String _deliveryState = 'queued';

  late AnimationController _mainController;
  late AnimationController _loadingController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
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
    if (_isSuccess) _observeDelivery();
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
          if (didPop && _isSuccess) {
            widget.onSuccess?.call();
          }
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
    } else if (code == 1017) {
      final prodTitle = _errorProduct?["title"] ?? "";
      title = PublicOrderStrings.productUnavailable(prodTitle);
      subtitle = PublicOrderStrings.chooseDifferentVariant(widget.tone);
    } else {
      title = PublicOrderStrings.orderFailed;
      subtitle = PublicOrderStrings.orderError((code ?? 0).toString());
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
          if (_isSuccess) _buildPaymentQr(),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
            ),
            child: Text(PublicOrderStrings.backToForm),
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

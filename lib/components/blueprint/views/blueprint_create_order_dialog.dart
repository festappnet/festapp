import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/styles/styles_config.dart';

class BlueprintCreateOrderDialog extends StatefulWidget {
  final List<int> selectedSpotIds;

  const BlueprintCreateOrderDialog({
    super.key,
    required this.selectedSpotIds,
  });

  @override
  State<BlueprintCreateOrderDialog> createState() =>
      _BlueprintCreateOrderDialogState();
}

class _BlueprintCreateOrderDialogState
    extends State<BlueprintCreateOrderDialog> {
  // --- JSON Keys Constants ---
  static const String _kConflicts = 'conflicts';
  static const String _kNewItems = 'new_order_items';
  static const String _kOrderId = 'order_id';
  static const String _kTotalPrice = 'total_price';
  static const String _kPrice = 'price';
  static const String _kEmail = 'email';
  static const String _kName = 'name';
  static const String _kSurname = 'surname';

  static const String _kIsFullyCancelled = 'is_fully_cancelled';
  static const String _kProducts = 'products';
  static const String _kTicketSymbol = 'ticket_symbol';
  static const String _kTitle = 'title';
  static const String _kSpotTitle = 'spot_title';
  static const String _kProductTitle = 'product_title';

  bool _loading = true;
  // New state to track the submission process
  bool _isSubmitting = false;

  final TextEditingController _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final ScrollController _scrollController = ScrollController();

  List<dynamic> _conflicts = [];
  List<dynamic> _newItems = [];

  double _sumCur = 0;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    try {
      final data = await DbEshop.analyzeNewOrderSpots(widget.selectedSpotIds);
      if (mounted) {
        setState(() {
          _conflicts = data[_kConflicts] ?? [];
          _newItems = data[_kNewItems] ?? [];
          _recalc();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ToastHelper.Show(context, "Error analyzing spots: $e",
            severity: ToastSeverity.NotOk);
      }
    }
  }

  void _recalc() {
    _sumCur = _newItems.fold(0.0, (sum, item) {
      final price = (item[_kPrice] as num?)?.toDouble() ?? 0.0;
      return sum + price;
    });
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final inputData = {
      'email': _emailController.text.trim(),
    };

    try {
      // API call performed here so we can show loading state
      await DbEshop.createOrderFromSpots(widget.selectedSpotIds, inputData);

      if (mounted) {
        // Return true to indicate success
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.Show(context, e.toString().replaceFirst("Exception: ", ""),
            severity: ToastSeverity.NotOk);
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupedConflicts = groupBy(_conflicts, (c) => c[_kOrderId]);

    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Row(
        children: [
          Expanded(child: Text(BlueprintStrings.legendCreateOrder)),
          IconButton(
            icon: const Icon(Icons.close),
            // Prevent closing while submitting
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          )
        ],
      ),
      content: _loading
          ? const SizedBox(
              height: 150, child: Center(child: CircularProgressIndicator()))
          : SizedBox(
              width: StylesConfig.formMaxWidth,
              child: SelectionArea(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- SECTION 1: CANCELLED ITEMS ---
                      if (groupedConflicts.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.remove_shopping_cart,
                                      color: theme.colorScheme.error, size: 20),
                                  const SizedBox(width: 8),
                                  Text(OrdersStrings.cancelledItemsTitle,
                                      style: TextStyle(
                                          color: theme.colorScheme.error,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                BlueprintStrings.warningNoCancellationEmail,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...groupedConflicts.entries.map((entry) {
                          return _buildOrderConflictCard(
                              entry.key, entry.value);
                        }),
                        const SizedBox(height: 24),
                        const Divider(thickness: 1),
                        const SizedBox(height: 24),
                      ],

                      // --- SECTION 2: NEW ORDER ---
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Icon(Icons.add_shopping_cart,
                                color: theme.colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Text(OrdersStrings.newOrderTitle,
                                style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ],
                        ),
                      ),
                      _buildNewOrderCard(),

                      const SizedBox(height: 24),

                      // --- SECTION 3: EMAIL INPUT ---
                      Text(OrdersStrings.infoEmail,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        OrdersStrings.emailHelpText,
                        style: TextStyle(
                            fontSize: 14, color: theme.colorScheme.onSurface),
                      ),
                      const SizedBox(height: 8),
                      Form(
                        key: _formKey,
                        child: TextFormField(
                          controller: _emailController,
                          enabled:
                              !_isSubmitting, // Disable input while submitting
                          decoration: InputDecoration(
                            hintText: OrdersStrings.customerExample,
                            hintStyle: TextStyle(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.6)),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.email_outlined),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 16),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty)
                              return 'Email is required';
                            if (!value.contains('@')) return 'Invalid email';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: Text(CommonStrings.storno),
        ),
        ElevatedButton(
          onPressed: (_loading || _isSubmitting) ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          // Swap label/icon for ProgressIndicator when submitting
          child: _isSubmitting
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: theme.colorScheme.onPrimary))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check, size: 18),
                    const SizedBox(width: 8),
                    Text(BlueprintStrings.confirmOrder),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildOrderConflictCard(dynamic orderId, List<dynamic> tickets) {
    return _buildOrderConflictCardOriginal(orderId, tickets);
  }

  Widget _buildNewOrderCard() {
    return _buildNewOrderCardOriginal();
  }

  Widget _buildOrderConflictCardOriginal(
      dynamic orderId, List<dynamic> tickets) {
    final theme = Theme.of(context);
    final double orderTotalRefund = tickets.fold(
        0.0, (sum, t) => sum + ((t[_kTotalPrice] as num?)?.toDouble() ?? 0.0));
    final firstTicket = tickets.first;
    final String email = firstTicket[_kEmail] ?? 'No Email';
    final String name = firstTicket[_kName] ?? '';
    final String surname = firstTicket[_kSurname] ?? '';
    final String fullName = "$name $surname".trim();
    final String customerInfo =
        fullName.isNotEmpty ? "$fullName ($email)" : email;
    final bool isFullyCancelled =
        tickets.any((t) => t[_kIsFullyCancelled] == true);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: theme.colorScheme.errorContainer.withOpacity(0.3),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: theme.colorScheme.error.withOpacity(0.3))),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text("#$orderId",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: theme.colorScheme.onSurface)),
                      Text(customerInfo,
                          style: TextStyle(
                              fontSize: 14, color: theme.colorScheme.onSurface),
                          overflow: TextOverflow.ellipsis)
                    ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text("-${Utilities.formatPrice(context, orderTotalRefund)}",
                      style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: isFullyCancelled
                              ? theme.colorScheme.error
                              : Colors.orange,
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(
                          isFullyCancelled
                              ? OrdersStrings.fullCancelLabel
                              : OrdersStrings.partialCancelLabel,
                          style: TextStyle(
                              fontSize: 12,
                              color: isFullyCancelled
                                  ? theme.colorScheme.onError
                                  : Colors.white,
                              fontWeight: FontWeight.bold)))
                ])
              ],
            ),
            const Divider(),
            ...tickets.map((ticket) {
              final products = ticket[_kProducts] as List<dynamic>? ?? [];
              final ticketSymbol = ticket[_kTicketSymbol] ?? '';
              return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.confirmation_number_outlined,
                              size: 14, color: theme.colorScheme.error),
                          const SizedBox(width: 4),
                          Text("${OrdersStrings.ticket} $ticketSymbol",
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15))
                        ]),
                        if (products.isEmpty)
                          Padding(
                              padding: const EdgeInsets.only(left: 20.0),
                              child: Text(OrdersStrings.noDetailsFound,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontStyle: FontStyle.italic)))
                        else
                          ...products.map((p) {
                            String title = p[_kTitle] ?? '';
                            final spotTitle = p[_kSpotTitle];
                            if (spotTitle != null &&
                                spotTitle.toString().isNotEmpty) {
                              title += " ($spotTitle)";
                            }
                            return Padding(
                                padding:
                                    const EdgeInsets.only(left: 20.0, top: 2.0),
                                child: Row(children: [
                                  Expanded(
                                      child: Text("• $title",
                                          style:
                                              const TextStyle(fontSize: 14))),
                                  Text(
                                      Utilities.formatPrice(
                                          context,
                                          (p[_kPrice] as num?)?.toDouble() ??
                                              0),
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: theme.colorScheme.onSurface))
                                ]));
                          })
                      ]));
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildNewOrderCardOriginal() {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withOpacity(0.2),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.3))),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            ..._newItems.map((item) {
              final price = (item[_kPrice] as num?)?.toDouble() ?? 0.0;
              return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(children: [
                    Icon(Icons.check_circle_outline,
                        color: theme.colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item[_kSpotTitle] ?? "Spot",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          Text(item[_kProductTitle] ?? "Product",
                              style: const TextStyle(fontSize: 13))
                        ]),
                    const Spacer(),
                    Text("+${Utilities.formatPrice(context, price)}",
                        style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold))
                  ]));
            }),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(OrdersStrings.newOrderTotal,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary)),
              Text(Utilities.formatPrice(context, _sumCur),
                  style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16))
            ]),
          ],
        ),
      ),
    );
  }
}

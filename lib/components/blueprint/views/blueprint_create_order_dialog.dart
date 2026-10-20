import 'package:festapp_core/forms.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/styles/styles_config.dart';

class BlueprintCreateOrderDialog extends StatefulWidget {
  final List<int> selectedSpotIds;
  final Map<String, dynamic>? initialAnalysis;
  final Future<Map<String, dynamic>> Function(List<int>)? analyze;
  final Future<void> Function(List<int>, Map<String, dynamic>)? submit;

  const BlueprintCreateOrderDialog({
    super.key,
    required this.selectedSpotIds,
    this.initialAnalysis,
    this.analyze,
    this.submit,
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
  String? _error;
  bool _analysisReady = false;
  // New state to track the submission process
  bool _isSubmitting = false;

  final TextEditingController _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final ScrollController _scrollController = ScrollController();

  List<dynamic> _conflicts = [];
  List<dynamic> _newItems = [];

  double _sumCur = 0;
  String? _currency;
  String? _orderFormKey;
  _OrderFormFields? _customerFields;
  final _ticketFields = <int, _OrderFormFields>{};

  void _acceptAnalysis(Map<String, dynamic> data) {
    final total = data[_kTotalPrice], currency = data['currency'];
    if (total is! num ||
        !total.isFinite ||
        currency is! String ||
        currency.isEmpty) {
      throw const FormatException('Missing authoritative order total');
    }
    _conflicts = data[_kConflicts] ?? [];
    _newItems = data[_kNewItems] ?? [];
    _sumCur = total.toDouble();
    _currency = currency;
    final form = data['order_form'] as Map?;
    _orderFormKey = form?['key'] as String?;
    final fields = (form?['fields'] as List? ?? const [])
        .map((json) =>
            FormFieldDefinition.fromJson(Map<String, dynamic>.from(json)))
        .where((f) =>
            f.isRequired == true &&
            f.isHidden != true &&
            !{'ticket', 'spot', 'product_type'}.contains(f.type))
        .toList();
    final customer = fields
        .where((f) => f.isTicketField != true && f.type != 'email')
        .toList();
    _customerFields = customer.isEmpty
        ? null
        : _OrderFormFields(customer, form?['phone_prefixes']);
    final ticket = fields.where((f) => f.isTicketField == true).toList();
    _ticketFields.clear();
    if (ticket.isNotEmpty) {
      for (final id in widget.selectedSpotIds) {
        _ticketFields[id] = _OrderFormFields(ticket, form?['phone_prefixes']);
      }
    }
    _analysisReady = true;
    _loading = false;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialAnalysis != null) {
      _acceptAnalysis(widget.initialAnalysis!);
    } else {
      _analyze();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    setState(() {
      _loading = true;
      _error = null;
      _analysisReady = false;
    });
    try {
      final data = await (widget.analyze ??
          DbEshop.analyzeNewOrderSpots)(widget.selectedSpotIds);
      if (mounted) setState(() => _acceptAnalysis(data));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = BlueprintStrings.analysisFailed;
        });
      }
    }
  }

  Future<void> _confirm() async {
    if (_loading || _isSubmitting || !_analysisReady) return;
    var valid = _formKey.currentState!.validate();
    for (final group in [
      if (_customerFields != null) _customerFields!,
      ..._ticketFields.values
    ]) {
      if (!(group.key.currentState?.saveAndValidate() ?? false)) valid = false;
    }
    if (!valid) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final inputData = {
      'email': _emailController.text.trim(),
      if (_orderFormKey != null) 'form_key': _orderFormKey,
      if (_customerFields != null)
        'fields': _customerFields!.values(ticket: false),
      if (_ticketFields.isNotEmpty)
        'ticket_fields': {
          for (final entry in _ticketFields.entries)
            entry.key.toString(): entry.value.values(ticket: true),
        },
    };

    try {
      // API call performed here so we can show loading state
      if (widget.submit != null) {
        await widget.submit!(widget.selectedSpotIds, inputData);
      } else {
        await DbEshop.createOrderFromSpots(widget.selectedSpotIds, inputData);
      }

      if (mounted) {
        // Return true to indicate success
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupedConflicts = groupBy(_conflicts, (c) => c[_kOrderId]);

    return AppAlertDialog(
      onClose: () => Navigator.of(context).pop(),
      dismissible: !(_isSubmitting),
      insetPadding: const EdgeInsets.all(16),
      titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Row(
        children: [
          Expanded(child: Text(BlueprintStrings.legendCreateOrder)),
        ],
      ),
      content: _loading
          ? SizedBox(
              height: 150, child: Center(child: Text(OrdersStrings.processing)))
          : !_analysisReady
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Semantics(
                      liveRegion: true,
                      child: Text(_error ?? BlueprintStrings.analysisFailed)),
                  TextButton(
                      onPressed: _analyze, child: Text(CommonStrings.retry)),
                ])
              : SizedBox(
                  width: StylesConfig.formMaxWidth,
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_error != null)
                            Semantics(
                                liveRegion: true,
                                child: Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(_error!,
                                        style: TextStyle(
                                            color: theme.colorScheme.error)))),
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
                                          color: theme.colorScheme.error,
                                          size: 20),
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
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            OrdersStrings.emailHelpText,
                            style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurface),
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
                                  return CommonStrings.fieldCannotBeEmpty;
                                if (!value.contains('@'))
                                  return CommonStrings.invalidFormat;
                                return null;
                              },
                            ),
                          ),
                          if (_customerFields != null) ...[
                            const SizedBox(height: 16),
                            _requiredFields(_customerFields!),
                          ],
                          for (final entry in _ticketFields.entries) ...[
                            const SizedBox(height: 20),
                            Text(
                                _newItems
                                            .where((item) =>
                                                item['spot_id'] == entry.key)
                                            .firstOrNull?['spot_title']
                                        as String? ??
                                    '${entry.key}',
                                style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            _requiredFields(entry.value),
                          ],
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
          onPressed:
              (_loading || _isSubmitting || !_analysisReady) ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: Row(
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

  Widget _requiredFields(_OrderFormFields group) => FormBuilder(
        key: group.key,
        enabled: !_isSubmitting,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children:
                FormHelper.getAllFormFields(context, group.key, group.holder)),
      );

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
                  Text(
                      "-${Utilities.formatPrice(context, orderTotalRefund, currencyCode: _currency)}",
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
                    Text(
                        "+${Utilities.formatPrice(context, price, currencyCode: item['currency'] as String? ?? _currency)}",
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
              Text(
                  Utilities.formatPrice(context, _sumCur,
                      currencyCode: _currency),
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

class _OrderFormFields {
  _OrderFormFields(List<FormFieldDefinition> definitions, Object? prefixes)
      : holder = FormHolder(
            fields: definitions.map(FormHolder.createFieldHolder).toList(),
            isCardDesign: false,
            phonePrefixes:
                prefixes is List ? prefixes.cast<String>() : const []) {
    holder.controller = FormHolderController(globalKey: key);
  }
  final key = GlobalKey<FormBuilderState>();
  final FormHolder holder;
  List<Map<String, dynamic>> values({required bool ticket}) => [
        for (final field in holder.fields)
          {
            field.id.toString(): FormHelper.getFieldData(key, field),
            if (ticket) field.fieldType: FormHelper.getFieldData(key, field),
          },
      ];
}

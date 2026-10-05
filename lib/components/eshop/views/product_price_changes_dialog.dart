import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';
import 'package:fstapp/services/utilities_all.dart';

import '../db_eshop.dart';
import '../models/product_model.dart';
import '../models/product_price_change.dart';
import '../orders_strings.dart';

String priceChangeText(String template, List<String> values) {
  for (final value in values) {
    template = template.replaceFirst('{}', value);
  }
  return template;
}

String scheduledPrice(BuildContext context, double? price, String? currency) =>
    price == null
        ? '?'
        : Utilities.formatPrice(
            context,
            price,
            currencyCode: currency,
            decimalDigits: 2,
          );
String scheduledTime(DateTime time) =>
    DateFormat('dd. MM. yyyy HH:mm').format(time.toLocal());

DateTime? scheduleWallTime(String date, String time) {
  for (final format in ['yyyy-MM-dd HH:mm', 'dd.MM.yyyy HH:mm']) {
    try {
      return DateFormat(format)
          .parseStrict('${date.trim()} ${time.trim()}', true);
    } on FormatException {/* Try the other accepted date format. */}
  }
  return null;
}

DateTime? localScheduleTime(String date, String time, {DateTime? existing}) {
  final wall = scheduleWallTime(date, time);
  if (wall == null) return null;
  bool matches(DateTime value) =>
      value.year == wall.year &&
      value.month == wall.month &&
      value.day == wall.day &&
      value.hour == wall.hour &&
      value.minute == wall.minute;
  final local =
      DateTime(wall.year, wall.month, wall.day, wall.hour, wall.minute);
  if (!matches(local)) return null;
  if (existing != null && matches(existing.toLocal())) return existing.toUtc();
  return local.toUtc();
}

class ProductPriceChangesDialog extends StatefulWidget {
  final ProductModel product;
  final List<DateTime> suggestedTimes;
  final bool canEdit;
  final Future<ProductModel> Function() reload;
  final Future<void> Function(double, DateTime, ProductPriceChange?)? save;
  final Future<void> Function(ProductPriceChange)? cancel;
  final VoidCallback? onOpenWaves;
  const ProductPriceChangesDialog({
    super.key,
    required this.product,
    this.suggestedTimes = const [],
    required this.canEdit,
    required this.reload,
    this.save,
    this.cancel,
    this.onOpenWaves,
  });
  @override
  State<ProductPriceChangesDialog> createState() =>
      _ProductPriceChangesDialogState();
}

class _ProductPriceChangesDialogState extends State<ProductPriceChangesDialog> {
  Timer? _timer;
  bool _reloading = false;
  late ProductModel product = widget.product;
  final price = TextEditingController();
  final date = TextEditingController();
  final time = TextEditingController();
  ProductPriceChange? editing;
  bool formOpen = false, busy = false, changed = false, allowClose = false;
  String? error;
  DateTime? offsetChoice;
  bool get dirty =>
      price.text.isNotEmpty || date.text.isNotEmpty || time.text.isNotEmpty;
  List<ProductPriceChange> get plans =>
      ProductPriceChange.pending(product.priceChanges);
  @override
  void initState() {
    super.initState();
    formOpen = widget.canEdit && plans.isEmpty;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted || busy) return;
      if (dirty) {
        setState(() {});
      } else {
        reload();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    price.dispose();
    date.dispose();
    time.dispose();
    super.dispose();
  }

  DateTime? get wallTime => scheduleWallTime(date.text, time.text);
  List<DateTime> get candidates {
    final instant =
        localScheduleTime(date.text, time.text, existing: offsetChoice);
    return instant == null ? [] : [instant];
  }

  void edit(ProductPriceChange? plan) {
    setState(() {
      editing = plan;
      formOpen = true;
      error = null;
      offsetChoice = null;
      price.text = plan?.price?.toString() ?? '';
      date.text = plan == null
          ? ''
          : DateFormat('dd.MM.yyyy').format(plan.time.toLocal());
      time.text =
          plan == null ? '' : DateFormat('HH:mm').format(plan.time.toLocal());
      if (plan != null) offsetChoice = plan.time;
    });
  }

  Future<bool> discard() async {
    if (!dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(CommonStrings.discardChanges),
            content: Text(CommonStrings.discardChangesConfirmation),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(CommonStrings.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(CommonStrings.discardChanges),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> close({bool openWaves = false}) async {
    if (busy || !await discard() || !mounted) return;
    setState(() => allowClose = true);
    Navigator.pop(context, changed);
    if (openWaves) widget.onOpenWaves?.call();
  }

  Future<void> reload() async {
    if (_reloading) return;
    _reloading = true;
    final result = await ExceptionHandler.guard(
      context,
      futureFunction: widget.reload,
      defaultErrorMessage: OrdersStrings.priceSaveFailed,
    );
    _reloading = false;
    if (result != null && mounted) {
      setState(() => product = result);
    }
  }

  Future<void> submit() async {
    final amount = double.tryParse(price.text.replaceAll(',', '.'));
    final instants = candidates;
    final instant = instants.length == 1
        ? instants.first
        : instants.where((i) => i == offsetChoice).firstOrNull;
    if (amount == null ||
        !amount.isFinite ||
        amount < 0 ||
        instant == null ||
        !instant.isAfter(product.priceNow)) {
      setState(
        () => error = instants.isEmpty && wallTime != null
            ? OrdersStrings.priceMissingTime
            : OrdersStrings.priceInvalid,
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final success = await ExceptionHandler.guardVoid(
      context,
      futureFunction: () async {
        if (widget.save != null) {
          await widget.save!(amount, instant, editing);
        } else {
          await DbEshop.saveProductPriceChange(
            product.id!,
            amount,
            instant,
            changeId: editing?.id,
            revision: editing?.revision,
          );
        }
      },
      defaultErrorMessage: OrdersStrings.priceSaveFailed,
    );
    if (!mounted) return;
    if (success) {
      changed = true;
      price.clear();
      date.clear();
      time.clear();
      editing = null;
      formOpen = false;
      await reload();
    }
    if (mounted) {
      setState(() {
        busy = false;
        if (!success) error = OrdersStrings.priceSaveFailed;
      });
    }
  }

  Future<void> cancel(ProductPriceChange plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(OrdersStrings.cancelPriceChange),
        content: Text(
          priceChangeText(OrdersStrings.priceCancelConfirm, [
            scheduledPrice(context, plan.price, product.currencyCode),
            scheduledTime(plan.time),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(CommonStrings.close),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(OrdersStrings.cancelPriceChange),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    final success = await ExceptionHandler.guardVoid(
      context,
      futureFunction: () async {
        if (widget.cancel != null) {
          await widget.cancel!(plan);
        } else {
          await DbEshop.cancelProductPriceChange(
            product.id!,
            plan.id,
            plan.revision,
          );
        }
      },
      defaultErrorMessage: OrdersStrings.priceSaveFailed,
    );
    if (success) {
      changed = true;
      await reload();
    }
    if (mounted) setState(() => busy = false);
  }

  double? precedingPrice(DateTime instant) {
    double? result = product.price;
    for (final plan in plans) {
      if (plan.id != editing?.id &&
          plan.failureCode == null &&
          plan.time.isBefore(instant)) result = plan.price;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final instants = candidates;
    final amount = double.tryParse(price.text.replaceAll(',', '.'));
    final instant = instants.length == 1 ? instants.first : offsetChoice;
    final children = <Widget>[
      Text(product.title ?? '', style: Theme.of(context).textTheme.titleMedium),
      Text(
        '${OrdersStrings.scheduledCurrentPrice}: ${scheduledPrice(context, product.price, product.currencyCode)}',
      ),
      const SizedBox(height: 12),
    ];
    double? previous = product.price;
    for (final plan in plans) {
      final label =
          '${scheduledPrice(context, previous, product.currencyCode)} → ${scheduledPrice(context, plan.price, product.currencyCode)}';
      final overdue = !plan.time.isAfter(product.priceNow);
      children.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                Text(scheduledTime(plan.time)),
                if (plan.failureCode != null)
                  Text('${OrdersStrings.priceFailed} (${plan.failureCode})')
                else if (overdue)
                  Text(OrdersStrings.pricePending),
                if (overdue &&
                    plan.failureCode == null &&
                    product.priceNow.difference(plan.time) >
                        const Duration(minutes: 2))
                  Text(OrdersStrings.priceDelayed),
                if (previous != product.price)
                  Text(OrdersStrings.priceExpected),
                if (widget.canEdit)
                  Wrap(
                    children: [
                      TextButton(
                        onPressed:
                            busy || formOpen && dirty ? null : () => edit(plan),
                        child: Text(
                          '${CommonStrings.edit} ${scheduledTime(plan.time)}',
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => cancel(plan),
                        child: Semantics(
                          excludeSemantics: true,
                          label:
                              '${product.title}: ${OrdersStrings.cancelPriceChange} ${scheduledTime(plan.time)}',
                          child: Text(OrdersStrings.cancelPriceChange),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
      if (plan.failureCode == null) previous = plan.price;
    }
    if (formOpen) {
      if (widget.suggestedTimes.isNotEmpty)
        children.add(Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final instant in widget.suggestedTimes)
                ActionChip(
                    avatar: const Icon(Icons.calendar_month, size: 16),
                    label: Text(scheduledTime(instant)),
                    onPressed: busy
                        ? null
                        : () => setState(() {
                              date.text = DateFormat('dd.MM.yyyy')
                                  .format(instant.toLocal());
                              time.text =
                                  DateFormat('HH:mm').format(instant.toLocal());
                              offsetChoice = instant;
                            }))
            ])));
      children.addAll([
        const Divider(),
        TextField(
          controller: price,
          enabled: !busy,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: OrdersStrings.newPrice,
            suffixText: product.currencyCode,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        TimeDatePicker(
          date: date.text.isEmpty ? null : scheduleWallTime(date.text, '00:00'),
          time: time.text.isEmpty
              ? null
              : TimeOfDay.fromDateTime(
                  scheduleWallTime('2000-01-01', time.text)!),
          dateLabel: OrdersStrings.priceDate,
          timeLabel: OrdersStrings.priceTime,
          enabled: !busy,
          minDate: DateTime.now(),
          maxDate: DateTime(2100),
          onDateChanged: (picked) => setState(() {
            date.text = DateFormat('dd.MM.yyyy').format(picked);
            offsetChoice = null;
          }),
          onTimeChanged: (picked) => setState(() {
            time.text =
                '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
            offsetChoice = null;
          }),
        ),
        if (amount != null && instant != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              priceChangeText(OrdersStrings.priceSummary, [
                scheduledTime(instant),
                scheduledPrice(context, amount, product.currencyCode),
              ]),
            ),
          ),
        if (amount != null &&
            instant != null &&
            amount == precedingPrice(instant))
          Text(OrdersStrings.priceSame),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ]);
    }
    final actions = [
      TextButton(
        onPressed: busy ? null : close,
        child: Text(CommonStrings.close),
      ),
      TextButton(
        onPressed: busy ? null : reload,
        child: Text(OrdersStrings.priceRefreshAction),
      ),
      if (widget.onOpenWaves != null)
        OutlinedButton(
          onPressed: busy ? null : () => close(openWaves: true),
          child: Text(OrdersStrings.priceWaves),
        ),
      if (widget.canEdit && !formOpen)
        FilledButton(
          onPressed: busy ? null : () => edit(null),
          child: Text(OrdersStrings.addPriceChange),
        ),
      if (widget.canEdit && formOpen)
        FilledButton(
          onPressed: busy ? null : submit,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  editing == null
                      ? OrdersStrings.schedulePrice
                      : CommonStrings.saveChanges,
                ),
        ),
    ];
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const SizedBox(width: 48),
              Expanded(
                child: Text(
                  OrdersStrings.priceChangesTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: CommonStrings.close,
                onPressed: busy ? null : close,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: actions,
          ),
        ),
      ],
    );
    return PopScope(
      canPop: allowClose,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: MediaQuery.sizeOf(context).width < 600
          ? Dialog.fullscreen(child: SafeArea(child: body))
          : Dialog(child: SizedBox(width: 560, child: body)),
    );
  }
}

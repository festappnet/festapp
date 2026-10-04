import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';
import '../db_eshop.dart';
import '../models/product_edit_bundle.dart';
import '../models/product_model.dart';
import '../models/product_price_wave.dart';
import '../orders_strings.dart';
import 'product_price_changes_dialog.dart';

/// A shared-term matrix projected from the canonical queue; no second executor.
class ProductPriceWavesDialog extends StatefulWidget {
  final String occasionLink;
  final ProductsEditBundle initialBundle;
  final bool canEdit;
  final Future<ProductsEditBundle> Function()? loader;
  const ProductPriceWavesDialog(
      {super.key,
      required this.occasionLink,
      required this.initialBundle,
      required this.canEdit,
      this.loader});
  @override
  State<ProductPriceWavesDialog> createState() =>
      _ProductPriceWavesDialogState();
}

class _ProductPriceWavesDialogState extends State<ProductPriceWavesDialog> {
  late ProductsEditBundle bundle = widget.initialBundle;
  bool busy = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!busy) reload();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> reload() async {
    if (busy) return;
    setState(() => busy = true);
    final next = await ExceptionHandler.guard(context,
        futureFunction: widget.loader ??
            () => DbEshop.getProductsAndTypesForOccasion(widget.occasionLink));
    if (mounted)
      setState(() {
        if (next != null) bundle = next;
        busy = false;
      });
  }

  Future<void> term([ProductPriceWave? wave]) async {
    setState(() => busy = true);
    final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WaveTermDialog(
            wave: wave,
            save: (time) async {
              if (wave == null) {
                await DbEshop.createProductPriceWave(widget.occasionLink, time);
              } else {
                await DbEshop.moveProductPriceWave(wave, time);
              }
            }));
    if (!mounted) return;
    setState(() => busy = false);
    if (changed == true) await reload();
  }

  Future<void> target(ProductPriceWave wave, ProductModel product) async {
    setState(() => busy = true);
    final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => WaveProductTargetDialog(
            wave: wave,
            product: product,
            save: (price, hidden) async {
              final persisted = wave.id == null
                  ? await DbEshop.createProductPriceWave(
                      widget.occasionLink, wave.time)
                  : wave;
              await DbEshop.saveProductWaveTarget(
                  persisted,
                  product.id!,
                  price,
                  hidden,
                  wave.prices(product).firstOrNull?.revision,
                  wave.visibility(product).firstOrNull?.revision);
            }));
    if (!mounted) return;
    setState(() => busy = false);
    if (changed == true) await reload();
  }

  Future<void> remove(ProductPriceWave wave) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                scrollable: true,
                title: Text(OrdersStrings.cancelWave),
                content: Text(OrdersStrings.cancelWaveConfirm),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(CommonStrings.storno)),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(CommonStrings.confirm))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    final success = await ExceptionHandler.guardVoid(context,
        futureFunction: () => DbEshop.cancelProductPriceWave(wave));
    if (!mounted) return;
    setState(() => busy = false);
    if (success) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final waves = ProductPriceWave.columns(bundle.priceWaves, bundle.products);
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(OrdersStrings.priceWaves),
          leading: IconButton(
            tooltip: CommonStrings.close,
            onPressed: busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          actions: [
            IconButton(
              tooltip: OrdersStrings.priceRefreshAction,
              onPressed: busy ? null : reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.canEdit)
                      FilledButton.icon(
                        onPressed: busy ? null : () => term(),
                        icon: const Icon(Icons.add),
                        label: Text(OrdersStrings.addWave),
                      ),
                    Text(
                      OrdersStrings.waveEmptyPrice,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: Column(
                          children: [
                            _timelinePoint(
                              title: OrdersStrings.waveNow,
                              current: true,
                              last: waves.isEmpty,
                              children: [
                                for (final product in bundle.products)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product.title ?? '',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 4,
                                          children: [
                                            Text(
                                              scheduledPrice(
                                                context,
                                                product.price,
                                                product.currencyCode,
                                              ),
                                            ),
                                            if (product.isHidden == true)
                                              Text(
                                                OrdersStrings.waveHiddenState,
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            for (var i = 0; i < waves.length; i++)
                              _timelinePoint(
                                title: scheduledTime(waves[i].time),
                                last: i == waves.length - 1,
                                menu: widget.canEdit && waves[i].id != null
                                    ? PopupMenuButton<String>(
                                        enabled: !busy,
                                        onSelected: (value) => value == 'move'
                                            ? term(waves[i])
                                            : remove(waves[i]),
                                        itemBuilder: (_) => [
                                          PopupMenuItem(
                                            value: 'move',
                                            child: Text(OrdersStrings.moveWave),
                                          ),
                                          PopupMenuItem(
                                            value: 'remove',
                                            child: Text(
                                              OrdersStrings.cancelWave,
                                            ),
                                          ),
                                        ],
                                      )
                                    : null,
                                children: [
                                  for (final product in bundle.products)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          final compact = constraints.maxWidth <
                                                  420 ||
                                              MediaQuery.textScalerOf(context)
                                                      .scale(16) >
                                                  24;
                                          final title = Text(
                                            product.title ?? '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          );
                                          final cell = WaveProductCell(
                                            wave: waves[i],
                                            product: product,
                                            width:
                                                compact ? double.infinity : 180,
                                            onOpen: widget.canEdit &&
                                                    !busy &&
                                                    waves[i].time.isAfter(
                                                          product.priceNow,
                                                        ) &&
                                                    waves[i]
                                                            .prices(product)
                                                            .length <=
                                                        1 &&
                                                    waves[i]
                                                            .visibility(product)
                                                            .length <=
                                                        1
                                                ? () =>
                                                    target(waves[i], product)
                                                : null,
                                          );
                                          return compact
                                              ? Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    title,
                                                    const SizedBox(height: 8),
                                                    cell,
                                                  ],
                                                )
                                              : Row(
                                                  children: [
                                                    Expanded(child: title),
                                                    const SizedBox(width: 16),
                                                    cell,
                                                  ],
                                                );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timelinePoint({
    required String title,
    bool current = false,
    bool last = false,
    Widget? menu,
    required List<Widget> children,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Stack(children: [
      if (!last)
        Positioned(
            left: 9,
            top: 20,
            bottom: 0,
            child: Container(width: 2, color: colors.outlineVariant)),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 20,
            child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Center(
                    child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: current
                                ? colors.onSurfaceVariant
                                : colors.surface,
                            border: Border.all(
                                color: colors.outline, width: 2)))))),
        const SizedBox(width: 12),
        Expanded(
            child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Card(
                  margin: EdgeInsets.zero,
                  color: colors.surfaceContainerLow,
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700))),
                            if (menu != null) menu
                          ]),
                          const Divider(height: 24),
                          ...children,
                        ],
                      )),
                ))),
      ]),
    ]);
  }
}

class WaveProductCell extends StatelessWidget {
  final ProductPriceWave wave;
  final ProductModel product;
  final VoidCallback? onOpen;
  final double width;
  const WaveProductCell(
      {super.key,
      required this.wave,
      required this.product,
      this.onOpen,
      this.width = 180});
  @override
  Widget build(BuildContext context) {
    final price = wave.prices(product).firstOrNull;
    final visibility = wave.visibility(product).firstOrNull;
    final failed = price?.failureCode != null ||
        visibility?.failureCode != null ||
        wave.prices(product).length > 1 ||
        wave.visibility(product).length > 1;
    final colors = Theme.of(context).colorScheme;
    final empty = price == null && visibility == null;
    final color = failed
        ? colors.error
        : visibility?.hidden == true
            ? colors.onSurfaceVariant
            : colors.primary;
    return SizedBox(
        width: width,
        child: OutlinedButton(
            onPressed: onOpen,
            style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: color,
                disabledForegroundColor: color,
                backgroundColor: empty ? null : color.withValues(alpha: .06),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (empty)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add, size: 16),
                      const SizedBox(width: 6),
                      Text(OrdersStrings.waveChange)
                    ]),
                  if (price != null)
                    Text(
                        scheduledPrice(
                            context, price.price, product.currencyCode),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (visibility != null)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          visibility.hidden == true
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 16),
                      const SizedBox(width: 6),
                      Text(visibility.hidden == true
                          ? OrdersStrings.waveHidden
                          : OrdersStrings.waveShown)
                    ]),
                  if (failed)
                    Text(OrdersStrings.waveFailed,
                        style: TextStyle(color: colors.error, fontSize: 12)),
                ])));
  }
}

class WaveProductTargetDialog extends StatefulWidget {
  final ProductPriceWave wave;
  final ProductModel product;
  final Future<void> Function(double?, bool?) save;
  const WaveProductTargetDialog(
      {super.key,
      required this.wave,
      required this.product,
      required this.save});
  @override
  State<WaveProductTargetDialog> createState() =>
      _WaveProductTargetDialogState();
}

class _WaveProductTargetDialogState extends State<WaveProductTargetDialog> {
  late final TextEditingController price = TextEditingController(
      text: widget.wave.prices(widget.product).firstOrNull?.price?.toString() ??
          '');
  late bool? hidden =
      widget.wave.visibility(widget.product).firstOrNull?.hidden;
  bool busy = false, dirty = false, allowClose = false;
  String? error;
  @override
  void dispose() {
    price.dispose();
    super.dispose();
  }

  Future<void> close() async {
    if (busy) return;
    if (dirty) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
                  scrollable: true,
                  title: Text(CommonStrings.discardChanges),
                  content: Text(CommonStrings.discardChangesConfirmation),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(CommonStrings.storno)),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(CommonStrings.confirm))
                  ]));
      if (discard != true || !mounted) return;
    }
    setState(() => allowClose = true);
    Navigator.pop(context, false);
  }

  Future<void> submit() async {
    final value = price.text.trim().isEmpty
        ? null
        : double.tryParse(price.text.replaceAll(',', '.'));
    if (price.text.trim().isNotEmpty &&
        (value == null || !value.isFinite || value < 0)) {
      setState(() => error = OrdersStrings.priceInvalid);
      return;
    }
    setState(() => busy = true);
    final success = await ExceptionHandler.guardVoid(context,
        futureFunction: () => widget.save(value, hidden),
        defaultErrorMessage: OrdersStrings.priceSaveFailed);
    if (!mounted) return;
    setState(() {
      busy = false;
      if (success) allowClose = true;
    });
    if (success) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: allowClose,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) close();
      },
      child: AlertDialog(
          scrollable: true,
          title: Text(widget.product.title ?? ''),
          content: SizedBox(
              width: 360,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(scheduledTime(widget.wave.time)),
                    const SizedBox(height: 20),
                    TextField(
                        controller: price,
                        enabled: !busy,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: OrdersStrings.newPrice,
                            hintText: OrdersStrings.waveNoChange,
                            suffixText: widget.product.currencyCode),
                        onChanged: (_) => setState(() => dirty = true)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                        initialValue: hidden == null
                            ? 0
                            : hidden!
                                ? 2
                                : 1,
                        decoration: InputDecoration(
                            labelText: OrdersStrings.waveAvailability),
                        items: [
                          DropdownMenuItem(
                              value: 0,
                              child: Text(OrdersStrings.waveNoChange)),
                          DropdownMenuItem(
                              value: 1, child: Text(OrdersStrings.waveShown)),
                          DropdownMenuItem(
                              value: 2, child: Text(OrdersStrings.waveHidden))
                        ],
                        onChanged: busy
                            ? null
                            : (value) => setState(() {
                                  hidden = value == 0 ? null : value == 2;
                                  dirty = true;
                                })),
                    if (error != null)
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ])),
          actions: [
            TextButton(
                onPressed: busy ? null : close,
                child: Text(CommonStrings.storno)),
            FilledButton(
                onPressed: busy ? null : submit,
                child: Text(CommonStrings.save))
          ]));
}

class _WaveTermDialog extends StatefulWidget {
  final ProductPriceWave? wave;
  final Future<void> Function(DateTime) save;
  const _WaveTermDialog({this.wave, required this.save});
  @override
  State<_WaveTermDialog> createState() => _WaveTermDialogState();
}

class _WaveTermDialogState extends State<_WaveTermDialog> {
  late final date = TextEditingController(
      text: widget.wave == null
          ? ''
          : DateFormat('dd.MM.yyyy').format(widget.wave!.time.toLocal()));
  late final time = TextEditingController(
      text: widget.wave == null
          ? ''
          : DateFormat('HH:mm').format(widget.wave!.time.toLocal()));
  bool busy = false;
  String? error;
  @override
  void dispose() {
    date.dispose();
    time.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final instant =
        localScheduleTime(date.text, time.text, existing: widget.wave?.time);
    if (instant == null || !instant.isAfter(DateTime.now().toUtc())) {
      setState(() => error = OrdersStrings.priceInvalid);
      return;
    }
    setState(() => busy = true);
    final success = await ExceptionHandler.guardVoid(context,
        futureFunction: () => widget.save(instant),
        defaultErrorMessage: OrdersStrings.priceSaveFailed);
    if (!mounted) return;
    setState(() => busy = false);
    if (success) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
          scrollable: true,
          title: Text(widget.wave == null
              ? OrdersStrings.addWave
              : OrdersStrings.moveWave),
          content: SizedBox(
              width: 360,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TimeDatePicker(
                  date: date.text.isEmpty
                      ? null
                      : scheduleWallTime(date.text, '00:00'),
                  time: time.text.isEmpty
                      ? null
                      : TimeOfDay.fromDateTime(
                          scheduleWallTime('2000-01-01', time.text)!),
                  dateLabel: OrdersStrings.priceDate,
                  timeLabel: OrdersStrings.priceTime,
                  enabled: !busy,
                  minDate: DateTime.now(),
                  maxDate: DateTime(2100),
                  onDateChanged: (picked) => setState(() =>
                      date.text = DateFormat('dd.MM.yyyy').format(picked)),
                  onTimeChanged: (picked) => setState(() => time.text =
                      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'),
                ),
                if (error != null)
                  Text(error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error))
              ])),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context, false),
                child: Text(CommonStrings.storno)),
            FilledButton(
                onPressed: busy ? null : submit,
                child: Text(CommonStrings.save))
          ]));
}

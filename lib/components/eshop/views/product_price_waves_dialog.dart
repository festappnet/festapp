import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';
import '../db_eshop.dart';
import '../models/product_edit_bundle.dart';
import 'package:festapp_core/eshop.dart';
import '../orders_strings.dart';
import 'product_price_changes_dialog.dart';
import 'product_price_wave_actions.dart';

/// A shared-term matrix projected from the canonical queue; no second executor.
class ProductPriceWavesDialog extends StatefulWidget {
  final String occasionLink;
  final ProductsEditBundle initialBundle;
  final bool canEdit;
  final ProductPriceWaveActions? actions;
  final DateTime? occasionEnd;
  final Future<ProductsEditBundle> Function()? loader;
  const ProductPriceWavesDialog(
      {super.key,
      required this.occasionLink,
      required this.initialBundle,
      required this.canEdit,
      this.loader,
      this.occasionEnd,
      this.actions});
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
    if (widget.actions == null)
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
    final occasion = RightsService.currentOccasion();
    final end = widget.occasionEnd ??
        (occasion?.link == widget.occasionLink ? occasion?.endTime : null);
    final suggested = wave?.time ??
        ProductPriceWave.suggestTime(
            now: DateTime.now(),
            end: end,
            terms: ProductPriceWave.columns(bundle.priceWaves, bundle.products)
                .map((w) => w.time));
    if (wave == null && suggested == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(end == null
              ? 'Nejprve doplňte konec akce.'
              : 'Před koncem akce už není volný termín pro další vlnu.')));
      return;
    }
    setState(() => busy = true);
    final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WaveTermDialog(
            initialTime: suggested,
            end: end,
            wave: wave,
            save: (time) async {
              if (wave == null) {
                if (widget.actions != null) {
                  await widget.actions!.create(time);
                } else {
                  await DbEshop.createProductPriceWave(
                      widget.occasionLink, time);
                }
              } else {
                if (widget.actions != null) {
                  await widget.actions!.move(wave, time);
                } else {
                  await DbEshop.moveProductPriceWave(wave, time);
                }
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
              if (widget.actions != null) {
                final persisted = wave.id == null
                    ? await widget.actions!.create(wave.time)
                    : wave;
                await widget.actions!
                    .saveTarget(persisted, product, price, hidden);
                return;
              }
              if (wave.id == null) {
                await DbEshop.saveNewProductWaveTarget(
                    widget.occasionLink,
                    wave,
                    product.id!,
                    price,
                    hidden,
                    wave.prices(product).firstOrNull?.revision,
                    wave.visibility(product).firstOrNull?.revision);
              } else {
                await DbEshop.saveProductWaveTarget(
                    wave,
                    product.id!,
                    price,
                    hidden,
                    wave.prices(product).firstOrNull?.revision,
                    wave.visibility(product).firstOrNull?.revision);
              }
            }));
    if (!mounted) return;
    setState(() => busy = false);
    if (changed == true) await reload();
  }

  Future<void> remove(ProductPriceWave wave) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AppAlertDialog(
                onClose: () => Navigator.pop(context, false),
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
        futureFunction: () => widget.actions != null
            ? widget.actions!.cancel(wave)
            : DbEshop.cancelProductPriceWave(wave));
    if (!mounted) return;
    setState(() => busy = false);
    if (success) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final localNow = TimeHelper.currentTime ?? DateTime.now();
    final waves = ProductPriceWave.columns(bundle.priceWaves, bundle.products);
    return AppDialog.fullscreen(
      dismissible: !busy,
      child: Scaffold(
        appBar: AppDialogAppBar(
          title: Text(OrdersStrings.priceWaves),
          onClose: () => Navigator.pop(context),
          closeEnabled: !busy,
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
                                                          product.priceTime(
                                                              localNow),
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
                      Flexible(child: Text(OrdersStrings.waveChange))
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
                      Flexible(
                          child: Text(visibility.hidden == true
                              ? OrdersStrings.waveHidden
                              : OrdersStrings.waveShown))
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
  late final bool? originalHidden =
      widget.wave.visibility(widget.product).firstOrNull?.hidden;
  late bool? hidden = originalHidden;
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
          builder: (_) => AppAlertDialog(
                  onClose: () => Navigator.pop(context, false),
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
      child: AppAlertDialog(
          onClose: close,
          dismissible: !(busy),
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
                        isExpanded: true,
                        itemHeight: null,
                        initialValue: hidden == null
                            ? 0
                            : hidden!
                                ? 2
                                : 1,
                        decoration: InputDecoration(
                            labelText: OrdersStrings.waveAvailability,
                            helper: Semantics(
                              liveRegion: true,
                              child: Text(widget.product.isUsedInBlueprint !=
                                      false
                                  ? (widget.product.isUsedInBlueprint == true
                                      ? OrdersStrings.waveSeatProductHint
                                      : OrdersStrings
                                          .waveAvailabilityUnknownHint)
                                  : hidden == null
                                      ? OrdersStrings.waveAvailabilityKeepHint
                                      : hidden!
                                          ? OrdersStrings
                                              .waveAvailabilityHideHint
                                          : OrdersStrings
                                              .waveAvailabilityShowHint),
                            ),
                            suffixIcon: IconButton(
                              tooltip: OrdersStrings.waveAvailabilityHelpTitle,
                              constraints: const BoxConstraints(
                                  minWidth: 48, minHeight: 48),
                              icon: const Icon(Icons.info_outline),
                              onPressed: busy ||
                                      widget.product.isUsedInBlueprint != false
                                  ? null
                                  : () => showDialog<void>(
                                        context: context,
                                        builder: (dialogContext) =>
                                            AppAlertDialog(
                                          onClose: () =>
                                              Navigator.pop(dialogContext),
                                          scrollable: true,
                                          title: Text(OrdersStrings
                                              .waveAvailabilityHelpTitle),
                                          content: Text(OrdersStrings
                                              .waveAvailabilityHelp),
                                        ),
                                      ),
                            )),
                        items: [
                          DropdownMenuItem(
                              value: 0,
                              child:
                                  Text(OrdersStrings.waveAvailabilityNoChange)),
                          DropdownMenuItem(
                              value: 1, child: Text(OrdersStrings.waveShown)),
                          DropdownMenuItem(
                              value: 2, child: Text(OrdersStrings.waveHidden))
                        ],
                        onChanged:
                            busy || widget.product.isUsedInBlueprint != false
                                ? null
                                : (value) => setState(() {
                                      hidden = value == 0 ? null : value == 2;
                                      dirty = true;
                                    })),
                    if (widget.product.isUsedInBlueprint != false &&
                        originalHidden != null)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: hidden == null,
                        title: Text(OrdersStrings.waveCancelAvailability),
                        onChanged: busy
                            ? null
                            : (cancel) => setState(() {
                                  hidden =
                                      cancel == true ? null : originalHidden;
                                  dirty = true;
                                }),
                      ),
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
  final DateTime? initialTime, end;
  final Future<void> Function(DateTime) save;
  const _WaveTermDialog(
      {this.wave, this.initialTime, this.end, required this.save});
  @override
  State<_WaveTermDialog> createState() => _WaveTermDialogState();
}

class _WaveTermDialogState extends State<_WaveTermDialog> {
  late final date = TextEditingController(
      text: (widget.wave?.time ?? widget.initialTime) == null
          ? ''
          : DateFormat('dd.MM.yyyy')
              .format((widget.wave?.time ?? widget.initialTime)!.toLocal()));
  late final time = TextEditingController(
      text: (widget.wave?.time ?? widget.initialTime) == null
          ? ''
          : DateFormat('HH:mm')
              .format((widget.wave?.time ?? widget.initialTime)!.toLocal()));
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
    if (instant == null ||
        !instant.isAfter(DateTime.now().toUtc()) ||
        (widget.end != null && !instant.isBefore(widget.end!))) {
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
      child: AppAlertDialog(
          onClose: () => Navigator.pop(context, false),
          dismissible: !(busy),
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

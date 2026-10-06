import 'package:fstapp/components/single_data_grid/admin_tab_activity.dart';
import 'report_text.dart';
import '../models/report_period.dart';
import '../models/report_exchange_rates.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'report_timeline_chart.dart';

import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:file_saver/file_saver.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/components/eshop/models/occasion_report_model.dart';
import 'package:fstapp/components/eshop/report_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';

class ReportTab extends StatefulWidget {
  final Future<ReportExchangeRates> Function()? exchangeRateLoader;
  final String? occasionLink;
  final String? identityKey;
  final Future<OccasionReport> Function(String)? loader;
  final Future<void> Function(OccasionReport)? exporter;
  const ReportTab({
    super.key,
    this.exchangeRateLoader,
    this.occasionLink,
    this.identityKey,
    this.loader,
    this.exporter,
  });

  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> {
  bool _tabActive = true;
  bool _onlyValid = true;
  OccasionReport? get _visibleReport => _onlyValid ? _report?.onlyValid() : _report;
  OccasionReport? _report;
  StreamSubscription<AuthState>? _authSubscription;
  String? _key, _link;
  int _generation = 0;
  bool _loading = false, _error = false, _text = false, _exporting = false;

  @override
  void initState() {
    super.initState();
    RightsService.occasionLinkModelNotifier.addListener(_contextChanged);
    if (widget.identityKey == null) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((_) => _contextChanged());
    }
  }

  void _contextChanged() {
    if (mounted) setState(_updateKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateKey();
    final active = AdminTabActivity.isActive(context);
    if (active &&
        !_tabActive &&
        _link != null &&
        (widget.identityKey != null || RightsService.isEditorOrderView())) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          setState(() {
            _load();
          });
      });
    }
    _tabActive = active;
  }

  @override
  void didUpdateWidget(covariant ReportTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateKey();
  }

  void _updateKey() {
    final link = widget.occasionLink ??
        context.routeData.inheritedPathParams.getString(
          AppRouter.linkFormatted,
        );
    final identity = widget.identityKey ??
        '${Supabase.instance.client.auth.currentUser?.id}/${RightsService.currentUser()?.id}/${RightsService.currentOccasion()?.organization}/${RightsService.isEditorOrderView()}';
    final key = '$identity/$link';
    if (key == _key) return;
    _onlyValid = true;
    _key = key;
    _link = link;
    _generation++;
    _report = null;
    _error = false;
    _loading = false;
    if (widget.identityKey != null ||
        (Supabase.instance.client.auth.currentUser != null &&
            RightsService.isEditorOrderView())) {
      _load();
    } else {
      _error = true;
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    final generation = ++_generation;
    _loading = true;
    _error = false;
    try {
      final report = await (widget.loader ?? DbEshop.getReportForOccasion)(
        _link!,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _report = report;
        _loading = false;
      });
      if (report.money.length > 1) {
        unawaited(_loadRates());
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = true;
        // A failed authorization or an unknown transport/contract failure must
        // never leave potentially unauthorized financial data on screen.
        _report = null;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _authSubscription?.cancel();
    RightsService.occasionLinkModelNotifier.removeListener(_contextChanged);
    super.dispose();
  }

  Future<void> _export() async {
    final report = _visibleReport;
    if (report == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      if (widget.exporter != null) {
        await widget.exporter!(report);
      } else {
        final title = report.title.replaceAll(
          RegExp(r'[^\p{L}\p{N}_-]+', unicode: true),
          '_',
        );
        await FileSaver.instance.saveFile(
          name:
              'report_${title.isEmpty ? report.occasionId : title.substring(0, title.length.clamp(0, 80))}',
          bytes: Uint8List.fromList(utf8.encode(formatReportText(report))),
          fileExtension: 'txt',
          mimeType: MimeType.text,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ReportStrings.exportError)));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  ReportExchangeRates? _rates;
  bool _ratesFailed = false;
  Future<void> _loadRates() async {
    try {
      final rates =
          await (widget.exchangeRateLoader ?? DbEshop.getReportExchangeRates)();
      if (mounted) {
        setState(() {
          _rates = rates;
          _ratesFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _ratesFailed = true);
    }
  }

  int _rangeDays = 0;
  bool _cumulative = true;
  String? _currency;

  Widget _section(
    String title,
    String help,
    List<Widget> children, {
    String? details,
  }) =>
      Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: .55)),
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  _ReportInfoIcon(help: details ?? help, label: title),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      );

  List<Widget> _timelines(OccasionReport report) {
    if (!report.hasTimeline) return [Text(ReportStrings.timelineUnavailable)];
    final dates = [
      ...report.orderDays.where((d) => d.count > 0).map((d) => d.day),
      ...report.paymentDays
          .where((d) =>
              reportMinorUnits(d.received) > BigInt.zero ||
              reportMinorUnits(d.returned) > BigInt.zero)
          .map((d) => d.day),
    ]..sort();
    if (dates.isEmpty) {
      return [
        _section(ReportStrings.orderTimeline, ReportStrings.orderTimelineHelp, [
          Text(ReportStrings.timelineEmpty),
        ]),
      ];
    }
    final occasion = RightsService.currentOccasion();
    final occasionEnd = occasion?.id?.toString() == report.occasionId
        ? occasion?.endTime
        : null;
    final end = reportTimelineEnd(
      today: reportDay(report.generatedAt),
      lastActivity: dates.last,
      occasionEnd: occasionEnd == null ? null : reportDay(occasionEnd),
    );
    final start = _rangeDays == 0
        ? dates.first
        : end.subtract(Duration(days: _rangeDays - 1));
    final colors = Theme.of(context).colorScheme;
    final currencies = {
      ...report.orderDays.map((d) => d.currency),
      ...report.money.map((m) => m.currency),
      ...report.paymentDays.map((d) => d.currency),
    }.toList()
      ..sort();
    final selected = currencies.contains(_currency) || _currency == '*'
        ? _currency!
        : currencies.length > 1
            ? '*'
            : currencies.first;
    final visible = selected == '*' ? currencies : [selected];
    final orders = <DateTime, BigInt>{};
    for (final d in report.orderDays.where(
      (d) => visible.contains(d.currency),
    )) {
      orders.update(
        d.day,
        (value) => value + BigInt.from(d.count),
        ifAbsent: () => BigInt.from(d.count),
      );
    }
    final combined = selected == '*';
    final canConvert = !combined ||
        visible.every(
          (c) => c == 'CZK' || (_rates?.rates.containsKey(c) ?? false),
        );
    Map<DateTime, BigInt> payments(bool returned) {
      final amounts = <DateTime, BigInt>{};
      for (final day in report.paymentDays.where(
        (d) => visible.contains(d.currency),
      )) {
        final cents = reportMinorUnits(returned ? day.returned : day.received);
        final value = combined ? _rates!.toCzk(cents, day.currency) : cents;
        amounts.update(day.day, (old) => old + value, ifAbsent: () => value);
      }
      return amounts;
    }

    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (currencies.length > 1)
              _filterGroup([
                for (final currency in currencies)
                  _filter(currency, selected == currency,
                      () => setState(() => _currency = currency)),
                _filter(ReportStrings.compareCurrencies, selected == '*',
                    () => setState(() => _currency = '*')),
              ])
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(selected,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: colors.onSurfaceVariant)),
              ),
            _filterGroup([
              for (final range in [30, 90, 0])
                _filter(
                  range == 0
                      ? ReportStrings.allDays
                      : range == 30
                          ? ReportStrings.days30
                          : ReportStrings.days90,
                  _rangeDays == range,
                  () => setState(() => _rangeDays = range),
                ),
            ]),
            _filterGroup([
              _filter(ReportStrings.daily, !_cumulative,
                  () => setState(() => _cumulative = false)),
              _filter(ReportStrings.cumulative, _cumulative,
                  () => setState(() => _cumulative = true)),
            ]),
          ],
        ),
      ),
      _columns([
        _section(ReportStrings.orderTimeline, ReportStrings.orderTimelineHelp, [
          ReportTimelineChart(
            start: start,
            end: end,
            cumulative: _cumulative,
            series: [
              ReportTimelineSeries(
                ReportStrings.orders,
                colors.primary,
                orders,
              ),
            ],
          ),
        ]),
        _section(
          ReportStrings.paymentTimeline,
          ReportStrings.paymentTimelineHelp,
          [
            if (canConvert)
              ReportTimelineChart(
                start: start,
                end: end,
                cumulative: _cumulative,
                currency: combined ? 'CZK' : selected,
                series: [
                  ReportTimelineSeries(
                    ReportStrings.received,
                    colors.primary,
                    payments(false),
                  ),
                  ReportTimelineSeries(
                    ReportStrings.returned,
                    colors.error,
                    payments(true),
                  ),
                ],
              )
            else if (_ratesFailed)
              Text(ReportStrings.ratesUnavailable)
            else
              const LinearProgressIndicator(),
            if (combined && canConvert) ...[
              Text(
                '${ReportStrings.currencyComparisonHelp} ${DateFormat('d. M. yyyy').format(_rates!.date)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final c in visible.where((c) => c != 'CZK'))
                    Text(
                      _rates!.rates[c]!.label,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ]),
    ];
  }

  Widget _filterGroup(List<Widget> children) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: .55)),
        ),
        child: Wrap(spacing: 4, runSpacing: 4, children: children),
      );

  Widget _filter(String label, bool selected, VoidCallback onSelected) {
    final colors = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: colors.primary,
      backgroundColor: colors.surface,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: selected ? colors.onPrimary : colors.onSurfaceVariant),
      onSelected: (_) => onSelected(),
    );
  }

  Widget _columns(List<Widget> children) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 850 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.4) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            );
          }
          return Table(
            defaultColumnWidth: const FlexColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
            columnWidths: {
              for (var i = 1; i < children.length * 2 - 1; i += 2)
                i: const FixedColumnWidth(12),
            },
            children: [
              TableRow(children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  children[i],
                ],
              ]),
            ],
          );
        },
      );

  Widget _value(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelText = Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            );
            final valueStyle = Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600);
            if (MediaQuery.textScalerOf(context).scale(1) > 1.4) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  labelText,
                  Text(value, style: valueStyle),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: labelText),
                const SizedBox(width: 12),
                Flexible(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Text(value,
                        textAlign: TextAlign.end, style: valueStyle),
                  ),
                ),
              ],
            );
          },
        ),
      );

  Widget _moneyCard(ReportMoney money) => _section(
        money.currency,
        ReportStrings.moneyHelp,
        [
          for (final amount in money.amounts.entries)
            if (money.hasDeposits || !amount.key.contains('deposit'))
              _value(ReportStrings.metric(amount.key),
                  '${amount.value} ${money.currency}'),
        ],
        details: ReportStrings.moneyDetails,
      );

  Widget _overview(OccasionReport report) => LayoutBuilder(
        builder: (context, constraints) {
          final orders = _states(ReportStrings.orders, report.orders);
          final tickets = _states(ReportStrings.tickets, report.tickets);
          final spots = report.spotsTotal == 0
              ? null
              : _section(ReportStrings.spots, ReportStrings.spotsHelp, [
                  _value(ReportStrings.spots,
                      '${report.spotsOccupied} / ${report.spotsTotal}'),
                  _value(ReportStrings.free, '${report.spotsFree}'),
                  Semantics(
                    label:
                        '${ReportStrings.spots}: ${report.spotsOccupied} / ${report.spotsTotal}',
                    child: LinearProgressIndicator(
                      value: report.spotsOccupied / report.spotsTotal,
                      minHeight: 6,
                    ),
                  ),
                ]);
          final money = report.money.map(_moneyCard).toList();
          final columns = MediaQuery.textScalerOf(context).scale(1) > 1.4
              ? 1
              : constraints.maxWidth >= 1100
                  ? 3
                  : constraints.maxWidth >= 700
                      ? 2
                      : 1;
          final groups = columns == 3
              ? [
                  [orders, if (spots != null) spots],
                  if (ReportStrings.hasTickets) [tickets],
                  money
                ]
              : columns == 2
                  ? [
                      [orders, if (ReportStrings.hasTickets) tickets],
                      [if (spots != null) spots, ...money]
                    ]
                  : [
                      [
                        orders,
                        if (ReportStrings.hasTickets) tickets,
                        if (spots != null) spots,
                        ...money
                      ]
                    ];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: groups[i],
                )),
              ],
            ],
          );
        },
      );

  String _stateLabel(String state) => ReportStrings.state(state);

  Widget _states(String title, ReportCounts counts) =>
      _section(title, ReportStrings.statesHelp, [
        _value(title, '${counts.total}'),
        for (final entry in counts.states.entries)
          Semantics(
            label:
                '${_stateLabel(entry.key)}: ${entry.value} / ${counts.total}',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text(_stateLabel(entry.key),
                              style: Theme.of(context).textTheme.bodySmall)),
                      const SizedBox(width: 12),
                      Text('${entry.value}',
                          style: Theme.of(context).textTheme.labelLarge),
                    ]),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: counts.total == 0 ? 0 : entry.value / counts.total,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(3),
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final r = _visibleReport;
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(builder: (context, constraints) {
                    final title = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (r != null) ...[
                          Text(r.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            '${ReportStrings.snapshot}: ${DateFormat('d. M. yyyy HH:mm').format(r.generatedAt.toLocal())}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                        ],
                      ],
                    );
                    final actions = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (r != null)
                          Semantics(
                            toggled: _onlyValid,
                            child: TextButton.icon(
                              key: const ValueKey('reportValidityFilter'),
                              onPressed: () => setState(() => _onlyValid = !_onlyValid),
                              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                              icon: Icon(_onlyValid ? Icons.check_box_outlined : Icons.check_box_outline_blank, size: 18),
                              label: Text(_onlyValid ? ReportStrings.onlyValid : ReportStrings.includingCancelled),
                            ),
                          ),
                        TextButton.icon(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                    _load();
                                  }),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                          ),
                          icon: const Icon(Icons.refresh),
                          label: Text(ReportStrings.refresh),
                        ),
                        if (r != null)
                          PopupMenuButton<String>(
                            tooltip: ReportStrings.details,
                            constraints: const BoxConstraints(minWidth: 48),
                            onSelected: (value) {
                              if (value == 'export') {
                                _export();
                              } else {
                                setState(() => _text = !_text);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'text',
                                child: Text(
                                  _text
                                      ? ReportStrings.graphic
                                      : ReportStrings.text,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'export',
                                enabled: !_exporting,
                                child: Text(ReportStrings.export),
                              ),
                            ],
                          ),
                      ],
                    );
                    if (constraints.maxWidth < 600 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.4) {
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            title,
                            const SizedBox(height: 8),
                            actions
                          ]);
                    }
                    return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Expanded(child: title), actions]);
                  }),
                  const SizedBox(height: 24),
                  if (_loading) const LinearProgressIndicator(),
                  if (_error) Text(ReportStrings.error),
                  if (r != null && _text) SelectableText(formatReportText(r)),
                  if (r != null && !_text) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final metricCount = 1 +
                            (ReportStrings.hasTickets ? 1 : 0) +
                            (r.spotsTotal > 0 ? 1 : 0) +
                            r.money.length;
                        final columns = math.min(
                            metricCount,
                            MediaQuery.textScalerOf(context).scale(1) > 1.4
                                ? 1
                                : constraints.maxWidth >= 1100
                                    ? 5
                                    : constraints.maxWidth >= 850
                                        ? 4
                                        : constraints.maxWidth >= 350
                                            ? 2
                                            : 1);
                        final width =
                            (constraints.maxWidth - (columns - 1) * 12) /
                                columns;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _summary(
                              ReportStrings.orders,
                              '${r.orders.total}',
                              width,
                            ),
                            if (ReportStrings.hasTickets)
                              _summary(
                                ReportStrings.tickets,
                                '${r.tickets.total}',
                                width,
                              ),
                            if (r.spotsTotal > 0)
                              _summary(
                                ReportStrings.spots,
                                '${r.spotsOccupied} / ${r.spotsTotal}',
                                width,
                              ),
                            for (final m in r.money)
                              _summary(
                                '${ReportStrings.metric('net_received')} (${m.currency})',
                                m.amounts['net_received']!,
                                width,
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    ..._timelines(r),
                    const SizedBox(height: 24),
                    Text(
                      ReportStrings.overview,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    _overview(r),
                    for (final w in r.warnings.entries)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          '${ReportStrings.metric(w.key)} (${w.value})',
                        ),
                      ),
                    _section(
                      ReportStrings.products,
                      ReportStrings.productsHelp,
                      [_products(r.products)],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _products(List<ReportProduct> products) => LayoutBuilder(
        builder: (context, constraints) {
          if (products.isEmpty) return Text(ReportStrings.empty);
          if (constraints.maxWidth < 600 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.4) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in products)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.typeTitle ?? ReportStrings.noType),
                        Text(
                          p.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text('${ReportStrings.count}: ${p.count}'),
                      ],
                    ),
                  ),
              ],
            );
          }
          Widget cell(String value) =>
              Padding(padding: const EdgeInsets.all(8), child: Text(value));
          return Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(4),
              2: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [
              TableRow(
                children: [
                  cell(ReportStrings.type),
                  cell(ReportStrings.product),
                  cell(ReportStrings.count),
                ],
              ),
              for (final p in products)
                TableRow(
                  children: [
                    cell(p.typeTitle ?? ReportStrings.noType),
                    cell(p.title),
                    cell('${p.count}'),
                  ],
                ),
            ],
          );
        },
      );

  Widget _summary(String label, String value, double width) => SizedBox(
        width: width,
        child: Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: .55)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ReportInfoIcon extends StatefulWidget {
  final String help, label;
  const _ReportInfoIcon({required this.help, required this.label});
  @override
  State<_ReportInfoIcon> createState() => _ReportInfoIconState();
}

class _ReportInfoIconState extends State<_ReportInfoIcon> {
  GlobalKey<TooltipState> _key = GlobalKey<TooltipState>();
  Timer? _timer;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
        key: _key,
        message: widget.help,
        excludeFromSemantics: true,
        triggerMode: TooltipTriggerMode.manual,
        waitDuration: const Duration(milliseconds: 350),
        exitDuration: const Duration(milliseconds: 100),
        showDuration: const Duration(seconds: 10),
        constraints: BoxConstraints(
          maxWidth: math.min(
            360,
            math.max(0, MediaQuery.sizeOf(context).width - 32),
          ),
        ),
        child: Semantics(
          label: '${widget.label}: ${widget.help}',
          child: IconButton(
            iconSize: 18,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              _key.currentState?.ensureTooltipVisible();
              _timer?.cancel();
              _timer = Timer(const Duration(seconds: 10), () {
                if (mounted) setState(() => _key = GlobalKey<TooltipState>());
              });
            },
          ),
        ),
      );
}

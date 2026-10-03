import 'dart:async';
import 'dart:convert';
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
import 'package:fstapp/styles/styles_config.dart';

class ReportTab extends StatefulWidget {
  final String? occasionLink;
  final String? identityKey;
  final Future<OccasionReport> Function(String)? loader;
  final Future<void> Function(OccasionReport)? exporter;
  const ReportTab(
      {super.key,
      this.occasionLink,
      this.identityKey,
      this.loader,
      this.exporter});

  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> {
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
  }

  @override
  void didUpdateWidget(covariant ReportTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateKey();
  }

  void _updateKey() {
    final link = widget.occasionLink ??
        context.routeData.params.getString(AppRouter.linkFormatted);
    final identity = widget.identityKey ??
        '${Supabase.instance.client.auth.currentUser?.id}/${RightsService.currentUser()?.id}/${RightsService.currentOccasion()?.organization}/${RightsService.isEditorOrderView()}';
    final key = '$identity/$link';
    if (key == _key) return;
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
      final report =
          await (widget.loader ?? DbEshop.getReportForOccasion)(_link!);
      if (!mounted || generation != _generation) return;
      setState(() {
        _report = report;
        _loading = false;
      });
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
    final report = _report;
    if (report == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      if (widget.exporter != null) {
        await widget.exporter!(report);
      } else {
        final title = report.title
            .replaceAll(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true), '_');
        await FileSaver.instance.saveFile(
          name:
              'report_${title.isEmpty ? report.occasionId : title.substring(0, title.length.clamp(0, 80))}',
          bytes: Uint8List.fromList(utf8.encode(report.text)),
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

  void _explain(String text) {
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(ReportStrings.details),
              content: SingleChildScrollView(child: Text(text)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    style:
                        TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    child: Text(ReportStrings.close))
              ],
            ));
  }

  Widget _section(String title, String help, List<Widget> children,
          {String? details}) =>
      Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                Text(help),
                Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                        style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48)),
                        onPressed: () => _explain(details ?? help),
                        icon: const Icon(Icons.info_outline),
                        label: Text(ReportStrings.details))),
                ...children
              ],
            )),
      );

  Widget _value(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label),
          Text(value, style: Theme.of(context).textTheme.titleMedium)
        ]),
      );

  Widget _states(String title, ReportCounts counts) =>
      _section(title, ReportStrings.statesHelp, [
        _value(title, '${counts.total}'),
        for (final entry in counts.states.entries)
          Semantics(
              label: '${entry.key}: ${entry.value} / ${counts.total}',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${entry.key}: ${entry.value}'),
                    LinearProgressIndicator(
                        value:
                            counts.total == 0 ? 0 : entry.value / counts.total,
                        minHeight: 8)
                  ],
                ),
              )),
      ]);

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
        body: SafeArea(
            child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (r != null) ...[
                  Text(r.title,
                      style: Theme.of(context).textTheme.headlineSmall),
                  Text(r.generatedAt.toLocal().toString())
                ],
                Wrap(spacing: 8, runSpacing: 8, children: [
                  TextButton.icon(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                                _load();
                              }),
                      style:
                          TextButton.styleFrom(minimumSize: const Size(48, 48)),
                      icon: const Icon(Icons.refresh),
                      label: Text(ReportStrings.refresh)),
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
                            child: Text(_text
                                ? ReportStrings.graphic
                                : ReportStrings.text)),
                        PopupMenuItem(
                            value: 'export',
                            enabled: !_exporting,
                            child: Text(ReportStrings.export)),
                      ],
                    ),
                ]),
                if (_loading) const LinearProgressIndicator(),
                if (_error) Text(ReportStrings.error),
                if (r != null && _text) SelectableText(r.text),
                if (r != null && !_text) ...[
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    _summary(ReportStrings.orders, '${r.orders.total}'),
                    _summary(ReportStrings.tickets, '${r.tickets.total}'),
                    if (r.spotsTotal > 0)
                      _summary(ReportStrings.spots,
                          '${r.spotsOccupied} / ${r.spotsTotal}'),
                    for (final m in r.money)
                      _summary(
                          '${ReportStrings.metric('net_received')} (${m.currency})',
                          m.amounts['net_received']!),
                  ]),
                  if (r.spotsTotal > 0)
                    _section(ReportStrings.spots, ReportStrings.spotsHelp, [
                      _value(ReportStrings.spots,
                          '${r.spotsOccupied} / ${r.spotsTotal}'),
                      _value(ReportStrings.free, '${r.spotsFree}'),
                      Semantics(
                          label:
                              '${ReportStrings.spots}: ${r.spotsOccupied} / ${r.spotsTotal}',
                          child: LinearProgressIndicator(
                              value: r.spotsOccupied / r.spotsTotal,
                              minHeight: 12)),
                    ]),
                  _states(ReportStrings.orders, r.orders),
                  _states(ReportStrings.tickets, r.tickets),
                  for (final m in r.money)
                    _section(
                        m.currency,
                        ReportStrings.moneyHelp,
                        [
                          for (final a in m.amounts.entries)
                            if (m.hasDeposits || !a.key.contains('deposit'))
                              _value(ReportStrings.metric(a.key),
                                  '${a.value} ${m.currency}'),
                        ],
                        details: ReportStrings.moneyDetails),
                  for (final w in r.warnings.entries)
                    Semantics(
                        liveRegion: true,
                        child: Text(
                            '${ReportStrings.metric(w.key)} (${w.value})')),
                  _section(ReportStrings.products, ReportStrings.productsHelp, [
                    _products(r.products),
                  ]),
                ],
              ],
            )),
      ),
    )));
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
                              Text(p.title,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text('${ReportStrings.count}: ${p.count}'),
                            ])),
                ]);
          }
          Widget cell(String value) =>
              Padding(padding: const EdgeInsets.all(8), child: Text(value));
          return Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(4),
              2: FlexColumnWidth()
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [
              TableRow(children: [
                cell(ReportStrings.type),
                cell(ReportStrings.product),
                cell(ReportStrings.count)
              ]),
              for (final p in products)
                TableRow(children: [
                  cell(p.typeTitle ?? ReportStrings.noType),
                  cell(p.title),
                  cell('${p.count}')
                ]),
            ],
          );
        },
      );

  Widget _summary(String label, String value) => SizedBox(
      width: MediaQuery.sizeOf(context).width < 600
          ? MediaQuery.sizeOf(context).width - 24
          : 240,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(16), child: _value(label, value))));
}

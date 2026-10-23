import 'ticket_batch_print_downloads.dart';
import '../models/ticket_batch_document_part.dart';
import 'order_history_dialog.dart';
import 'package:fstapp/components/single_data_grid/admin_tab_activity.dart';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:uuid/uuid.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ticket_batch_commands.dart';
import '../ticket_batch_strings.dart';

Future<bool> createTicketBatchFromSpots(BuildContext context,
    {required int blueprintId, required List<int> spotIds}) async {
  final options = await Supabase.instance.client.rpc(
      'get_ticket_batch_create_options',
      params: {'p_occasion': RightsService.currentOccasionId()});
  if (!context.mounted) return false;
  final id = await showDialog<String>(
      context: context,
      builder: (_) => _BatchCreateDialog(
          options: List.from(options)
              .where((f) => f['blueprint'] == blueprintId)
              .toList(),
          spotIds: spotIds));
  return id != null;
}

String _text(String key) => TicketBatchStrings.text(key);

@RoutePage()
class TicketBatchesPage extends StatelessWidget {
  const TicketBatchesPage({super.key});
  @override
  Widget build(BuildContext context) => const AutoRouter();
}

@RoutePage()
class TicketBatchListPage extends StatefulWidget {
  const TicketBatchListPage({super.key});
  @override
  State<TicketBatchListPage> createState() => _TicketBatchListState();
}

class _TicketBatchListState extends State<TicketBatchListPage> {
  final _db = Supabase.instance.client;
  late Future<List<dynamic>> _data;
  bool? _wasActive;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = AdminTabActivity.isActive(context);
    if (active && _wasActive == false) _data = _load();
    _wasActive = active;
  }

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<List<dynamic>> _load() async =>
      List.from(await _db.rpc('get_ticket_batches',
          params: {'p_occasion': RightsService.currentOccasionId()}));
  void _reload() => setState(() {
        _data = _load();
      });
  Future<void> _create() async {
    final options = await ExceptionHandler.guard<List<dynamic>>(context,
        futureFunction: () async => List.from(await _db.rpc(
            'get_ticket_batch_create_options',
            params: {'p_occasion': RightsService.currentOccasionId()})));
    if (!mounted || options == null) return;
    final id = await showDialog<String>(
        context: context, builder: (_) => _BatchCreateDialog(options: options));
    if (!mounted || id == null) return;
    _reload();
    await context.router.push(TicketBatchDetailRoute(batchId: id));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                  child: Text(TicketBatchStrings.title,
                      style: Theme.of(context).textTheme.titleLarge)),
              if (RightsService.canUpdateOrders())
                FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add),
                    label: Text(TicketBatchStrings.create)),
              IconButton(
                  onPressed: _reload,
                  tooltip: _text('refresh'),
                  icon: const Icon(Icons.refresh))
            ])),
        Expanded(
            child: FutureBuilder<List<dynamic>>(
                future: _data,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                        child: TextButton(
                            onPressed: _reload, child: Text(_text('retry'))));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final rows = snapshot.data!;
                  if (rows.isEmpty) {
                    return Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_text('empty'))));
                  }
                  return ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final b = rows[index] as Map;
                        final counts = b['counts'] as Map;
                        return ListTile(
                            title: Text(b['title']),
                            subtitle: Text(
                                '${_text('available')}: ${counts['available']}   ${_text('sold')}: ${counts['soldActive']}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await context.router.push(
                                  TicketBatchDetailRoute(batchId: b['id']));
                              if (mounted) _reload();
                            });
                      });
                }))
      ]);
}

class _BatchCreateDialog extends StatefulWidget {
  const _BatchCreateDialog({required this.options, this.spotIds = const []});
  final List<int> spotIds;
  final List<dynamic> options;
  @override
  State<_BatchCreateDialog> createState() => _BatchCreateState();
}

class _BatchCreateState extends State<_BatchCreateDialog> {
  final _title = TextEditingController(),
      _count = TextEditingController(text: '10');
  final _spotSecret = const Uuid().v4();
  int? _form, _product;
  bool _busy = false;
  Map? _preview;
  List get _products =>
      widget.options.where((f) => f['id'] == _form).firstOrNull?['products'] ??
      [];
  @override
  void dispose() {
    _title.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final n = widget.spotIds.isEmpty
        ? int.tryParse(_count.text)
        : widget.spotIds.length;
    if (_form == null ||
        (widget.spotIds.isEmpty && _product == null) ||
        n == null ||
        n < 1 ||
        n > 200 ||
        _title.text.trim().isEmpty) {
      return;
    }
    setState(() => _busy = true);
    final selection = widget.spotIds.isNotEmpty
        ? widget.spotIds.map((id) => <String, dynamic>{'spot': id}).toList()
        : List.generate(
            n,
            (_) => <String, dynamic>{
                  'fields': [
                    {'product_type': _product}
                  ]
                });
    await ExceptionHandler.guardVoid(context, futureFunction: () async {
      if (_preview == null) {
        final result = await Supabase.instance.client.rpc(
            'preview_ticket_batch',
            params: {'p_form': _form, 'p_selection': selection});
        if (mounted) setState(() => _preview = Map.from(result));
      } else {
        final result =
            await SupabaseTicketBatchCommands(Supabase.instance.client).create(
                formId: _form!,
                title: _title.text.trim(),
                selection: selection,
                spotSecret: widget.spotIds.isEmpty ? null : _spotSecret);
        if (mounted) Navigator.of(context).pop(result['batchId'] as String);
      }
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AppAlertDialog(
          title: Text(TicketBatchStrings.create),
          dismissible: !_busy,
          content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Text(_text('explanation')),
                    TextField(
                        controller: _title,
                        maxLength: 200,
                        enabled: !_busy,
                        decoration: InputDecoration(labelText: _text('name')),
                        onChanged: (_) => setState(() => _preview = null)),
                    DropdownButtonFormField<int>(
                        initialValue: _form,
                        decoration: InputDecoration(labelText: _text('form')),
                        items: [
                          for (final f in widget.options)
                            DropdownMenuItem(
                                value: f['id'] as int,
                                child: Text(f['title'] ?? '#${f['id']}'))
                        ],
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                  _form = v;
                                  _product = null;
                                  _preview = null;
                                })),
                    if (widget.spotIds.isEmpty)
                      DropdownButtonFormField<int>(
                          key: ValueKey(_form),
                          initialValue: _product,
                          decoration:
                              InputDecoration(labelText: _text('product')),
                          items: [
                            for (final p in _products)
                              DropdownMenuItem(
                                  value: p['id'] as int,
                                  child: Text(
                                      '${p['title']} - ${p['price']} ${p['currency']}'))
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setState(() {
                                    _product = v;
                                    _preview = null;
                                  })),
                    if (widget.spotIds.isEmpty)
                      TextField(
                          controller: _count,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          decoration:
                              InputDecoration(labelText: _text('quantity')),
                          onChanged: (_) => setState(() => _preview = null)),
                    if (_preview != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                              '${_text('total')}: ${(_preview!['prices'] as List).map((p) => '${p['amount']} ${p['currency_code']}').join(', ')}')),
                  ]))),
          actions: [
            FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy
                    ? _text('working')
                    : _preview == null
                        ? _text('preview')
                        : TicketBatchStrings.create))
          ]);
}

@RoutePage()
class TicketBatchDetailPage extends StatefulWidget {
  const TicketBatchDetailPage(
      {super.key, @PathParam('batchId') required this.batchId});
  final String batchId;
  @override
  State<TicketBatchDetailPage> createState() => _TicketBatchDetailState();
}

class _TicketBatchDetailState extends State<TicketBatchDetailPage> {
  final _db = Supabase.instance.client;
  final _selected = <int>{};
  final _lookup = TextEditingController();
  late final _commands = SupabaseTicketBatchCommands(_db);
  late Future<Map<String, dynamic>> _data;
  bool _busy = false;
  Map? _receipt;
  bool? _wasActive;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = AdminTabActivity.isActive(context);
    if (active && _wasActive == false) _data = _load();
    _wasActive = active;
  }

  @override
  void initState() {
    super.initState();
    _data = _load(recover: true);
  }

  @override
  void dispose() {
    _lookup.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load({bool recover = false}) async {
    final result = Map<String, dynamic>.from(await _db
        .rpc('get_ticket_batch_detail', params: {'p_batch': widget.batchId}));
    if (result['occasion'] != RightsService.currentOccasionId()) {
      throw StateError('Batch belongs to another occasion');
    }
    if (recover) _receipt = await _commands.recoverPendingSale(widget.batchId);
    final items = List.from(result['items']);
    while (
        items.length < (result['counts']['total'] as num) && items.isNotEmpty) {
      final page = await _db.rpc('get_ticket_batch_detail', params: {
        'p_batch': widget.batchId,
        'p_after': items.last['ordinal']
      });
      final more = List.from(page['items']);
      if (more.isEmpty) break;
      items.addAll(more);
    }
    result['items'] = items;
    final availableIds = items
        .where((item) =>
            item['sale_order_id'] == null && item['state'] == 'ordered')
        .map((item) => item['id'] as int)
        .toSet();
    _selected.removeWhere((id) => !availableIds.contains(id));
    return result;
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() => _busy = true);
    await ExceptionHandler.guardVoid(context, futureFunction: action);
    if (mounted) {
      setState(() {
        _busy = false;
        _data = _load();
      });
    }
  }

  Future<void> _downloadExport(String format) => _act(() async {
        final response = await _db.functions.invoke(
            'prepare-ticket-batch-document',
            body: {'batchId': widget.batchId, 'format': format});
        final bytes = response.data;
        if (bytes is! Uint8List || bytes.isEmpty) {
          throw StateError('Batch download unavailable');
        }
        await FileSaver.instance.saveFile(
            name: 'tickets-${widget.batchId}',
            bytes: bytes,
            fileExtension: format == 'zip' ? 'zip' : 'pdf',
            mimeType: format == 'zip' ? MimeType.zip : MimeType.pdf);
      });

  Future<void> _sell(Map<String, dynamic> batch) async {
    // Re-read capabilities immediately before entering the financial confirmation.
    final fresh = await _load();
    if (!(fresh['allowedActions'] as List).contains('sell') || !mounted) return;
    final selected = (fresh['items'] as List)
        .where((i) => _selected.contains(i['id']))
        .toList();
    if (selected.isEmpty) return;
    final amount = selected.fold<num>(
        0,
        (sum, i) =>
            sum +
            (i['snapshot']['products'] as List)
                .fold<num>(0, (sum, p) => sum + (p['price'] as num)));
    final contact = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _BatchSaleDialog(
            count: selected.length,
            amount: amount,
            currency: batch['currency']));
    if (contact == null) return;
    final result = await _commands.sell(
        batchId: widget.batchId,
        ticketIds: _selected.toList(),
        contact: Map<String, String>.from(contact['contact']),
        sendTickets: contact['sendTickets']);
    if (mounted) {
      setState(() {
        _receipt = result;
        _selected.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: TextButton(
                  onPressed: () => setState(() {
                        _data = _load();
                      }),
                  child: Text(_text('retry'))));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final b = snapshot.data!,
            items = b['items'] as List,
            actions = b['allowedActions'] as List,
            counts = b['counts'] as Map;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          BackButton(
                              onPressed: () => context.router.maybePop()),
                          Expanded(
                              child: Text(b['title'],
                                  style:
                                      Theme.of(context).textTheme.titleLarge)),
                          IconButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                        _data = _load();
                                      }),
                              tooltip: _text('refresh'),
                              icon: const Icon(Icons.refresh))
                        ]),
                        Text(
                            '${_text('available')}: ${counts['available']}   ${_text('sold')}: ${counts['soldActive']}   ${_text('voided')}: ${counts['voidedUnsold']}'),
                        Text(
                            '${_text('stockValue')}: ${b['stockValue'] ?? 0} ${b['currency']}   ${_text('receivedAmount')}: ${b['receivedAmount'] ?? 0} ${b['currency']}'),
                        if ((b['sales'] as List? ?? const []).isNotEmpty)
                          Wrap(spacing: 8, children: [
                            for (final sale in b['sales'] as List)
                              TextButton(
                                  onPressed: () => showDialog(
                                      context: context,
                                      builder: (_) => OrderHistoryDialog(
                                          orderId: sale['id'] as int)),
                                  child: Text(
                                      '#${sale['symbol']} - ${sale['amount']} ${b['currency']}')),
                          ]),
                        if (_receipt != null)
                          SelectableText(
                              '${_text('receipt')}: ${_receipt!['orderId']} - ${_receipt!['amount']} ${_receipt!['currency']}'),
                        if ((counts['voidedUnsold'] as num) +
                                (counts['cancelledAfterSale'] as num) >
                            0)
                          Text(_text('voidWarning')),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          if (actions.contains('prepare'))
                            OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _act(() async {
                                          // Each request owns bounded work. A failed request retains the same batch.
                                          for (var n = 0; n < 220; n++) {
                                            final response = await _db.functions
                                                .invoke(
                                                    'prepare-ticket-batch-document',
                                                    body: {
                                                  'batchId': widget.batchId
                                                });
                                            final state =
                                                response.data['state'];
                                            if (state == 'ready' ||
                                                state == 'pending') {
                                              break;
                                            }
                                            if (state != 'progress') {
                                              throw StateError(
                                                  'Batch print failed');
                                            }
                                          }
                                        }),
                                icon: const Icon(Icons.print_outlined),
                                label: Text(_text('prepare'))),
                          if (actions.contains('sell'))
                            FilledButton(
                                onPressed: _busy ||
                                        _selected.isEmpty ||
                                        _selected.length > 20
                                    ? null
                                    : () => _act(() => _sell(b)),
                                child: Text(_text('sell'))),
                          if (actions.contains('void'))
                            TextButton(
                                onPressed: _busy || _selected.isEmpty
                                    ? null
                                    : () => _act(() async {
                                          final confirmed = await showDialog<
                                                  bool>(
                                              context: context,
                                              builder: (context) =>
                                                  AppAlertDialog(
                                                      title:
                                                          Text(_text('void')),
                                                      content: Text(
                                                          _text('voidConfirm')),
                                                      actions: [
                                                        TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    context,
                                                                    true),
                                                            child: Text(
                                                                _text('void')))
                                                      ]));
                                          if (confirmed == true) {
                                            await _commands.voidItems(
                                                widget.batchId,
                                                _selected.toList(),
                                                _text('voidReason'));
                                            _selected.clear();
                                          }
                                        }),
                                child: Text(_text('void'))),
                          TicketBatchPrintDownloads(
                              parts: [
                                for (final d in b['documents'] as List)
                                  TicketBatchDocumentPart.fromJson(
                                      Map<String, dynamic>.from(d))
                              ],
                              label: _text('download'),
                              a4Label: _text('downloadA4'),
                              zipLabel: _text('downloadZip'),
                              enabled: !_busy,
                              onSelected: _downloadExport),
                        ]),
                        TextField(
                            controller: _lookup,
                            enabled: !_busy,
                            decoration: InputDecoration(
                                labelText: _text('lookup'),
                                suffixIcon: IconButton(
                                    icon: const Icon(Icons.search),
                                    onPressed: () {
                                      final found = items.where((i) =>
                                          i['ticket_symbol'] ==
                                              _lookup.text.trim() &&
                                          i['sale_order_id'] == null &&
                                          i['state'] == 'ordered');
                                      if (found.isNotEmpty) {
                                        setState(() => _selected
                                            .add(found.first['id'] as int));
                                      }
                                    })),
                            onSubmitted: (value) {
                              final found = items.where((i) =>
                                  i['ticket_symbol'] == value.trim() &&
                                  i['sale_order_id'] == null &&
                                  i['state'] == 'ordered');
                              if (found.isNotEmpty) {
                                setState(() =>
                                    _selected.add(found.first['id'] as int));
                              }
                            }),
                      ])),
              if (_busy) const LinearProgressIndicator(),
              Expanded(
                  child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final i = items[index] as Map;
                        final available = i['sale_order_id'] == null &&
                            i['state'] == 'ordered';
                        return CheckboxListTile(
                            value: _selected.contains(i['id']),
                            onChanged: _busy || !available
                                ? null
                                : (value) => setState(() {
                                      if (value == true) {
                                        _selected.add(i['id'] as int);
                                      } else {
                                        _selected.remove(i['id']);
                                      }
                                    }),
                            title:
                                Text('${i['ordinal']}. ${i['ticket_symbol']}'),
                            subtitle: Text(i['state'] == 'storno'
                                ? _text('voided')
                                : available
                                    ? _text('available')
                                    : '${_text('sold')} - #${i['sale_order_id']}'));
                      }))
            ]);
      });
}

class _BatchSaleDialog extends StatefulWidget {
  const _BatchSaleDialog(
      {required this.count, required this.amount, required this.currency});
  final int count;
  final num amount;
  final String currency;
  @override
  State<_BatchSaleDialog> createState() => _BatchSaleState();
}

class _BatchSaleState extends State<_BatchSaleDialog> {
  final _email = TextEditingController();
  bool _send = false;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppAlertDialog(
          title: Text(_text('sell')),
          content: SizedBox(
              width: 400,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${widget.count} - ${widget.amount} ${widget.currency}'),
                Text(_text('cashConfirmation')),
                TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                        labelText: _text('email'),
                        errorText: validTicketBatchEmail(_email.text.trim())
                            ? null
                            : _text('invalidEmail')),
                    onChanged: (_) => setState(() {})),
                CheckboxListTile(
                    value: _send,
                    onChanged: (v) => setState(() => _send = v!),
                    title: Text(_text('sendTickets'))),
              ])),
          actions: [
            FilledButton(
                onPressed: !validTicketBatchEmail(_email.text.trim()) ||
                        (_send && _email.text.trim().isEmpty)
                    ? null
                    : () => Navigator.pop(context, {
                          'contact': {
                            if (_email.text.trim().isNotEmpty)
                              'email': _email.text.trim()
                          },
                          'sendTickets': _send
                        }),
                child: Text(_text('confirmSale')))
          ]);
}

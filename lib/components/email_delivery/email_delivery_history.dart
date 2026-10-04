import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/views/order_state_display.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:trina_grid/trina_grid.dart';
import 'email_delivery_model.dart';
import 'email_delivery_strings.dart';

class EmailDeliveryHistory extends StatefulWidget {
  final int? occasionId;
  final int? organizationId;
  final String? userId;
  final bool embedded;
  final bool ordersOnly;
  final int? orderId;
  final Future<dynamic> Function(String, Map<String, dynamic>)? read;
  const EmailDeliveryHistory(
      {super.key,
      this.occasionId,
      this.orderId,
      this.organizationId,
      this.userId,
      this.embedded = false,
      this.ordersOnly = false,
      this.read});
  @override
  State<EmailDeliveryHistory> createState() => _EmailDeliveryHistoryState();
}

class _EmailDeliveryHistoryState extends State<EmailDeliveryHistory> {
  bool _organizationScope = false;
  int _generation = 0;
  Map<String, dynamic>? _overview;
  SingleDataGridController<EmailDeliveryModel>? _controller;
  Future<dynamic> _read(String name, {required Map<String, dynamic> params}) =>
      widget.read?.call(name, params) ??
      Supabase.instance.client.rpc(name, params: params);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= _createController();
  }

  @override
  void didUpdateWidget(covariant EmailDeliveryHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.occasionId != widget.occasionId ||
        oldWidget.organizationId != widget.organizationId ||
        oldWidget.orderId != widget.orderId ||
        oldWidget.userId != widget.userId ||
        oldWidget.ordersOnly != widget.ordersOnly ||
        oldWidget.read != widget.read) {
      _organizationScope = false;
      _overview = null;
      _controller = _createController();
    }
  }

  SingleDataGridController<EmailDeliveryModel> _createController() {
    final generation = ++_generation;
    final params = <String, dynamic>{
      'p_occasion': _organizationScope ? null : widget.occasionId,
      'p_organization': widget.organizationId,
      'p_order': widget.orderId,
      'p_user': widget.userId,
      if (widget.ordersOnly) 'p_orders_only': true,
    };
    final read = widget.read ??
        (String name, Map<String, dynamic> args) async =>
            Supabase.instance.client.rpc(name, params: args);
    return SingleDataGridController<EmailDeliveryModel>(
      context: context,
      loadData: () async {
        final result =
            await ExceptionHandler.guard(context, futureFunction: () async {
          final rows = await EmailDeliveryModel.loadHistory(read, params);
          if (!widget.ordersOnly &&
              widget.orderId == null &&
              widget.userId == null) {
            final overview = await read('get_email_delivery_overview', {
              'p_occasion': params['p_occasion'],
              'p_organization': params['p_organization'],
            });
            if (mounted && generation == _generation && overview is Map) {
              setState(() => _overview = Map<String, dynamic>.from(overview));
            }
          }
          return rows;
        });
        return result ?? <EmailDeliveryModel>[];
      },
      fromPlutoJson: EmailDeliveryModel.fromPlutoJson,
      idColumn: 'id',
      firstColumnType: DataGridFirstColumn.none,
      actionsExtended: DataGridActionsController(
        isAddActionPossible: () => false,
        areAllActionsEnabled: () => false,
      ),
      headerChildren: [
        DataGridAction(
            name: CommonStrings.update,
            action: (controller, [originalAction]) => controller.reloadData())
      ],
      columns: [
        TrinaColumn(
            title: OrdersStrings.gridId,
            field: 'id',
            hide: true,
            readOnly: true,
            type: TrinaColumnType.number()),
        EshopColumns.orderSymbolColumn(),
        TrinaColumn(
            title: CommonStrings.date,
            field: 'created_at',
            readOnly: true,
            width: 160,
            type: TrinaColumnType.text()),
        TrinaColumn(
            title: CommonStrings.type,
            field: 'kind',
            readOnly: true,
            width: 240,
            type: TrinaColumnType.text()),
        TrinaColumn(
            title: OrdersStrings.gridState,
            field: 'state',
            renderer: (cell) {
              final model = cell.row.cells[EmailDeliveryModel.reference]!.value
                  as EmailDeliveryModel;
              return OrderStateDisplay(
                formattedState: '${model.state};${cell.cell.value}',
                getBackground: (state) {
                  final colors = Theme.of(context).colorScheme;
                  if ([
                    'bounce',
                    'complaint',
                    'reject',
                    'rendering_failure',
                    'dead',
                    'unknown',
                    'post_action_failed'
                  ].contains(state)) return colors.errorContainer;
                  if (['delivery', 'open', 'click'].contains(state))
                    return colors.tertiaryContainer;
                  if ([
                    'pending',
                    'preparing',
                    'sending',
                    'blocked',
                    'retry_wait',
                    'delay'
                  ].contains(state)) return colors.secondaryContainer;
                  return colors.surfaceContainerHighest;
                },
              );
            },
            readOnly: true,
            width: 280,
            type: TrinaColumnType.text()),
        TrinaColumn(
            title: CommonStrings.detailsLabel,
            field: 'detail',
            readOnly: true,
            width: 100,
            enableFilterMenuItem: false,
            type: TrinaColumnType.text(),
            renderer: (cell) => IconButton(
                tooltip: CommonStrings.detailsLabel,
                icon: const Icon(Icons.info_outline),
                onPressed: () => _detail((cell
                        .row
                        .cells[EmailDeliveryModel.reference]!
                        .value as EmailDeliveryModel)
                    .messageId))),
      ],
    );
  }

  Future<void> _detail(String messageId) async {
    final result = await ExceptionHandler.guard(context,
        futureFunction: () => _read('get_email_delivery_detail',
            params: {'p_message': messageId}));
    if (!mounted || result is! Map) return;
    await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text(EmailDeliveryStrings.history),
              content: SizedBox(
                  width: 400,
                  child: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(EmailDeliveryStrings.state(
                            result['message']?['tracking_policy'] == 'disabled'
                                ? 'tracking_disabled'
                                : result['message']?['clicked_at'] != null
                                    ? 'click'
                                    : result['message']?['opened_at'] != null
                                        ? 'open'
                                        : 'not_observed')),
                        if (result['message']?['last_error'] ==
                            'post_action_failed')
                          Text(
                              EmailDeliveryStrings.state('post_action_failed')),
                        for (final entry in (result['attempts'] as List? ?? []))
                          Text(
                              '${EmailDeliveryStrings.state(entry['state'].toString())} - ${entry['at']}${entry['error'] == null ? '' : ' - ${entry['error']}'}'),
                        for (final entry in (result['events'] as List? ?? []))
                          Text(
                              '${EmailDeliveryStrings.state(entry['type'].toString())} - ${entry['at']}'),
                      ]))),
            ));
  }

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      width: widget.embedded ? double.infinity : 900,
      height: widget.embedded ? double.infinity : 480,
      child: Column(children: [
        if (!widget.ordersOnly &&
            widget.organizationId != null &&
            widget.occasionId != null &&
            widget.orderId == null &&
            widget.userId == null)
          SwitchListTile(
              title: Text(EmailDeliveryStrings.organizationScope),
              value: _organizationScope,
              onChanged: (value) => setState(() {
                    _organizationScope = value;
                    _overview = null;
                    _controller = _createController();
                  })),
        if (_overview != null)
          Wrap(spacing: 16, children: [
            for (final key in [
              'accepted',
              'delivered',
              'bounced',
              'complained',
              'feedback_overdue',
              'unknown',
              'dead'
            ])
              Text('${EmailDeliveryStrings.state({
                    'delivered': 'delivery',
                    'bounced': 'bounce',
                    'complained': 'complaint'
                  }[key] ?? key)}: ${_overview![key]}')
          ]),
        Expanded(
            child: SingleTableDataGrid<EmailDeliveryModel>(_controller!,
                key: ObjectKey(_controller))),
      ]),
    );
    return widget.embedded ? content : Dialog(child: content);
  }
}

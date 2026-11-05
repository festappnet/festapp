import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/email_delivery/email_delivery_history.dart';
import 'package:fstapp/components/email_delivery/email_delivery_strings.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/services/locale_date_time.dart';

import '../sale_opening_strings.dart';

class SaleOpeningSubscriber implements ITrinaRowModel {
  SaleOpeningSubscriber(this.data);
  final Map<String, dynamic> data;
  @override
  String get id => data['id'] as String;
  @override
  TrinaRow toTrinaRow(BuildContext context) => TrinaRow(
    cells: {
      'id': TrinaCell(value: id),
      'model': TrinaCell(value: this),
      'email': TrinaCell(value: data['email']),
      'lang': TrinaCell(value: data['lang']),
      'state': TrinaCell(
        value: switch (data['state']) {
          'active' => SaleOpeningStrings.active,
          'unsubscribed' => SaleOpeningStrings.unsubscribed,
          _ => SaleOpeningStrings.closed,
        },
      ),
      'created_at': TrinaCell(
        value: LocaleDateTime.instant(
          data['created_at'],
          Localizations.localeOf(context).toString(),
        ),
      ),
      'delivery': TrinaCell(
        value: ((data['messages'] as List?) ?? [])
            .map((m) => EmailDeliveryStrings.state(m['state']))
            .join(', '),
      ),
    },
  );
  @override
  Future<void> deleteMethod(BuildContext context) async =>
      throw UnsupportedError('read only');
  @override
  Future<void> updateMethod(BuildContext context) async =>
      throw UnsupportedError('read only');
  @override
  String toBasicString() => data['email'] as String;
}

class SaleOpeningSubscribers extends StatefulWidget {
  const SaleOpeningSubscribers({super.key, required this.formId});
  final int formId;
  @override
  State<SaleOpeningSubscribers> createState() => _SaleOpeningSubscribersState();
}

class _SaleOpeningSubscribersState extends State<SaleOpeningSubscribers> {
  SingleDataGridController<SaleOpeningSubscriber>? grid;
  Future<List<SaleOpeningSubscriber>> load() async {
    final all = <SaleOpeningSubscriber>[];
    String? after;
    while (true) {
      final page = (await Supabase.instance.client.rpc(
        'get_sale_opening_subscribers',
        params: {'p_form': widget.formId, 'p_after': after},
      )) as List;
      all.addAll(
        page.map((v) => SaleOpeningSubscriber(Map<String, dynamic>.from(v))),
      );
      if (page.length < 100) return all;
      final next = page.last['id'] as String;
      if (next == after)
        throw const FormatException('subscriber cursor did not advance');
      after = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    grid ??= SingleDataGridController<SaleOpeningSubscriber>(
      context: context,
      loadData: load,
      fromPlutoJson: (value) => value['model'] as SaleOpeningSubscriber,
      firstColumnType: DataGridFirstColumn.none,
      idColumn: 'id',
      actionsExtended: DataGridActionsController(
        isAddActionPossible: () => false,
        areAllActionsEnabled: () => false,
      ),
      exportOptions: ExportOptions(visible: false, fileName: ''),
      columns: [
        for (final column in [
          ('id', 'id'),
          ('email', SaleOpeningStrings.email),
          ('lang', Localizations.localeOf(context).languageCode),
          ('state', SaleOpeningStrings.subscribers),
          ('created_at', SaleOpeningStrings.subscribe),
          ('delivery', SaleOpeningStrings.delivered),
        ])
          TrinaColumn(
            title: column.$2,
            field: column.$1,
            type: TrinaColumnType.text(),
            readOnly: true,
            hide: column.$1 == 'id',
          ),
      ],
      onRowActivate: (row) async {
        final model = row;
        await showDialog<void>(
          context: context,
          builder: (context) => AppAlertDialog(
            title: Text(model.toBasicString()),
            onClose: () => Navigator.pop(context),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final m in (model.data['messages'] as List? ?? []))
                      FutureBuilder<dynamic>(
                        future: Supabase.instance.client.rpc(
                          'get_email_delivery_detail',
                          params: {'p_message': m['message_id']},
                        ),
                        builder: (context, snapshot) => snapshot.hasData
                            ? emailDeliveryMessageContent(
                                context,
                                snapshot.data as Map,
                              )
                            : Text(EmailDeliveryStrings.state(m['state'])),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    return SizedBox(
      width: 1000,
      height: 600,
      child: SingleTableDataGrid(grid!),
    );
  }
}

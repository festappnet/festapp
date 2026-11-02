import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/eshop/db_orders.dart';

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/models/form_response_model.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/data_services/rights_service.dart';

class FormResponsesContent extends StatefulWidget {
  final String formLink;
  final Future<List<FormFieldDefinition>> Function(String)? loadFields;
  final Future<ReservationsBundle> Function({
    String? occasionLink,
    String? formLink,
    bool includeOrderDetails,
    bool includeSpots,
    bool includeOrdersHistory,
  })?
  loadOrders;
  const FormResponsesContent({
    super.key,
    required this.formLink,
    this.loadFields,
    this.loadOrders,
  });

  @override
  State<FormResponsesContent> createState() => _FormResponsesContentState();
}

class _FormResponsesContentState extends State<FormResponsesContent> {
  List<FormFieldDefinition>? formFieldModels;
  String? _formLink; // Renamed to avoid confusion
  SingleDataGridController<FormResponseModel>? controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newFormLink = widget.formLink;
    if (newFormLink != _formLink) {
      _formLink = newFormLink;
      loadData();
    }
  }

  Future<void> loadData() async {
    if (_formLink == null) return;
    final link = _formLink!;
    final ff = await (widget.loadFields ?? DbForms.getAllFormFields)(link);
    if (mounted && link == _formLink) {
      setState(() {
        formFieldModels = ff;
        controller = SingleDataGridController<FormResponseModel>(
          context: context,
          loadData: () async {
            final link = _formLink!;
            final bundle =
                await (widget.loadOrders ?? DbOrders.getAllOrdersBundle)(
                  formLink: link,
                  includeOrderDetails: true,
                );
            return bundle.orders
                .where((order) => order.form?.definition.link == link)
                .map((order) => FormResponseModel.fromOrder(order, ff))
                .toList();
          },
          fromPlutoJson: (Map<String, dynamic> json) {
            return FormResponseModel.fromPlutoJson(json, formFieldModels ?? []);
          },
          firstColumnType: DataGridFirstColumn.none,
          idColumn: TbEshop.orders.id,
          actionsExtended: DataGridActionsController(
            areAllActionsEnabled: RightsService.canUpdateUsers,
            isAddActionPossible: () => false,
          ),
          headerChildren: [],
          columns: EshopColumns.generateColumns(
            context,
            columnIdentifiers,
            data: {
              EshopColumnIds.RESPONSES: formFieldModels,
              EshopColumnIds.TICKET_PRODUCTS_EXTENDED:
                  EshopColumns.productCategories,
            },
          ),
          exportOptions: ExportOptions(
            fileName: "${_formLink ?? ""}-responses",
          ),
        );
      });
    }
  }

  Future<void> refreshData() async {
    await controller?.reloadData();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleTableDataGrid<FormResponseModel>(controller!);
  }

  static List<String> columnIdentifiers = [
    EshopColumnIds.ORDER_ID,
    EshopColumnIds.ORDER_SYMBOL,
    EshopColumnIds.TICKET_PRODUCTS_EXTENDED,
    EshopColumnIds.ORDER_STATE,
    EshopColumnIds.ORDER_WAITLIST,
    EshopColumnIds.RESPONSES,
  ];
}

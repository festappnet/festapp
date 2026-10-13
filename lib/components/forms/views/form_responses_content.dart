import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import '../models/form_model.dart';
import '../waitlist_strings.dart';
import 'waitlist_offers_dialog.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/forms/models/form_response_model.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/data_services/rights_service.dart';

class FormResponsesContent extends StatefulWidget {
  final String formLink;
  const FormResponsesContent({super.key, required this.formLink});

  @override
  _FormResponsesContentState createState() => _FormResponsesContentState();
}

class _FormResponsesContentState extends State<FormResponsesContent> {
  List<FormFieldModel>? formFieldModels;
  FormModel? _capacityForm;
  List<OrderModel> _orders = [];
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
    var ff = await DbForms.getAllFormFields(_formLink!);
    if (mounted) {
      setState(() {
        formFieldModels = ff;
        controller = SingleDataGridController<FormResponseModel>(
          context: context,
          loadData: () async {
            final link = _formLink!;
            final bundle = await DbOrders.getAllOrdersBundle(formLink: link);
            if (mounted && link == _formLink) {
              setState(() {
                _capacityForm =
                    bundle.forms.where((form) => form.link == link).firstOrNull;
                _orders = bundle.orders;
              });
            }
            return DbForms.getAllResponses(link);
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
              EshopColumns.RESPONSES: formFieldModels,
              EshopColumns.TICKET_PRODUCTS_EXTENDED:
                  EshopColumns.productCategories,
            },
          ),
          exportOptions:
              ExportOptions(fileName: "${_formLink ?? ""}-responses"),
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
    return Column(children: [
      if (_capacityForm?.capacity case final capacity?)
        Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (capacity.enabled) WaitlistCapacitySummary(capacity: capacity),
              if (_capacityForm!.waitlistEnabled &&
                  RightsService.isEditorOrder())
                TextButton(
                    onPressed: () async {
                      await showDialog(
                          context: context,
                          builder: (_) => WaitlistOffersDialog(
                              form: _capacityForm!, orders: _orders));
                      await refreshData();
                    },
                    child: Text(WaitlistStrings.send)),
            ])),
      Expanded(child: SingleTableDataGrid<FormResponseModel>(controller!)),
    ]);
  }

  static List<String> columnIdentifiers = [
    EshopColumns.ORDER_ID,
    EshopColumns.ORDER_SYMBOL,
    EshopColumns.TICKET_PRODUCTS_EXTENDED,
    EshopColumns.ORDER_STATE,
    EshopColumns.ORDER_WAITLIST,
    EshopColumns.RESPONSES
  ];
}

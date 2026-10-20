import 'package:festapp_core/forms.dart';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/forms/models/form_bundle.dart';
import 'package:fstapp/components/forms/models/holder_models/form_ticket_model.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/forms/widgets_view/option_field_helper.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/models/holder_models/ticket_holder.dart';

class FormSession extends ChangeNotifier {
  final FormBundle form;
  final FormHolder formHolder;
  final GlobalKey<FormBuilderState> formKey;

  double totalPrice = 0.0;
  int totalTickets = 0;
  int totalProducts = 0;
  String? currencyCode;

  /// Visual-only meta-surcharge totals grouped by currency code. Never affect totalPrice.
  /// Empty when DepositFeature is off.
  Map<String, double> metaSurchargeSums = {};

  // Snapshot for restoring state if selection is cancelled
  List<FormTicketModel>? _ticketSnapshot;

  FormSession({
    required this.form,
    required this.formHolder,
    required this.formKey,
  });

  // Getter for UI components that need the list of currently selected seats
  List<BlueprintSeat> get currentSeats {
    final ticketHolder = formHolder.getTicket();
    if (ticketHolder == null) return [];
    return ticketHolder.tickets
        .where((t) => t.seat != null)
        .map((t) => t.seat!)
        .toList();
  }

  void startSeatSelection() {
    final ticketHolder = formHolder.getTicket();
    if (ticketHolder != null) {
      // Create a shallow copy of the list.
      // Note: FormTicketModel objects themselves are mutable, but we are primarily concerned
      // with the list composition here. If deep copy is needed, we'd need to implement it.
      // For now, assuming replacing the list reference in TicketHolder on restore is sufficient
      // Seat visual state is restored by the package controller if needed.
      // actually TicketHolder.updateTickets replaces the list.
      _ticketSnapshot = List.from(ticketHolder.tickets);
    }
  }

  void updateSeats(List<BlueprintSeat> seats) {
    final ticketHolder = formHolder.getTicket();
    if (ticketHolder != null) {
      ticketHolder.updateTickets(seats);
      recalculateTotals();
    }
  }

  void confirmSeatSelection() {
    _ticketSnapshot = null;
    recalculateTotals();
  }

  void cancelSeatSelection() {
    final ticketHolder = formHolder.getTicket();
    if (ticketHolder != null && _ticketSnapshot != null) {
      ticketHolder.tickets = _ticketSnapshot!;
      _ticketSnapshot = null;
      recalculateTotals();
    }
  }

  void recalculateTotals() {
    String? currencyC;
    totalPrice = 0.0;
    totalTickets = 0;
    totalProducts = 0;

    final bool depositOn =
        FeatureService.isFeatureEnabled(FeatureConstants.deposit);
    final Map<String, double> metaSums = {};
    void addMeta(FormOptionProductModel p) {
      if (!depositOn) return;
      final amount = p.metaSurchargeAmount;
      if (amount == null || amount == 0) return;
      // Surcharge doesn't share the product price currency by default.
      final curr = p.metaSurchargeCurrency ??
          OptionFieldHelper.defaultMetaSurchargeCurrency;
      metaSums.update(curr, (v) => v + amount, ifAbsent: () => amount);
    }

    for (var field in formHolder.fields) {
      if (field.fieldType == FormMetadata.fieldTypeProductType) {
        var selectedOption = field.getValue(formHolder.controller!.globalKey);
        if (selectedOption is FormOptionProductModel) {
          totalPrice += selectedOption.price;
          currencyC ??= selectedOption.currencyCode;
          addMeta(selectedOption);
        }
      }

      if (field is TicketHolder) {
        totalTickets = field.tickets.length;

        for (var s in field.tickets) {
          if (s.seat != null) {
            totalProducts++; // Should specific seats count as products? Original code did this.
            totalPrice += s.seat!.seat!.product!.price!;
            currencyC ??= s.seat!.seat!.product!.currencyCode;
          }
        }

        var tickets = FormHelper.getFieldData(formKey, field) ?? [];

        for (var ticketData in tickets) {
          for (var ticketField in ticketData[FormMetadata.metaFields]) {
            for (var fValue in ticketField.values) {
              if (fValue is FormOptionProductModel) {
                totalProducts++;
                totalPrice += fValue.price;
                currencyC ??= fValue.currencyCode;
                addMeta(fValue);
              } else if (fValue is Iterable) {
                var products = List<FormOptionProductModel>.from(fValue);
                totalProducts += products.length;
                totalPrice +=
                    products.fold(0, (sum, product) => sum + product.price);
                currencyC ??= products.firstOrNull?.currencyCode;
                for (final p in products) {
                  addMeta(p);
                }
              }
            }
          }
        }
      }
    }
    currencyCode = currencyC;
    metaSurchargeSums = metaSums;

    notifyListeners();
  }
}

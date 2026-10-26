import 'package:festapp_core/forms.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';

import 'field_holder.dart';

class FormTicketModel {
  int? ticketId;
  final String? blueprintAreaNodeId;
  final Map<int, FormOptionProductModel> productDefaults;
  BlueprintSeat? seat;
  final List<FieldHolder> ticketValues;
  final GlobalKey<FormBuilderState> ticketKey;

  FormTicketModel({
    required this.ticketValues,
    required this.ticketKey,
    this.seat,
    this.ticketId,
    this.blueprintAreaNodeId,
    this.productDefaults = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FormTicketModel &&
          runtimeType == other.runtimeType &&
          (seat == null || other.seat == null
              ? identical(ticketKey, other.ticketKey)
              : seat!.seat!.id! == other.seat!.seat!.id!);

  @override
  int get hashCode => seat?.seat?.id?.hashCode ?? identityHashCode(ticketKey);
}

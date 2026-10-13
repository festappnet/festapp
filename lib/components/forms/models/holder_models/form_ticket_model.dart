import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'field_holder.dart';

class FormTicketModel {
  String? participantId;
  BlueprintSeat? seat;
  final List<FieldHolder> ticketValues;
  final GlobalKey<FormBuilderState> ticketKey;

  FormTicketModel({
    required this.ticketValues,
    required this.ticketKey,
    this.seat,
    this.participantId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FormTicketModel &&
          runtimeType == other.runtimeType &&
          seat!.seat!.id! == other.seat!.seat!.id!;

  @override
  int get hashCode => seat!.seat!.id!.hashCode;
}

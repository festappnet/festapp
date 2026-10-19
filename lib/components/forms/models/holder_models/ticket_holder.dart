// lib/pages/form/models/ticket_holder.dart

import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'field_holder.dart';
import 'form_ticket_model.dart';

class TicketHolder extends FieldHolder {
  static const String metaFields = "fields";
  static const String metaTicket = "ticket";
  static const String metaMaxTickets = "max_tickets";
  static const String metaShowDepositDescription = "show_surcharge_description";

  List<FormTicketModel> tickets = [];

  int maxTickets;
  bool fixedTickets = false;
  final bool showDepositDescription;
  final List<FieldHolder> fields;
  List<OptionsFieldProductHolder> offeredProductFields = const [];

  TicketHolder({
    required super.fieldType,
    required int maxTickets,
    this.showDepositDescription = true,
    required this.fields,
    super.isRequired = true,
    required super.id,
  }) : maxTickets = maxTickets.clamp(1, AppConfig.maxTicketsPerOrder);

  @override
  Map<String, dynamic> toJson() {
    return super.toJson()
      ..addAll({
        metaFields: fields.map((e) => e.toJson()).toList(),
      });
  }

  @override
  String toString() => 'TicketHolder(fields: $fields)';

  /// Updates the tickets based on the provided list of [seats].
  void updateTickets(List<BlueprintSeat> seats) {
    // Create a map of existing tickets for fast lookup.
    final existingTicketsMap = {
      for (var ticket in tickets)
        if (ticket.seat != null) ticket.seat!.seat!.id!: ticket
    };

    // Build the new list of tickets.
    final List<FormTicketModel> updatedTickets = [];

    for (var seat in seats) {
      if (existingTicketsMap.containsKey(seat.seat!.id!)) {
        // Use the existing ticket if it matches the seat.
        updatedTickets.add(existingTicketsMap[seat.seat!.id!]!);
      } else {
        // Create a new ticket if none exists for the seat.
        updatedTickets.add(
          FormTicketModel(
            ticketValues: fields,
            ticketKey: GlobalKey<FormBuilderState>(),
            seat: seat,
          ),
        );
      }
    }

    // Replace the old tickets with the updated list.
    tickets = [
      ...tickets.where((ticket) => ticket.seat == null),
      ...updatedTickets
    ];
  }

  // Helper getter to check if any of the fields is a "spot".
  // Using string literal "spot" to avoid circular dependency with FormHelper.
  bool get hasSpot => fields.any((element) => element.fieldType == 'spot');
}

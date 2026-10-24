import 'package:fstapp/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/services/utilities_all.dart';

class TicketSearchDialog extends StatefulWidget {
  final List<TicketModel> allTickets;
  const TicketSearchDialog({super.key, required this.allTickets});

  @override
  State<TicketSearchDialog> createState() => _TicketSearchDialogState();
}

class _TicketSearchDialogState extends State<TicketSearchDialog> {
  late List<TicketModel> _filteredTickets;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredTickets = List.from(widget.allTickets);
    _searchController.addListener(_filterTickets);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterTickets);
    _searchController.dispose();
    super.dispose();
  }

  void _filterTickets() {
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _filteredTickets = List.from(widget.allTickets);
      });
    } else {
      final normalizedQuery = Utilities.removeDiacritics(query.toLowerCase());
      setState(() {
        _filteredTickets = widget.allTickets.where((ticket) {
          final symbol = Utilities.removeDiacritics(
              (ticket.ticketSymbol ?? "").toLowerCase());

          String holderName = "";
          String email = "";

          if (ticket.relatedOrder?.data != null) {
            final data = ticket.relatedOrder!.data!;
            final name = data['name'] ?? "";
            final surname = data['surname'] ?? "";
            holderName = Utilities.removeDiacritics(
                "$name $surname".trim().toLowerCase());
            email =
                Utilities.removeDiacritics((data['email'] ?? "").toLowerCase());
          }

          return Utilities.removeDiacritics(ticket.scanLabel.toLowerCase())
                  .contains(normalizedQuery) ||
              symbol.contains(normalizedQuery) ||
              holderName.contains(normalizedQuery) ||
              email.contains(normalizedQuery);
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppAlertDialog(
      onClose: () => Navigator.of(context).pop(),
      title: Text(FeaturesStrings.selectTicket),
      content: SizedBox(
        width: 300,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: OrdersStrings.searchPlaceholder,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredTickets.length,
                itemBuilder: (context, index) {
                  final ticket = _filteredTickets[index];
                  final orderData = ticket.relatedOrder?.toCustomerData() ?? "";
                  final title = [ticket.batch?['title'], ticket.ticketSymbol]
                      .whereType<String>()
                      .where((value) => value.trim().isNotEmpty)
                      .join(' · ');
                  return ListTile(
                    visualDensity: VisualDensity.compact,
                    title: Text(
                      title.isNotEmpty ? title : FeaturesStrings.unknown,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: orderData.isNotEmpty ? Text(orderData) : null,
                    onTap: () {
                      Navigator.of(context).pop(ticket);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(CommonStrings.storno),
        ),
      ],
    );
  }
}

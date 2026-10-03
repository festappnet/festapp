import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/tickets_tab.dart';

@RoutePage()
class TicketsSectionPage extends StatelessWidget {
  const TicketsSectionPage({super.key});
  @override
  Widget build(BuildContext context) => TicketsTab();
}

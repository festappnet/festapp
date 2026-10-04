import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/email_delivery/email_delivery_history.dart';
import 'package:fstapp/data_services/rights_service.dart';

@RoutePage()
class OrdersEmailHistoryPage extends StatelessWidget {
  const OrdersEmailHistoryPage({super.key});

  @override
  Widget build(BuildContext context) => EmailDeliveryHistory(
        occasionId: RightsService.currentOccasion()?.id,
        ordersOnly: true,
        embedded: true,
      );
}

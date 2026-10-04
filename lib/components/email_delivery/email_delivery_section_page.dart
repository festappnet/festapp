import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'email_delivery_history.dart';

@RoutePage()
class EmailDeliverySectionPage extends StatelessWidget {
  const EmailDeliverySectionPage({super.key});

  @override
  Widget build(BuildContext context) => EmailDeliveryHistory(
      occasionId: RightsService.currentOccasion()?.id,
      organizationId: RightsService.isAdmin() ? AppConfig.organization : null,
      embedded: true);
}

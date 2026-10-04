import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/activities/activities_content.dart';
import 'package:fstapp/data_services/rights_service.dart';

@RoutePage()
class VolunteersSectionPage extends StatelessWidget {
  const VolunteersSectionPage({super.key});
  @override
  Widget build(BuildContext context) =>
      ActivitiesContent(occasionId: RightsService.currentOccasionId()!);
}

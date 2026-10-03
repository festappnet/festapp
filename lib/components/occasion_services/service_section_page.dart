import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/occasion_services/service_tab.dart';

@RoutePage()
class ServiceSectionPage extends StatelessWidget {
  const ServiceSectionPage({super.key});
  @override
  Widget build(BuildContext context) => ServiceTab();
}

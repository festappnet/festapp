import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/views/report_tab.dart';

@RoutePage()
class ReportSectionPage extends StatelessWidget {
  const ReportSectionPage({super.key});
  @override
  Widget build(BuildContext context) => ReportTab();
}

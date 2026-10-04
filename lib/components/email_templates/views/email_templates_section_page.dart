import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/email_templates/views/email_templates_tab.dart';

@RoutePage()
class EmailTemplatesSectionPage extends StatelessWidget {
  const EmailTemplatesSectionPage({super.key});
  @override
  Widget build(BuildContext context) => EmailTemplatesTab();
}

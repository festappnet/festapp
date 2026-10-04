import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/blueprint/views/blueprint_editor_tab.dart';

@RoutePage()
class BlueprintSectionPage extends StatelessWidget {
  const BlueprintSectionPage({super.key});
  @override
  Widget build(BuildContext context) => BlueprintTab();
}

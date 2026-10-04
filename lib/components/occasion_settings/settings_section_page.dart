import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_tab.dart';

@RoutePage()
class SettingsSectionPage extends StatelessWidget {
  const SettingsSectionPage({super.key});
  @override
  Widget build(BuildContext context) => OccasionSettingsTab();
}

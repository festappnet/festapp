import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/speakers/admin/speakers_tab.dart';

@RoutePage()
class SpeakersSectionPage extends StatelessWidget {
  const SpeakersSectionPage({super.key});
  @override
  Widget build(BuildContext context) => const SpeakersTab();
}

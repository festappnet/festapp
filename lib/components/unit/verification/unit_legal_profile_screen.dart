import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'package:fstapp/components/unit/views/unit_admin_page.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'unit_legal_profile_section.dart';
import 'verification_strings.dart';

@RoutePage(name: 'UnitLegalProfileRoute')
class UnitLegalProfilePage extends StatelessWidget {
  const UnitLegalProfilePage({super.key});

  Future<void> _pop(BuildContext context) async {
    final router = context.router;
    if (!await router.maybePop() && context.mounted) {
      await router.replaceAll([const UnitSettingsContentRoute()]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = UnitAdministrationScope.of(context);
    return ListenableBuilder(
      listenable: RightsService.occasionLinkModelNotifier,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(VerificationStrings.text('title')),
          leading: BackButton(
              onPressed: () =>
                  RetainedDraftGuard.instance.leaveOwner(context, () async {
                    await WidgetsBinding.instance.endOfFrame;
                    if (context.mounted) await _pop(context);
                  })),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                child: UnitLegalProfileSection(
                  key: ValueKey(scope.unit.id),
                  unitId: scope.unit.id!,
                  canEdit: RightsService.hasCapability(
                      AuthorizationCapabilities.unitLegalProfileWrite),
                  onBack: () => _pop(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:fstapp/components/unit/unit_creation_helper.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/occasion/demo/demo_occasion_strings.dart';
import 'package:fstapp/components/occasion/occasion_copy_dialog.dart';
import 'package:fstapp/components/unit/db_units.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/components/unit/unit_strings.dart';
import 'package:uuid/uuid.dart';
import 'demo_occasion_navigation.dart';

/// Float over the full page while keeping nested footer controls visible.
class DemoOccasionOverlay extends StatelessWidget {
  final Widget child;
  const DemoOccasionOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        child,
        const Positioned(
            left: 0, right: 0, bottom: 64, child: DemoOccasionBanner()),
      ]);
}

class DemoOccasionBanner extends StatefulWidget {
  const DemoOccasionBanner({super.key});
  @override
  State<DemoOccasionBanner> createState() => _DemoOccasionBannerState();
}

class _DemoOccasionBannerState extends State<DemoOccasionBanner> {
  bool _busy = false;
  int? _source;
  String? _command;
  UnitModel? _target;
  Future<void> _copy() async {
    if (_busy) return;
    final source = RightsService.currentOccasionId();
    if (source == null || !RightsService.isDemoReadOnly) return;
    setState(() => _busy = true);
    try {
      if (_source != source) {
        _source = source;
        _target = null;
        _command = null;
      }
      if (_target == null) {
        var targets = await DbUnits.getOccasionCopyUnits(source);
        if (!mounted) return;
        if (targets.isEmpty &&
            RightsService
                    .occasionLinkModel?.organization?.isUnitCreationEnabled ==
                true) {
          final unit = await UnitCreationHelper.createNewUnit(context);
          if (unit == null || !mounted) return;
          targets = await DbUnits.getOccasionCopyUnits(source);
          if (!mounted) return;
        }
        if (targets.isEmpty) {
          ToastHelper.Show(context, DemoOccasionStrings.noTarget);
          return;
        }
        _target = await showOccasionCopyTargetDialog(context, targets,
            hint: DemoOccasionStrings.copyHint);
        if (_target == null || !mounted) return;
        _command = const Uuid().v4();
      }
      final result = await DbOccasions.duplicateDemoOccasion(source,
          targetUnitId: _target!.id!, commandId: _command!);
      if (!mounted) return;
      if (!result.mediaCopied)
        ToastHelper.Show(context, UnitStrings.createCopyMediaFailed);
      final copy = await DbOccasions.getOccasion(result.occasionId);
      if (!mounted) return;
      ToastHelper.Show(context, DemoOccasionStrings.copyHint);
      await RouterService.navigate(
          context, '/${copy.link}/reservations/settings');
    } catch (_) {
      if (mounted) ToastHelper.Show(context, UnitStrings.createCopyFailed);
      // The same target and command survive a timeout; Retry replays its receipt.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Align(
              heightFactor: 1,
              alignment: Alignment.bottomCenter,
              child: Material(
                  elevation: 8,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  color: Theme.of(context).cardColor,
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton.icon(
                                onPressed: () =>
                                    DemoOccasionNavigation.back(context),
                                icon: const Icon(Icons.arrow_back),
                                label: Text(DemoOccasionStrings.back)),
                            Text(DemoOccasionStrings.readOnly),
                            FilledButton(
                                onPressed: _busy ? null : _copy,
                                child: _busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : Text(DemoOccasionStrings.copy))
                          ]))))));
}

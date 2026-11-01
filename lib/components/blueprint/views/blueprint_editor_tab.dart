import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../_shared/common_strings.dart';
import '../../forms/db_forms.dart';
import '../blueprint_model.dart';
import '../blueprint_strings.dart';
import '../seating_transition_models.dart';
import '../seating_transition_transport.dart';
import '../seating_transition_strings.dart';
import 'blueprint_layout_host.dart';

/// Multiple saved plans require an explicit target; a reload retains that target.
class BlueprintTab extends StatefulWidget {
  const BlueprintTab({super.key});
  @override
  State<BlueprintTab> createState() => _BlueprintTabState();
}

class _BlueprintTabState extends State<BlueprintTab> {
  BlueprintModel? _source;
  String? _occasionLink;
  int? _blueprintId;
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final params = context.routeData.inheritedPathParams;
    if (params.isEmpty) return;
    final link = params.getString(AppRouter.linkFormatted);
    if (link == _occasionLink) return;
    _occasionLink = link;
    _blueprintId = null;
    _plans = [];
    _load();
  }

  Future<void> _load() async {
    final link = _occasionLink;
    if (link == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _source = null;
    });
    BlueprintModel? source;
    try {
      final occasion = RightsService.currentOccasionId();
      if (occasion != null) {
        final workspace = await SeatingTransitionTransport(
          Supabase.instance.client,
        ).workspace(occasion, _blueprintId);
        _plans = seatingRows(workspace['plans']);
        if (_blueprintId == null && _plans.length == 1)
          _blueprintId = seatingInt(_plans.single['id']);
        if (_blueprintId == null && _plans.length > 1) {
          if (mounted && generation == _generation)
            setState(() => _loading = false);
          return;
        }
      }
      source = await DbForms.getBlueprintForEdit(
        link,
        blueprintId: _blueprintId,
      );
      if (source?.layoutSnapshot == null) source = null;
      if (source != null) _blueprintId = source.id;
    } catch (_) {
      /* Explicit retry keeps the target, including repair failures. */
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _source = source;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final source = _source;
    if (source != null) {
      return BlueprintLayoutHost(
        key: ValueKey(source.id),
        source: source,
        reload: () =>
            DbForms.getBlueprintForEdit(_occasionLink!, blueprintId: source.id),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _plans.length > 1
                  ? SeatingTransitionStrings.text('choosePlan')
                  : BlueprintStrings.layoutUnavailable,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final plan in _plans)
              ListTile(
                title: Text(plan['title']?.toString() ?? '#${plan['id']}'),
                subtitle: plan['valid'] == true
                    ? null
                    : Text(SeatingTransitionStrings.text('repairPlan')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  _blueprintId = seatingInt(plan['id']);
                  _load();
                },
              ),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(CommonStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}

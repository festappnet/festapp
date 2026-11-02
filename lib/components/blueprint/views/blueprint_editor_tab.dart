import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../_shared/common_strings.dart';
import '../../forms/db_forms.dart';
import '../../forms/views/reservation_page.dart';
import '../../navigation/navigation_paths.dart';
import '../../navigation/route_visibility.dart';
import '../blueprint_model.dart';
import '../blueprint_focus_target.dart';
import '../blueprint_strings.dart';
import '../seating_transition_models.dart';
import '../seating_transition_transport.dart';
import '../seating_transition_strings.dart';
import 'blueprint_layout_host.dart';

/// Tracks only this mounted occasion's visible main Blueprint route. A new
/// visit is a new focus intent even when the query matches the previous visit.
class BlueprintRouteFocusState {
  bool active = false;
  BlueprintFocusTarget? target;
  bool invalidPlan = false;
  (String, String?, String?)? _last;

  bool observe(Uri uri, {required String occasionLink, required bool visible}) {
    final path = uri.pathSegments;
    final scoped =
        visible &&
        path.length == 3 &&
        path[0] == occasionLink &&
        path[1] == ReservationsPage.ROUTE &&
        path[2] == NavigationPaths.blueprint;
    if (!scoped) {
      final changed = active;
      active = false;
      target = null;
      invalidPlan = false;
      _last = null;
      return changed;
    }
    final query = uri.queryParameters;
    final key = (occasionLink, query['blueprintId'], query['blueprintNodeId']);
    if (active && key == _last) return false;
    active = true;
    _last = key;
    target = BlueprintFocusTarget.fromQuery(query);
    invalidPlan = query.containsKey('blueprintId') && target == null;
    return true;
  }
}

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
  StackRouter? _router;
  BlueprintFocusTarget? _focusTarget;
  final _routeFocus = BlueprintRouteFocusState();
  int _focusRevision = 0;
  bool _invalidPlan = false;

  void _routeChanged() {
    if (!mounted || _occasionLink == null || _router == null) return;
    final uri = _router!.urlState.uri;
    final changed = _routeFocus.observe(
      uri,
      occasionLink: _occasionLink!,
      visible: isVisibleRouteInstance(context),
    );
    if (!changed) return;
    if (!_routeFocus.active) {
      // Leaving cancels old reads, but same-occasion navigation retains its plan.
      _generation++;
      _focusTarget = null;
      if (uri.pathSegments.firstOrNull != _occasionLink) {
        _source = null;
        _plans = [];
        _blueprintId = null;
        _loading = true;
      }
      setState(() {});
      return;
    }
    final target = _routeFocus.target;
    final recoverDefault = _invalidPlan && !_routeFocus.invalidPlan;
    final changedPlan = target != null && target.blueprintId != _blueprintId;
    _focusTarget = target;
    _invalidPlan = _routeFocus.invalidPlan;
    _focusRevision++;
    if (changedPlan || _invalidPlan || recoverDefault || _source == null) {
      if (changedPlan || _invalidPlan || recoverDefault)
        _blueprintId = target?.blueprintId;
      _load();
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _generation++;
    _router?.removeListener(_routeChanged);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final root = context.router.root;
    if (_router != root) {
      _router?.removeListener(_routeChanged);
      _router = root;
      root.addListener(_routeChanged);
    }
    final params = context.routeData.inheritedPathParams;
    if (params.isEmpty) return;
    final link = params.getString(AppRouter.linkFormatted);
    if (link != _occasionLink) {
      _generation++;
      _occasionLink = link;
      _focusTarget = null;
      _blueprintId = null;
      _source = null;
      _plans = [];
      _loading = true;
    }
    _routeChanged();
  }

  Future<void> _load() async {
    final link = _occasionLink;
    if (link == null || !_routeFocus.active) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _source = null;
      _plans = [];
    });
    BlueprintModel? source;
    var planId = _blueprintId;
    try {
      if (_invalidPlan) throw StateError('Invalid blueprint target');
      final occasion = RightsService.currentOccasionId();
      if (occasion == null) throw StateError('Missing occasion');
      final workspace = await SeatingTransitionTransport(
        Supabase.instance.client,
      ).workspace(occasion, planId);
      if (!mounted ||
          generation != _generation ||
          occasion != RightsService.currentOccasionId())
        return;
      final plans = seatingRows(workspace['plans']);
      _plans = plans;
      if (planId != null &&
          !plans.any((plan) => seatingInt(plan['id']) == planId)) {
        throw StateError('Blueprint outside occasion');
      }
      if (planId == null && plans.length == 1)
        planId = seatingInt(plans.single['id']);
      if (planId == null && plans.length > 1) {
        setState(() => _loading = false);
        return;
      }
      source = await DbForms.getBlueprintForEdit(link, blueprintId: planId);
      if (!mounted ||
          generation != _generation ||
          occasion != RightsService.currentOccasionId())
        return;
      if (source?.layoutSnapshot == null ||
          (planId != null && source?.id != planId))
        source = null;
      if (source != null) _blueprintId = source.id;
    } catch (_) {
      // A superseded request must not clear the current request's plan list.
      if (!mounted || generation != _generation) return;
      _plans = [];
      // Explicit retry keeps the requested target; never fall back to another plan.
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
        focusNodeId: _focusTarget?.nodeFor(
          source.id,
          source.layoutSnapshot!.document,
        ),
        focusRevision: _focusRevision,
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
                  _focusTarget = null;
                  _invalidPlan = false;
                  _focusRevision++;
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

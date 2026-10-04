import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/html/html_strings.dart';

/// A retained editor registers its existing discard prompt at its identity boundary.
/// Switching retained tabs keeps drafts; replacing their owner asks before routing.
class RetainedDraftGuard extends AutoRouteGuard {
  static final instance = RetainedDraftGuard();
  final Set<_NavigationDraftBoundaryState> _drafts = {};
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) async {
    final target = <RouteMatch>[
      ...router.routeData.breadcrumbs,
      ..._flatten(resolver.route),
    ];
    for (final draft in _drafts.toList()) {
      if (!draft.mounted || draft._approved || !draft.widget.isDirty())
        continue;
      final owner = draft._owner;
      if (owner == null) continue;
      // Last occurrence wins when a stack replaces an existing object's route.
      final candidates =
          target.where((match) => match.name == owner.name).toList();
      final destination = candidates.isEmpty ? null : candidates.last;
      final currentParams = owner.inheritedPathParams.rawMap;
      final targetParams = <String, dynamic>{
        for (final match in target) ...match.params.rawMap
      };
      final sameOwner = destination != null &&
          currentParams.entries
              .every((entry) => targetParams[entry.key] == entry.value);
      if (sameOwner) continue;
      if (!await draft._confirm()) {
        resolver.next(false);
        return;
      }
    }
    resolver.next();
  }

  /// Preflight replacements, whose AutoRoute implementation removes pages
  /// before evaluating guards. Browser deep links use this same boundary.
  Future<bool> confirmPath(StackRouter root, Uri target) async {
    final matches = root.matcher.matchUri(target, includePrefixMatches: false);
    final routes = matches == null
        ? <RouteMatch>[]
        : [for (final route in matches) ..._flatten(route)];
    final params = <String, dynamic>{
      for (final route in routes) ...route.params.rawMap
    };
    final names = routes.map((route) => route.name).toSet();
    final approved = <_NavigationDraftBoundaryState>[];
    for (final draft in _drafts.toList()) {
      if (!draft.mounted || !draft.widget.isDirty() || draft._approved)
        continue;
      final owner = draft._owner;
      if (owner == null) continue;
      final sameParams = owner.inheritedPathParams.rawMap.entries
          .every((entry) => params[entry.key] == entry.value);
      if (sameParams &&
          names.contains(owner.name) &&
          !names.contains('NavigationNotFoundRoute')) continue;
      // Switching another retained top tab keeps this object's nested stack.
      final objectNavigation = switch (owner.name) {
        'FormDetailRoute' => 'FormsNavigationRoute',
        'InventoryPoolDetailRoute' => 'InventoryPoolsNavigationRoute',
        'BankAccountDetailRoute' => 'UnitBankAccountsNavigationRoute',
        _ => null,
      };
      if (objectNavigation != null && !names.contains(objectNavigation)) {
        final parent = _ancestors(owner)
            .where((data) => const {
                  'AdminRoute',
                  'ReservationsRoute',
                  'UnitAdminRoute'
                }.contains(data.name))
            .first;
        if (!names.contains('NavigationNotFoundRoute') &&
            names.contains(parent.name) &&
            parent.inheritedPathParams.rawMap.entries
                .every((entry) => params[entry.key] == entry.value)) continue;
      }
      if (!await draft._confirm()) {
        for (final previous in approved) {
          previous._approved = false;
        }
        return false;
      }
      draft._approveForNavigation();
      approved.add(draft);
    }
    return true;
  }

  Future<void> leaveOwner(
      BuildContext context, Future<void> Function() action) async {
    final owners =
        context.routeData.breadcrumbs.map((route) => route.name).toSet();
    final approved = <_NavigationDraftBoundaryState>[];
    for (final draft in _drafts.toList()) {
      if (draft.mounted &&
          owners.contains(draft._owner?.name) &&
          draft.widget.isDirty()) {
        if (!await draft._confirm()) {
          for (final previous in approved) {
            previous._approved = false;
          }
          return;
        }
        draft._approveForNavigation();
        approved.add(draft);
      }
    }
    if (context.mounted) await action();
  }

  static Iterable<RouteData> _ancestors(RouteData data) sync* {
    RouteData? current = data;
    while (current != null) {
      yield current;
      current = current.parent;
    }
  }

  static Iterable<RouteMatch> _flatten(RouteMatch route) sync* {
    yield route;
    for (final child in route.children ?? <RouteMatch>[]) {
      yield* _flatten(child);
    }
  }
}

class NavigationDraftBoundary extends StatefulWidget {
  final bool Function() isDirty;
  final Future<bool> Function()? confirm;
  final Widget child;
  const NavigationDraftBoundary(
      {super.key, required this.isDirty, this.confirm, required this.child});
  @override
  State<NavigationDraftBoundary> createState() =>
      _NavigationDraftBoundaryState();
}

class _NavigationDraftBoundaryState extends State<NavigationDraftBoundary> {
  RouteData? _owner;
  bool _approved = false;
  void _approveForNavigation() {
    _approved = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _approved = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data =
        context.findAncestorWidgetOfExactType<RouteDataScope>()?.routeData;
    if (data == null) return;
    // Object owner first; otherwise the containing occasion/unit administration.
    final owners = RetainedDraftGuard._ancestors(data).where((route) => const {
          'FormDetailRoute',
          'InventoryPoolDetailRoute',
          'BankAccountDetailRoute',
          'AdminRoute',
          'ReservationsRoute',
          'UnitAdminRoute'
        }.contains(route.name));
    _owner = owners.isEmpty ? null : owners.first;
    RetainedDraftGuard.instance._drafts.add(this);
  }

  Future<bool> _confirm() async {
    if (!widget.isDirty()) return true;
    if (widget.confirm != null) return widget.confirm!();
    return await showDialog<bool>(
            context: context,
            builder: (context) =>
                AlertDialog(title: Text(HtmlStrings.discardDraft), actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(CommonStrings.storno)),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(CommonStrings.ok)),
                ])) ==
        true;
  }

  @override
  void dispose() {
    RetainedDraftGuard.instance._drafts.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

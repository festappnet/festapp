import 'package:fstapp/widgets/app_dialog.dart';
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
      if (_leavesOccasion(owner, target)) continue;
      if (_preservesOwner(owner, target)) continue;
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
    final approved = <_NavigationDraftBoundaryState>[];
    for (final draft in _drafts.toList()) {
      if (!draft.mounted || !draft.widget.isDirty() || draft._approved)
        continue;
      final owner = draft._owner;
      if (owner == null) continue;
      if (_leavesOccasion(owner, routes)) continue;
      if (_preservesOwner(owner, routes)) continue;
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

  // Drafts belong to one occasion. Its administration boundary disposes
  // editors when that occasion leaves the active root route.
  static bool _leavesOccasion(RouteData owner, Iterable<RouteMatch> routes) {
    final occasions = _ancestors(owner).where((route) =>
        const {'AdminRoute', 'ReservationsRoute'}.contains(route.name));
    if (occasions.isEmpty) return false; // Unit editors retain their own guard.
    final occasion = occasions.first;
    final params = <String, dynamic>{
      for (final route in routes) ...route.params.rawMap
    };
    return !routes.any((route) => route.name == occasion.name) ||
        !occasion.inheritedPathParams.rawMap.entries
            .every((entry) => params[entry.key] == entry.value);
  }

  /// Guard callbacks and URL preflight must agree about retained tab owners.
  /// Another tab inside the same administration keeps this object's stack alive.
  static bool _preservesOwner(RouteData owner, Iterable<RouteMatch> routes) {
    final names = routes.map((route) => route.name).toSet();
    if (names.contains('NavigationNotFoundRoute')) return false;
    // Later matches override parameters from the existing stack breadcrumbs.
    final params = <String, dynamic>{
      for (final route in routes) ...route.params.rawMap
    };
    bool sameIdentity(RouteData route) =>
        route.inheritedPathParams.rawMap.entries
            .every((entry) => params[entry.key] == entry.value);
    if (names.contains(owner.name) && sameIdentity(owner)) return true;
    final objectNavigation = switch (owner.name) {
      'FormDetailRoute' => 'FormsNavigationRoute',
      'InventoryPoolDetailRoute' => 'InventoryPoolsNavigationRoute',
      'BankAccountDetailRoute' => 'UnitBankAccountsNavigationRoute',
      _ => null,
    };
    if (objectNavigation == null || names.contains(objectNavigation))
      return false;
    for (final parent in _ancestors(owner)) {
      if (const {'AdminRoute', 'ReservationsRoute', 'UnitAdminRoute'}
          .contains(parent.name)) {
        return names.contains(parent.name) && sameIdentity(parent);
      }
    }
    return false;
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
          'BankAccountConnectionSettingsRoute',
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
            builder: (context) => AppAlertDialog(
                    onClose: () => Navigator.pop(context, false),
                    title: Text(HtmlStrings.discardDraft),
                    actions: [
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

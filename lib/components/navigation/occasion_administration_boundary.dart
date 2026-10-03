import 'package:fstapp/components/navigation/route_visibility.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/rights_service.dart';

/// The context/access seam keeps routed presentation independent of data loading.
abstract interface class AdministrationAccess {
  bool get isSignedIn;
  String? get loadedLink;
  Listenable get changes;
  bool canAccess({required bool reservations});
  Future<bool> load(String link, {required bool reservations});
}

class RightsAdministrationAccess implements AdministrationAccess {
  const RightsAdministrationAccess();
  @override
  bool get isSignedIn => AuthService.isLoggedIn();
  @override
  String? get loadedLink => RightsService.currentLink;
  @override
  Listenable get changes => RightsService.occasionLinkModelNotifier;
  @override
  bool canAccess({required bool reservations}) =>
      isSignedIn &&
      (reservations
          ? RightsService.canSeeReservations()
          : RightsService.canSeeAdministration());
  @override
  Future<bool> load(String link, {required bool reservations}) async {
    await RightsService.updateAppData(link: link, refreshOffline: false);
    return loadedLink == link && canAccess(reservations: reservations);
  }
}

class OccasionAdministrationBoundary extends StatefulWidget {
  final bool reservations;
  final WidgetBuilder builder;
  final AdministrationAccess access;
  const OccasionAdministrationBoundary(
      {super.key,
      required this.builder,
      this.reservations = false,
      this.access = const RightsAdministrationAccess()});
  @override
  State<OccasionAdministrationBoundary> createState() =>
      _OccasionAdministrationBoundaryState();
}

class _OccasionAdministrationBoundaryState
    extends State<OccasionAdministrationBoundary> {
  String? _link;
  StackRouter? _root;
  int _generation = 0;
  bool _ready = false;
  bool _denied = false;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    widget.access.changes.addListener(_contextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.of(
        context); // Reload retained context when native Back reveals it.
    context.dependOnInheritedWidgetOfExactType<RouteDataScope>();
    final root = context.router.root;
    if (_root != root) {
      _root?.removeListener(_contextChanged);
      _root = root;
      root.addListener(_contextChanged);
    }
    final link = context.routeData.inheritedPathParams
        .getString(AppRouter.linkFormatted);
    if (_link == link) {
      _contextChanged();
      return;
    }
    _link = link;
    _ready = false;
    _denied = false;
    _load(link, ++_generation);
  }

  void _contextChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _link == null || !isVisibleRouteInstance(context)) return;
      if (widget.access.loadedLink == _link &&
          !widget.access.canAccess(reservations: widget.reservations)) {
        if (!_denied)
          setState(() {
            _denied = true;
          });
        return;
      }
      if (widget.access.loadedLink != _link || (!_ready && !_loading)) {
        if (!_loading && isVisibleRouteInstance(context))
          _load(_link!, ++_generation);
      } else if (_ready && _denied) {
        setState(() => _denied = false);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _load(String link, int generation) async {
    _loading = true;
    if (!widget.access.isSignedIn) {
      final intended = _root!.urlState.uri.toString();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation)
          _root!.replace(LoginRoute(redirect: intended));
      });
      _loading = false;
      return;
    }
    try {
      final allowed =
          await widget.access.load(link, reservations: widget.reservations);
      if (!mounted || generation != _generation) return;
      setState(() {
        _ready = allowed && widget.access.loadedLink == link;
        _denied = !_ready;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _denied = true);
    } finally {
      if (generation == _generation) _loading = false;
    }
  }

  @override
  void dispose() {
    ++_generation;
    widget.access.changes.removeListener(_contextChanged);
    _root?.removeListener(_contextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_denied && !_ready)
      return const Scaffold(body: Center(child: Text('Access denied')));
    if (!_ready)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final waiting = widget.access.loadedLink != _link;
    // Previously authorized retained editors stay mounted behind the denial
    // screen. Initial denial never creates them; restored access keeps the same
    // native nested route stack and unsaved draft.
    return Stack(fit: StackFit.expand, children: [
      Offstage(
          offstage: _denied || waiting,
          child: TickerMode(
              enabled: !_denied && !waiting,
              child: KeyedSubtree(
                  key: ValueKey(_link), child: widget.builder(context)))),
      if (waiting)
        const Scaffold(body: Center(child: CircularProgressIndicator()))
      else if (_denied)
        const Scaffold(body: Center(child: Text('Access denied'))),
    ]);
  }
}

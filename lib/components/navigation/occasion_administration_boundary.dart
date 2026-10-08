import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/last_administration_context.dart';
import 'package:fstapp/components/navigation/route_visibility.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
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
    final allowed = loadedLink == link && canAccess(reservations: reservations);
    if (allowed) {
      await LastAdministrationContext.instance.remember(
          AppConfig.organization,
          RightsService.currentUser()?.id,
          '/$link/${reservations ? 'reservations' : 'admin'}');
    }
    return allowed;
  }
}

class OccasionAdministrationBoundary extends StatefulWidget {
  final bool reservations;
  final WidgetBuilder builder;
  final WidgetBuilder? loadingBuilder;
  final AdministrationAccess access;
  const OccasionAdministrationBoundary(
      {super.key,
      required this.builder,
      this.loadingBuilder,
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
  bool _loadFailed = false;
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
      if (!mounted ||
          _link == null ||
          _loadFailed ||
          !isVisibleRouteInstance(context)) return;
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
    _loadFailed = false;
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
        final ready = allowed && widget.access.loadedLink == link;
        _ready = _ready || ready;
        _denied = !ready;
        _loadFailed = !ready;
      });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() {
          _denied = true;
          _loadFailed = true;
        });
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
    final failure = Scaffold(
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Access denied'),
      TextButton(
          onPressed: () {
            if (!_loading) _load(_link!, ++_generation);
          },
          child: Text(CommonStrings.retry)),
    ])));
    if (_denied && !_ready) return failure;
    final loading = widget.loadingBuilder?.call(context) ??
        const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_ready) return loading;
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
      if (_denied)
        failure
      else if (waiting)
        loading,
    ]);
  }
}

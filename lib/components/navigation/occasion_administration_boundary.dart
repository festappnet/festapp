import 'package:fstapp/services/public_link_path.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/last_administration_context.dart';
import 'package:fstapp/components/navigation/route_visibility.dart';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
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
          ? RightsService.canAccessReservationsWorkspace()
          : RightsService.canSeeAdministration());
  @override
  Future<bool> load(String link, {required bool reservations}) async {
    final pending = RightsService.pendingContextUpdate;
    if (pending != null) {
      await pending;
      if (loadedLink == link) return canAccess(reservations: reservations);
    }
    if (loadedLink == link && canAccess(reservations: reservations))
      return true;
    // A denied/failed refresh leaves this link selected with invalidated
    // capabilities. Retry must ask SQL again, rather than cache that denial.
    await RightsService.updateAppData(
      link: link,
      force: loadedLink == link,
      refreshOffline: false,
    );
    final allowed = loadedLink != null && canAccess(reservations: reservations);
    if (allowed) {
      await LastAdministrationContext.instance.remember(
        AppConfig.organization,
        RightsService.currentUser()?.id,
        '/$loadedLink/${reservations ? 'reservations' : 'admin'}',
      );
    }
    return allowed;
  }
}

class OccasionAdministrationBoundary extends StatefulWidget {
  final bool reservations;
  final WidgetBuilder builder;
  final WidgetBuilder? loadingBuilder;
  final AdministrationAccess access;
  const OccasionAdministrationBoundary({
    super.key,
    required this.builder,
    this.loadingBuilder,
    this.reservations = false,
    this.access = const RightsAdministrationAccess(),
  });
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
  bool _inactive = false;
  bool _denied = false;
  bool _loading = false;
  bool _loadFailed = false;
  bool _loadErrored = false;
  @override
  void initState() {
    super.initState();
    widget.access.changes.addListener(_contextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ModalRoute.of(
      context,
    ); // Reload retained context when native Back reveals it.
    context.dependOnInheritedWidgetOfExactType<RouteDataScope>();
    final root = context.router.root;
    if (_root != root) {
      _root?.removeListener(_contextChanged);
      _root = root;
      root.addListener(_contextChanged);
    }
    final link = context.routeData.inheritedPathParams.getString(
      AppRouter.linkFormatted,
    );
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
      if (!mounted || _link == null) return;
      if (!isVisibleRouteInstance(context)) {
        if (!_inactive) {
          // Preserve the active route for Back, but never the editor state.
          final data = context.routeData;
          final nested = context.router.innerRouterOf<RoutingController>(
            data.name,
          );
          final segments = nested?.currentSegments ?? <RouteMatch>[];
          RouteMatch? restored;
          for (final segment in segments.reversed) {
            restored = segment.copyWith(
              children: restored == null ? null : [restored],
            );
          }
          if (restored != null) {
            data.pendingChildren
              ..clear()
              ..add(restored);
          }
          setState(() {
            _inactive = true;
            ++_generation;
            _ready = false;
            _loading = false;
            _denied = false;
            _loadFailed = false;
          });
        }
        return;
      }
      if (_inactive) setState(() => _inactive = false);
      if (_loadFailed) {
        if (widget.access.loadedLink != _link ||
            !widget.access.canAccess(reservations: widget.reservations))
          return;
        setState(() {
          _loadFailed = false;
          _loadErrored = false;
          _denied = false;
        });
      }
      if (widget.access.loadedLink == _link &&
          !widget.access.canAccess(reservations: widget.reservations)) {
        if (!_loading) {
          setState(() => _denied = true);
          _load(_link!, ++_generation);
        }
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
    _loadErrored = false;
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
      final allowed = await widget.access.load(
        link,
        reservations: widget.reservations,
      );
      if (!mounted || generation != _generation) return;
      final canonical = widget.access.loadedLink;
      if (allowed && canonical != null && canonical != link) {
        final current = _root!.urlState.uri.toString();
        final target = canonicalPublicPath(
          current,
          'occasion',
          link,
          canonical,
        );
        if (target != current) {
          final matches = _root!.matcher.match(
            target,
            includePrefixMatches: false,
          );
          if (matches != null) {
            _root!.markUrlStateForReplace();
            await _root!.navigateAll(matches);
          }
        }
        return;
      }

      setState(() {
        final ready = allowed && widget.access.loadedLink == link;
        _ready = _ready || ready;
        _denied = !ready;
        _loadFailed = !ready;
      });
    } catch (error) {
      if (mounted && generation == _generation)
        setState(() {
          _denied = true;
          _loadFailed = true;
          _loadErrored = error is! ContextAccessDenied;
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
    // Do not retain drafts on a hidden root occasion, including native Back.
    if (_inactive) return const SizedBox.shrink();
    final failure = Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _loadErrored ? CommonStrings.contextLoadFailed : 'Access denied',
            ),
            TextButton(
              onPressed: () {
                if (!_loading) _load(_link!, ++_generation);
              },
              child: Text(CommonStrings.retry),
            ),
          ],
        ),
      ),
    );
    final loading =
        widget.loadingBuilder?.call(context) ??
        const Scaffold(body: SizedBox.expand());
    if (!_ready)
      return _loading
          ? loading
          : _denied
          ? failure
          : loading;
    final waiting = _loading || widget.access.loadedLink != _link;
    // Previously authorized retained editors stay mounted behind the denial
    // screen. Initial denial never creates them; restored access keeps the same
    // native nested route stack and unsaved draft.
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: _denied || waiting,
          child: TickerMode(
            enabled: !_denied && !waiting,
            child: KeyedSubtree(
              key: ValueKey(_link),
              child: widget.builder(context),
            ),
          ),
        ),
        if (waiting) loading else if (_denied) failure,
      ],
    );
  }
}

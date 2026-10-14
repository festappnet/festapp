import 'package:fstapp/services/last_administration_context.dart';
import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'package:fstapp/components/navigation/root_route_navigation.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/forms/views/reservation_page.dart';
import 'package:fstapp/components/occasion/admin_page.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/js/js_interop.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'dart:async';

import 'package:fstapp/components/forms/views/form_page.dart';
import 'package:fstapp/components/schedule/event_page.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/link_model.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/feature_constants.dart';

class RouterService {
  static const link = "link";
  static const subpage = "subpage";
  static const linkPath = "/:$link";
  static String currentOccasionLink = "";

  //todo temporary fix
  static String getCurrentLink() => currentOccasionLink.isNotEmpty
      ? "/$currentOccasionLink/"
      : "/offlineOccasion/"; //to avoid offline errors

  static Future<T?> navigatePageInfo<T extends Object?>(
      BuildContext context, PageRouteInfo route) {
    return context.router.push(route);
  }

  static Future<T?> navigateOccasion<T extends Object?>(
      BuildContext context, String path) {
    return pushRootPath<T>(context.router.root, getCurrentLink() + path);
  }

  static Future<T?> navigateOccasionNoContext<T extends Object?>(String path) {
    return pushRootPath<T>(router, getCurrentLink() + path);
  }

  static Future<T?> changeOnOccasion<T extends Object?>(
      BuildContext context, String path,
      {Object? extra}) {
    return context.router.push(
      PageRouteInfo<void>(getCurrentLink() + path, args: extra),
    );
  }

  static Future<T?> navigate<T extends Object?>(
      BuildContext context, String path) {
    if (path.isEmpty) return Future.value(null);

    // Clean the path if it's a full URL
    path = normalizeUrl(path);

    path = fixPath(path);

    if (kIsWeb && AppConfig.isWebclientSupported) {
      // List of paths that should be handled by the web client
      // This can be expanded. For now, we know 'form' is one.
      // Check against list of known web-client routes
      if (path.startsWith("/${FormPage.ROUTE}/")) {
        unawaited(LaunchUrlService.openExternalUrl(
          path,
          inCurrentWindow: true,
        ));
        return Future.value(null);
      }
    }

    return pushRootPath<T>(context.router.root, path);
  }

  static String fixPath(String path) {
    if (!path.startsWith("/")) {
      path = "/$path";
    }
    return path;
  }

  static String normalizeUrl(String url) {
    String path = url;

    // 1. Determine base to strip (Configured URL or dynamic localhost origin)
    final matchedBase = AppConfig.compatibleUrls().firstWhere(
      (u) => u.isNotEmpty && url.startsWith(u),
      orElse: () => "",
    );

    if (matchedBase.isNotEmpty) {
      path = url.substring(matchedBase.length);
    } else if (url.contains("localhost")) {
      final uri = Uri.tryParse(url);
      if (uri != null && url.startsWith(uri.origin)) {
        path = url.substring(uri.origin.length);
      }
    }

    // 2. Remove specific legacy hash "/#" only if it immediately follows the domain
    // Examples:
    // domain.com/#/path -> /path
    // domain.com/path -> /path
    if (path.startsWith('/#')) {
      path = path.replaceFirst('/#', '');
    }

    // 3. Remove leading slash to get cleaner path, but fixPath adds it back if needed.
    // We'll let fixPath handle the leading slash requirement.

    return path;
  }

  static Future<void> pushReplacementFull<T extends Object?>(
      BuildContext context, String path) async {
    path = fixPath(path);
    await replaceRootPath(context.router.root, path);
  }

  static void pushReplacementOccasion<T extends Object?>(
      BuildContext context, String path) {
    replaceRootPath(context.router.root, getCurrentLink() + path);
  }

  static Future<void> goToApplicationHome(StackRouter rootRouter) async {
    if (kIsWeb) {
      await LaunchUrlService.openExternalUrl('/', inCurrentWindow: true);
    } else {
      await rootRouter.replaceAll([OrganizationRoute()]);
    }
  }

  static void popOrHome(BuildContext context) {
    if (context.router.canPop()) {
      context.router.maybePop();
    } else {
      navigateOccasion(context, "");
    }
  }

  static void scheduleBack(BuildContext context) {
    // EventPage sits below both AutoTabsRouter and the program's nested
    // StackRouter. `context.router` can resolve to the outer occasion stack
    // for a directly opened deep link, so mutating it leaves EventRoute
    // untouched. Resolve the retained program tab exactly as the bottom-nav
    // reselection does and reset that stack instead.
    final tabsRouter = context.tabsRouter;
    final programRouter = tabsRouter.stackRouterOfIndex(tabsRouter.activeIndex);
    if (programRouter == null) {
      unawaited(replaceRootPath(
          context.router.root, getCurrentLink() + EventPage.ROUTE));
      return;
    }
    final canonicalRoot = programRouter.routeCollection.routes.firstWhere(
      (route) => route.path.isEmpty,
      orElse: () => throw StateError('Program router has no canonical root.'),
    );
    unawaited(
      programRouter.replaceAll([PageRouteInfo<void>(canonicalRoot.name)]),
    );
  }

  static bool canPop(BuildContext context) => context.router.canPop();
  static bool canNavigateBack(BuildContext context) =>
      context.router.canNavigateBack;

  static void goBackOrInitial(BuildContext context) {
    if (!context.router.canPop()) {
      goToInitial(context);
    } else {
      context.router.back();
    }
  }

  static void goBack(BuildContext context, [dynamic result]) {
    context.router.pop(result);
  }

  static Future<void> goToUnit(BuildContext context, int? unitId) async {
    if (unitId == null) {
      goToInitial(context);
      return;
    }
    await context.router.replace(UnitRoute(id: unitId));
  }

  static void goToInitial(BuildContext context) {
    navigateOccasion(context, "");
  }

  static Uri getCurrentUri() {
    return getCurrentBrowserUri();
  }

  /// Returns the actual browser address rather than [Uri.base], whose value on
  /// web is affected by the document's `<base href>` and can lose a deep link.
  static Uri getCurrentBrowserUri() {
    return Uri.parse(getCurrentBrowserUrl());
  }

  static String getCurrentUriWithOccasion() {
    if (Uri.base.scheme == "http" || Uri.base.scheme == "https") {
      return "${Uri.base.origin}${getCurrentLink()}";
    }
    return "${Uri.base}${getCurrentLink()}";
  }

  static final router = AppRouter();

  static void popTwo(BuildContext context) {
    Navigator.of(context)
      ..pop()
      ..pop();
  }

  /// Navigates to a specific unit's edit page after updating app data.
  static Future<void> navigateToUnitAdmin(
      BuildContext context, UnitModel unit) async {
    await RouterService.navigate(context, "unit/${unit.id!}/edit");
  }

  /// Clear a deleted occasion from the route stack and reload its unit.
  static Future<void> replaceWithUnitAdmin(
      BuildContext context, int unitId) async {
    final rootRouter = context.router.root;
    await RightsService.updateAppData(
        unitId: unitId, force: true, refreshOffline: false);
    await rootRouter.replaceAll([UnitAdminRoute(id: unitId)]);
  }

  @visibleForTesting
  static UnitModel? postLoginAdminUnit(List<UnitModel>? userUnits) {
    if (userUnits != null && userUnits.isNotEmpty) {
      return userUnits.first;
    }
    return null;
  }

  static Future<void> navigateHome(BuildContext context) async {
    String targetHomePath = fixPath(""); // This resolves to "/"

    // Check if the current path is already the target home path
    if (context.routeData.path == targetHomePath) {
      await RightsService.updateAppData(
          unitId: null, force: true, refreshOffline: false);
      if (!context.mounted) return;
      if (kIsWeb && AppConfig.isWebclientSupported) {
        await LaunchUrlService.openExternalUrl(
          "/",
          inCurrentWindow: true,
        );
      }
      // Already at home, so don't navigate
      return;
    }

    if (kIsWeb && AppConfig.isWebclientSupported) {
      if (!await RetainedDraftGuard.instance
          .confirmPath(context.router.root, Uri.parse(targetHomePath))) return;
      await LaunchUrlService.openExternalUrl(
        "/",
        inCurrentWindow: true,
      );
      return;
    }

    // Not at home, navigate
    await RouterService.navigate(context, ""); // Navigates to "/"
  }

  /// The routed entry page loads and checks the occasion after navigation.
  static Future<void> navigateToOccasionByLink(
      BuildContext context, String link) async {
    await RouterService.navigate(context, "/$link/${AdminPage.ROUTE}");
  }

  /// The routed reservation boundary owns its context load and access check.
  static Future<void> navigateToOccasionReservationsByLink(
      BuildContext context, String link) async {
    await RouterService.navigate(context, "/$link/${ReservationsPage.ROUTE}");
  }

  /// Preserve the nearest administration ancestor when changing occasions.
  /// Outside a shell, keep the existing product default.
  static Future<void> navigateToOccasionAdministration(BuildContext context,
      {String? occasionLink, OccasionModel? occasion}) async {
    String? resolvedLink = occasionLink ?? occasion?.link;

    // Get the link from arguments or route parameters.
    if (resolvedLink == null || resolvedLink.isEmpty) {
      resolvedLink = context.routeData.inheritedPathParams
          .getString(AppRouter.linkFormatted);
    }

    // If no link could be resolved, we can't navigate.
    if (resolvedLink.isEmpty) {
      AppLogger.error(
          "RouterService Error: Could not resolve occasion link for navigation.");
      return;
    }

    // Preserve static section/subtab paths, but never carry an object's ID
    // into another occasion. Read the active router, since the breadcrumb's
    // BuildContext may belong to the outer shell rather than its selected tab.
    final active = context.router.root.currentSegments;
    final shellIndex = active.indexWhere((route) =>
        route.name == AdminRoute.name || route.name == ReservationsRoute.name);
    if (shellIndex >= 0) {
      final shell = active[shellIndex].name == ReservationsRoute.name
          ? ReservationsPage.ROUTE
          : AdminPage.ROUTE;
      final suffix = <String>[];
      for (final route in active.skip(shellIndex + 1)) {
        if (route.path.contains(':') || route.path.contains('*')) break;
        suffix.addAll(route.path.split('/').where((part) => part.isNotEmpty));
      }
      await navigate(
          context,
          '/$resolvedLink/$shell'
          '${suffix.isEmpty ? '' : '/${suffix.join('/')}'}');
      return;
    }

    if (!AppConfig.isAppSupported ||
        (occasion != null &&
            FeatureService.isFeatureEnabled(FeatureConstants.form,
                features: occasion.features))) {
      await navigateToOccasionReservationsByLink(context, resolvedLink);
      return;
    }

    // 2. Fallback to the default route from AppConfig.
    if (AppConfig.defaultAdministrationRoute == ReservationsPage.ROUTE) {
      await navigateToOccasionReservationsByLink(context, resolvedLink);
    } else {
      // Default to the main admin page.
      await navigateToOccasionByLink(context, resolvedLink);
    }
  }

  static final JSInterop _js = JSInterop();

  /// Provides a stream of `popstate` events from the browser.
  /// On non-web platforms, returns an empty stream.
  static Stream<dynamic> get onPopState {
    if (kIsWeb) {
      return _js.onPopState;
    }
    return Stream.empty();
  }

  /// Pushes a new "fake" history state for an overlay.
  /// [overlayTag] is a string like "seat-reservation" to be appended as a hash.
  static void pushOverlayState(String overlayTag) {
    if (kIsWeb) {
      final currentUrl = _js.getCurrentUrl();
      _js.pushState('$currentUrl#$overlayTag');
    }
  }

  /// Triggers a `history.back()` command in the browser.
  static void goBackProgrammatically() {
    if (kIsWeb) {
      _js.goBack();
    }
  }

  /// Gets the current full URL from the browser.
  static String getCurrentBrowserUrl() {
    if (kIsWeb) {
      return _js.getCurrentUrl();
    }
    return Uri.base.toString(); // Fallback
  }

  /// (Legacy Support) Replaces the current history state.
  /// Used by NotificationHelper.
  static void changeUrl(String newUrl) {
    if (kIsWeb) {
      _js.changeUrl(newUrl);
    }
  }

  /// Centralized logic for navigation after successful login.
  /// Used by both [LoginPage] and [TransferPage] to ensure consistent behavior.
  static bool isAdministrationReturnPath(String? path) {
    final uri = path == null ? null : Uri.tryParse(path);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        !uri.path.startsWith('/')) return false;
    final segments = uri.pathSegments;
    return (segments.length >= 2 &&
            (segments[1] == 'admin' || segments[1] == 'reservations')) ||
        (segments.length >= 3 &&
            segments[0] == 'unit' &&
            int.tryParse(segments[1]) != null &&
            segments[2] == 'edit');
  }

  static Future<void> handlePostLoginNavigation(BuildContext context,
      {String? fallbackPath, bool useReplacement = false}) async {
    // An explicit protected destination has priority over the generic unit landing.
    if (isAdministrationReturnPath(fallbackPath)) {
      final target = Uri.parse(fallbackPath!);
      if (target.pathSegments.first == 'unit') {
        await RightsService.updateAppData(
            unitId: int.parse(target.pathSegments[1]),
            force: true,
            refreshOffline: false);
      } else {
        await RightsService.updateAppData(
            link: target.pathSegments.first,
            force: true,
            refreshOffline: false);
      }
      if (!context.mounted) return;
      await replaceRootPath(context.router.root, target.toString());
      return;
    }
    final initialUnitId = RightsService.currentUnit()?.id;
    final initialLink = currentOccasionLink;
    // Explicit destinations above win. Only a generic administration entry
    // resumes the previous workspace, after checking its current server rights.
    if (LastAdministrationContext.canRestoreFor(fallbackPath)) {
      final userId = RightsService.currentUser()?.id;
      final remembered = await LastAdministrationContext.instance
          .restore(AppConfig.organization, userId, canAccess: (path) async {
        final parts = Uri.parse(path).pathSegments;
        try {
          if (parts.first == 'unit') {
            final id = int.parse(parts[1]);
            await RightsService.updateAppData(
                unitId: id, force: true, refreshOffline: false);
            return RightsService.currentUser()?.id == userId &&
                RightsService.currentUnit()?.id == id &&
                RightsService.isUnitEditorView();
          }
          await RightsService.updateAppData(
              link: parts.first, force: true, refreshOffline: false);
          return RightsService.currentUser()?.id == userId &&
              RightsService.currentLink == parts.first &&
              (parts.last == 'reservations'
                  ? RightsService.canSeeReservations()
                  : RightsService.canSeeAdministration());
        } catch (_) {
          final state = RightsService.occasionLinkModel;
          if (state?.isAccessDenied() == true || state?.isNotFound() == true) {
            return false;
          }
          rethrow;
        }
      });
      if (!context.mounted) return;
      if (remembered != null) {
        await replaceRootPath(context.router.root, remembered);
        return;
      }
    }
    // 1. Update App Data
    var unitId = initialUnitId == 1 ? null : initialUnitId;

    // If no current link, try to extract it from the fallback path
    String linkToUse = initialLink;
    if ((linkToUse.isEmpty) &&
        fallbackPath != null &&
        fallbackPath.isNotEmpty) {
      try {
        // handlePostLoginNavigation is often called with a path like "/event_name/admin"
        // extractOccasionLink expects a full URL or a path.
        var extracted = LinkModel.extractOccasionLink(fallbackPath);
        if (extracted.occasionLink != null &&
            extracted.occasionLink!.isNotEmpty) {
          linkToUse = extracted.occasionLink!;
          AppLogger.debug(
              "[RouterService] Post-Login: Extracted link '$linkToUse' from fallbackPath '$fallbackPath'");
        }
      } catch (e) {
        AppLogger.error(
            "[RouterService] Post-Login: Failed to extract link from fallbackPath: $e");
      }
    }

    await RightsService.updateAppData(
        unitId: unitId, link: linkToUse, force: true);

    // 2. Check for Units (Admin flow priority). A managed unit must win over
    // the fallback even when a unit context is already loaded.
    final adminUnit = postLoginAdminUnit(RightsService.currentUser()?.units);
    if (adminUnit != null) {
      AppLogger.debug(
          "[RouterService] Post-Login: User has units. Navigating to UnitAdmin.");
      if (useReplacement) {
        final rootRouter = context.router.root;
        await RightsService.updateAppData(
            unitId: adminUnit.id, force: true, refreshOffline: false);
        await rootRouter.replaceAll([UnitAdminRoute(id: adminUnit.id)]);
      } else {
        await navigateToUnitAdmin(context, adminUnit);
      }
      return;
    }

    // 3. Fallback Navigation
    // If no specific unit, go to fallback or pop/home.
    if (fallbackPath != null && fallbackPath.isNotEmpty) {
      // If the redirect target is explicitly "Login", but we are already logged in (post-login flow),
      // we should NOT go to login. We should go Home instead.
      if (fallbackPath.toLowerCase() == "/login" ||
          fallbackPath.toLowerCase() == "login") {
        AppLogger.debug(
            "[RouterService] Post-Login: Redirect was 'login', avoiding redundant loop. Going Home.");
        await replaceRootPath(context.router.root, '/');
        return;
      }

      AppLogger.debug(
          "[RouterService] Post-Login: Using fallback path: $fallbackPath (Replace: $useReplacement)");
      if (useReplacement) {
        // Fix path to ensure it starts with /
        String target = fixPath(fallbackPath);
        await replaceRootPath(context.router.root, target);
      } else {
        await navigate(context, fallbackPath);
      }
    } else {
      // Default behavior (pop or home)
      AppLogger.debug("[RouterService] Post-Login: Pop or Home");
      if (useReplacement) {
        // If we must replace but have no specific target, we go Home.
        await replaceRootPath(context.router.root, '/');
      } else {
        popOrHome(context);
      }
    }
  }
}

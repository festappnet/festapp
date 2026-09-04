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
    return context.router.pushPath(getCurrentLink() + path);
  }

  static Future<T?> navigateOccasionNoContext<T extends Object?>(String path) {
    return router.pushPath(getCurrentLink() + path);
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

    return context.router.root.pushPath(path);
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
    await context.router.replacePath(path);
  }

  static void pushReplacementOccasion<T extends Object?>(
      BuildContext context, String path) {
    context.router.replacePath(getCurrentLink() + path);
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
      unawaited(
          context.router.root.replacePath(getCurrentLink() + EventPage.ROUTE));
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
    await RightsService.updateAppData(
        unitId: unit.id, force: true, refreshOffline: false);
    await RouterService.navigate(
        context, "unit/${RightsService.currentUnit()!.id!}/edit");
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

    // First, update app data regardless of navigation
    await RightsService.updateAppData(
        unitId: null, force: true, refreshOffline: false);

    // Check if the current path is already the target home path
    if (context.routeData.path == targetHomePath) {
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
      await LaunchUrlService.openExternalUrl(
        "/",
        inCurrentWindow: true,
      );
      return;
    }

    // Not at home, navigate
    await RouterService.navigate(context, ""); // Navigates to "/"
  }

  /// Navigates to a specific occasion's admin page after updating app data.
  static Future<void> navigateToOccasionByLink(
      BuildContext context, String link) async {
    await RightsService.updateAppData(
        link: link, force: true, refreshOffline: false);
    await RouterService.navigate(context, "/$link/${AdminPage.ROUTE}");
  }

  /// Navigates to a specific occasion's reservation page after updating app data.
  static Future<void> navigateToOccasionReservationsByLink(
      BuildContext context, String link) async {
    await RightsService.updateAppData(
        link: link, force: true, refreshOffline: false);
    await RouterService.navigate(context, "/$link/${ReservationsPage.ROUTE}");
  }

  /// Navigates to an occasion's administration page based on context.
  ///
  /// This method determines the destination by first checking the type of the
  /// current widget from the `BuildContext`. If the context is an `AdminPage` or
  /// `ReservationsPage`, it navigates to the corresponding view.
  ///
  /// If the widget type isn't a recognized admin page, it uses the fallback route
  /// defined in `AppConfig.defaultAdministrationRoute`.
  ///
  /// The [occasionLink] can be passed directly. If not, it's extracted from
  /// the current route's parameters.
  static Future<void> navigateToOccasionAdministration(BuildContext context,
      {String? occasionLink, OccasionModel? occasion}) async {
    // If occasion is provided, prioritize it for feature checks
    if (occasion != null) {
      if (FeatureService.isFeatureEnabled(FeatureConstants.form,
          features: occasion.features)) {
        await navigateToOccasionReservationsByLink(
            context, occasion.link ?? occasionLink!);
        return;
      }
    }

    String? resolvedLink = occasionLink ?? occasion?.link;

    // Get the link from arguments or route parameters.
    if (resolvedLink == null || resolvedLink.isEmpty) {
      resolvedLink = context.routeData.params.getString(link);
    }

    // If no link could be resolved, we can't navigate.
    if (resolvedLink.isEmpty) {
      AppLogger.error(
          "RouterService Error: Could not resolve occasion link for navigation.");
      return;
    }

    if (!AppConfig.isAppSupported) {
      await navigateToOccasionReservationsByLink(context, resolvedLink);
      return;
    }

    // 1. Decide destination based on the current widget type.
    if (context.widget is AdminPage) {
      await navigateToOccasionByLink(context, resolvedLink);
      return;
    } else if (context.widget is ReservationsPage) {
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
  static Future<void> handlePostLoginNavigation(BuildContext context,
      {String? fallbackPath, bool useReplacement = false}) async {
    // 1. Update App Data
    var unitId = RightsService.currentUnit()?.id == 1
        ? null
        : RightsService.currentUnit()?.id;

    // If no current link, try to extract it from the fallback path
    String linkToUse = currentOccasionLink;
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
      await navigateToUnitAdmin(context, adminUnit);
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
        await context.router.replacePath('/');
        return;
      }

      AppLogger.debug(
          "[RouterService] Post-Login: Using fallback path: $fallbackPath (Replace: $useReplacement)");
      if (useReplacement) {
        // Fix path to ensure it starts with /
        String target = fixPath(fallbackPath);
        await context.router.replacePath(target);
      } else {
        await navigate(context, fallbackPath);
      }
    } else {
      // Default behavior (pop or home)
      AppLogger.debug("[RouterService] Post-Login: Pop or Home");
      if (useReplacement) {
        // If we must replace but have no specific target, we go Home.
        await context.router.replacePath('/');
      } else {
        popOrHome(context);
      }
    }
  }
}

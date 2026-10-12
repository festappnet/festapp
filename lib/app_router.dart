import 'package:fstapp/components/navigation/platform_route_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'package:fstapp/components/navigation/navigation_paths.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart'; // Already imported, no change needed
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/schedule_feature.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/forms/views/reservation_page.dart';
import 'package:fstapp/components/scan/check_page.dart';
import 'package:fstapp/components/schedule/event_edit_page.dart';
import 'package:fstapp/components/schedule/event_page.dart';
import 'package:fstapp/components/inventory/views/user_stay_page.dart';
import 'package:fstapp/components/occasion/admin_page.dart';
import 'package:fstapp/components/unit/views/unit_page.dart';
import 'package:fstapp/components/users/views/login_page.dart';
import 'package:fstapp/components/users/views/transfer_page.dart';
import 'package:fstapp/components/users/views/reset_password_page.dart';
import 'package:fstapp/components/information/info_page.dart';
import 'package:fstapp/components/app_management/install_page.dart';
import 'package:fstapp/components/map/map_page.dart';
import 'package:fstapp/components/news/news_form_page.dart';
import 'package:fstapp/components/news/news_page.dart';
import 'package:fstapp/components/schedule/my_schedule_page.dart';
import 'package:fstapp/components/speakers/counseling_page.dart';
import 'package:fstapp/components/cleaning/cleaning_page.dart';
import 'package:fstapp/components/users/views/forgot_password_page.dart';
import 'package:fstapp/components/scan/scan_page.dart';
import 'package:fstapp/components/app_management/settings_page.dart';
import 'package:fstapp/components/users/views/signup_page.dart';
import 'package:fstapp/components/information/song/song_page.dart';
import 'package:fstapp/components/schedule/timetable_page.dart';
import 'package:fstapp/components/users/views/user_page.dart';
import 'package:fstapp/components/forms/views/form_page.dart';
import 'package:fstapp/components/app_management/instance_install_page.dart';
import 'package:fstapp/components/reception/reception_page.dart';
import 'package:fstapp/components/reception/login_qr_scanner_page.dart';

import 'app_router.gr.dart';
import 'components/information/game/game_page.dart';

// Keep web routes in one executable bundle. Separate deferred JS chunks can
// strand an already-installed PWA on AutoRoute's loading placeholder when a
// deployment replaces a chunk that the older runtime has not cached yet.
@AutoRouterConfig(replaceInRouteName: 'Page,Route', deferredLoading: false)
class AppRouter extends RootStackRouter {
  @override
  DefaultRouteParser defaultRouteParser(
          {bool includePrefixMatches = !kIsWeb,
          DeepLinkTransformer? deepLinkTransformer}) =>
      PlatformRouteParser(matcher,
          includePrefixMatches: includePrefixMatches,
          deepLinkTransformer: deepLinkTransformer);

  static const String LINK = "occasionLink";
  static const String linkFormatted = "{$LINK}";

  @override
  List<AutoRouteGuard> get guards => [RetainedDraftGuard.instance];

  @override
  RouteType get defaultRouteType => const RouteType.material();

  @override
  List<AutoRoute> get routes => [
        CustomRoute(
            page: OrganizationRoute.page,
            path: "/",
            guards: [InitialRedirectGuard()],
            transitionsBuilder: TransitionsBuilders.noTransition),

        AutoRoute(
            page: ResetPasswordRoute.page, path: sl(ResetPasswordPage.ROUTE)),
        AutoRoute(
            page: ForgotPasswordRoute.page, path: sl(ForgotPasswordPage.ROUTE)),
        RedirectRoute(path: '/app/google-auth', redirectTo: '/login'),
        AutoRoute(page: LoginRoute.page, path: sl(LoginPage.ROUTE)),
        AutoRoute(
            page: LoginQrScannerRoute.page, path: sl(LoginQrScannerPage.ROUTE)),
        AutoRoute(page: SignupRoute.page, path: sl(SignupPage.ROUTE)),
        AutoRoute(page: SettingsRoute.page, path: sl(SettingsPage.ROUTE)),
        AutoRoute(page: InstallRoute.page, path: sl(InstallPage.ROUTE)),
        AutoRoute(page: TransferRoute.page, path: "/${TransferPage.ROUTE}"),
        AutoRoute(
            page: InstanceInstallRoute.page,
            path: sl(InstanceInstallPage.ROUTE)),
        CustomRoute(
            page: UnitAdminRoute.page,
            // Retained context routers must have different keys per unit/link.
            usesPathAsKey: true,
            path: "/${UnitPage.ROUTE}/:id/edit",
            children: [
              AutoRoute(
                  page: UnitAdministrationTabsRoute.page,
                  path: '',
                  initial: true,
                  children: [
                    RedirectRoute(
                        path: '', redirectTo: NavigationPaths.occasions),
                    AutoRoute(
                        page: UnitOccasionsRoute.page,
                        path: NavigationPaths.occasions),
                    AutoRoute(
                        page: UnitUsersRoute.page, path: NavigationPaths.users),
                    AutoRoute(
                        page: UnitQuotesRoute.page,
                        path: NavigationPaths.quotes),
                    AutoRoute(
                        page: UnitEmailTemplatesRoute.page,
                        path: NavigationPaths.emailTemplates),
                    AutoRoute(
                        page: UnitSettingsRoute.page,
                        path: NavigationPaths.settings),
                    AutoRoute(
                        page: UnitBankAccountsNavigationRoute.page,
                        path: NavigationPaths.bankAccounts,
                        children: [
                          AutoRoute(
                              page: UnitBankAccountsListRoute.page,
                              path: '',
                              initial: true),
                          AutoRoute(
                              page: BankAccountDetailRoute.page,
                              path: ':accountId',
                              children: [
                                AutoRoute(
                                    page: BankAccountTabsRoute.page,
                                    path: '',
                                    initial: true,
                                    children: [
                                      RedirectRoute(
                                          path: '',
                                          redirectTo: NavigationPaths.general),
                                      AutoRoute(
                                          page: BankAccountGeneralRoute.page,
                                          path: NavigationPaths.general),
                                      AutoRoute(
                                          page: BankAccountConnectionRoute.page,
                                          path: NavigationPaths.connection),
                                      AutoRoute(
                                          page: BankAccountUsersRoute.page,
                                          path: NavigationPaths.users)
                                    ]),
                                AutoRoute(
                                    page: NavigationNotFoundRoute.page,
                                    path: '*')
                              ]),
                          AutoRoute(
                              page: NavigationNotFoundRoute.page, path: '*')
                        ])
                  ]),
              AutoRoute(page: NavigationNotFoundRoute.page, path: '*')
            ],
            transitionsBuilder: TransitionsBuilders.noTransition),

        CustomRoute(
            page: OrganizationEditRoute.page,
            path: "/organizationEdit/:id",
            transitionsBuilder: TransitionsBuilders.noTransition),

        CustomRoute(
            page: OrganizationEditRedirectRoute.page,
            path: "/organizationEdit",
            transitionsBuilder: TransitionsBuilders.noTransition),

        // Use UnitPage for the /unit/:id path (this was commented out)
        AutoRoute(page: UnitRoute.page, path: "/${UnitPage.ROUTE}/:id"),

        AutoRoute(page: ScanRoute.page, path: "/${ScanPage.ROUTE}", children: [
          AutoRoute(
            path: ':scanCode',
            page: ScanRoute.page,
          ),
        ]),
        AutoRoute(page: FormRoute.page, path: "/${FormPage.ROUTE}/:formLink"),
        CustomRoute(
            page: ReservationsRoute.page,
            // Retained context routers must have different keys per unit/link.
            usesPathAsKey: true,
            path: "/:$linkFormatted/${ReservationsPage.ROUTE}",
            children: [
              AutoRoute(
                  page: ReservationsTabsRoute.page,
                  path: '',
                  initial: true,
                  children: [
                    RedirectRoute(path: '', redirectTo: NavigationPaths.orders),
                    AutoRoute(
                        page: OrdersNavigationRoute.page,
                        path: NavigationPaths.orders,
                        children: [
                          AutoRoute(
                              page: OrdersTabsRoute.page,
                              path: '',
                              initial: true,
                              children: [
                                RedirectRoute(
                                    path: '',
                                    redirectTo: NavigationPaths.current),
                                AutoRoute(
                                    page: OrdersCurrentRoute.page,
                                    path: NavigationPaths.current),
                                AutoRoute(
                                    page: OrdersHistoryRoute.page,
                                    path: NavigationPaths.history),
                                AutoRoute(
                                    page: OrdersEmailHistoryRoute.page,
                                    path: NavigationPaths.emailHistory)
                              ]),
                          AutoRoute(
                              page: NavigationNotFoundRoute.page, path: '*')
                        ]),
                    AutoRoute(
                        page: TicketsSectionRoute.page,
                        path: NavigationPaths.tickets),
                    AutoRoute(
                        page: BlueprintSectionRoute.page,
                        path: NavigationPaths.blueprint),
                    AutoRoute(
                        page: FormsNavigationRoute.page,
                        path: NavigationPaths.forms,
                        children: [
                          AutoRoute(
                              page: FormsListRoute.page,
                              path: '',
                              initial: true),
                          CustomRoute(
                              page: FormDetailRoute.page,
                              // Selecting the only form must not add a second
                              // nested slide after the outer Forms tab transition.
                              transitionsBuilder:
                                  TransitionsBuilders.noTransition,
                              duration: Duration.zero,
                              reverseDuration: Duration.zero,
                              path: ':formLink',
                              children: [
                                AutoRoute(
                                    page: FormTabsRoute.page,
                                    path: '',
                                    initial: true,
                                    children: [
                                      RedirectRoute(
                                          path: '',
                                          redirectTo: NavigationPaths.editor),
                                      AutoRoute(
                                          page: FormEditorRoute.page,
                                          path: NavigationPaths.editor),
                                      AutoRoute(
                                          page: FormSettingsRoute.page,
                                          path: NavigationPaths.settings),
                                      AutoRoute(
                                          page: FormDesignRoute.page,
                                          path: NavigationPaths.design),
                                      AutoRoute(
                                          page: FormResponsesRoute.page,
                                          path: NavigationPaths.responses)
                                    ]),
                                AutoRoute(
                                    page: NavigationNotFoundRoute.page,
                                    path: '*')
                              ]),
                          AutoRoute(
                              page: NavigationNotFoundRoute.page, path: '*')
                        ]),
                    AutoRoute(
                        page: ProductsSectionRoute.page,
                        path: NavigationPaths.products),
                    AutoRoute(
                        page: InventoryPoolsNavigationRoute.page,
                        path: NavigationPaths.inventoryPools,
                        children: [
                          AutoRoute(
                              page: InventoryPoolsListRoute.page,
                              path: '',
                              initial: true),
                          AutoRoute(
                              page: InventoryPoolDetailRoute.page,
                              path: ':poolId',
                              children: [
                                AutoRoute(
                                    page: InventoryPoolTabsRoute.page,
                                    path: '',
                                    initial: true,
                                    children: [
                                      RedirectRoute(
                                          path: '',
                                          redirectTo:
                                              NavigationPaths.occupancy),
                                      AutoRoute(
                                          page:
                                              InventoryPoolOccupancyRoute.page,
                                          path: NavigationPaths.occupancy),
                                      AutoRoute(
                                          page: InventoryPoolRoomsRoute.page,
                                          path: NavigationPaths.rooms),
                                      AutoRoute(
                                          page: InventoryPoolSettingsRoute.page,
                                          path: NavigationPaths.settings)
                                    ]),
                                AutoRoute(
                                    page: NavigationNotFoundRoute.page,
                                    path: '*')
                              ]),
                          AutoRoute(
                              page: NavigationNotFoundRoute.page, path: '*')
                        ]),
                    AutoRoute(
                        page: ReportSectionRoute.page,
                        path: NavigationPaths.report),
                    AutoRoute(
                        page: EmailTemplatesSectionRoute.page,
                        path: NavigationPaths.emailTemplates),
                    AutoRoute(
                        page: UsersSectionRoute.page,
                        path: NavigationPaths.users),
                    AutoRoute(
                        page: SettingsSectionRoute.page,
                        path: NavigationPaths.settings)
                  ]),
              AutoRoute(page: NavigationNotFoundRoute.page, path: '*')
            ],
            transitionsBuilder: TransitionsBuilders.noTransition),
        AutoRoute(
            page: CheckRoute.page,
            path: "/:$linkFormatted/${CheckPage.ROUTE}/:id"),
        AutoRoute(
            page: NewsFormRoute.page,
            path: "/:$linkFormatted/${NewsFormPage.ROUTE}"),
        CustomRoute(
            page: AdminRoute.page,
            // Retained context routers must have different keys per unit/link.
            usesPathAsKey: true,
            path: "/:$linkFormatted/${AdminPage.ROUTE}",
            children: [
              AutoRoute(
                  page: AdminTabsRoute.page,
                  path: '',
                  initial: true,
                  children: [
                    RedirectRoute(path: '', redirectTo: NavigationPaths.info),
                    AutoRoute(
                        page: InformationNavigationRoute.page,
                        path: NavigationPaths.info,
                        children: [
                          AutoRoute(
                              page: InformationTabsRoute.page,
                              path: '',
                              initial: true,
                              children: [
                                RedirectRoute(
                                    path: '',
                                    redirectTo: NavigationPaths.information),
                                AutoRoute(
                                    page: InformationInformationRoute.page,
                                    path: NavigationPaths.information),
                                AutoRoute(
                                    page: InformationSongbookRoute.page,
                                    path: NavigationPaths.songbook)
                              ]),
                          AutoRoute(
                              page: NavigationNotFoundRoute.page, path: '*')
                        ]),
                    AutoRoute(
                        page: ScheduleNavigationRoute.page,
                        path: NavigationPaths.events,
                        children: [
                          AutoRoute(
                              page: ScheduleTabsRoute.page,
                              path: '',
                              initial: true,
                              children: [
                                RedirectRoute(
                                    path: '',
                                    redirectTo: NavigationPaths.schedule),
                                AutoRoute(
                                    page: ScheduleScheduleRoute.page,
                                    path: NavigationPaths.schedule),
                                AutoRoute(
                                    page: ScheduleSuspiciousRoute.page,
                                    path: NavigationPaths.suspicious),
                                AutoRoute(
                                    page: ScheduleExclusivityRoute.page,
                                    path: NavigationPaths.exclusivity),
                                AutoRoute(
                                    page: ScheduleFeedbackRoute.page,
                                    path: NavigationPaths.feedback)
                              ]),
                          AutoRoute(
                              page: NavigationNotFoundRoute.page, path: '*')
                        ]),
                    AutoRoute(
                        page: PlacesNavigationRoute.page,
                        path: NavigationPaths.places,
                        children: [
                          AutoRoute(
                              page: PlacesTabsRoute.page,
                              path: '',
                              initial: true,
                              children: [
                                RedirectRoute(
                                    path: '', redirectTo: NavigationPaths.list),
                                AutoRoute(
                                    page: PlacesListRoute.page,
                                    path: NavigationPaths.list),
                                AutoRoute(
                                    page: PlacesPathsRoute.page,
                                    path: NavigationPaths.paths),
                                AutoRoute(
                                    page: PlacesTypesRoute.page,
                                    path: NavigationPaths.types),
                                AutoRoute(
                                    page: PlacesIconsRoute.page,
                                    path: NavigationPaths.icons)
                              ]),
                          AutoRoute(
                              page: NavigationNotFoundRoute.page, path: '*')
                        ]),
                    AutoRoute(
                        page: SpeakersSectionRoute.page,
                        path: NavigationPaths.speakers),
                    AutoRoute(
                        page: GroupsSectionRoute.page,
                        path: NavigationPaths.groups),
                    AutoRoute(
                        page: GameNavigationRoute.page,
                        path: NavigationPaths.game,
                        children: [
                          AutoRoute(
                              page: GameTabsRoute.page,
                              path: '',
                              initial: true,
                              children: [
                                RedirectRoute(
                                    path: '',
                                    redirectTo: NavigationPaths.checkpoints),
                                AutoRoute(
                                    page: GameCheckpointsRoute.page,
                                    path: NavigationPaths.checkpoints),
                                AutoRoute(
                                    page: GameGroupsRoute.page,
                                    path: NavigationPaths.groups),
                                AutoRoute(
                                    page: GameSettingsRoute.page,
                                    path: NavigationPaths.settings)
                              ]),
                          AutoRoute(
                              page: NavigationNotFoundRoute.page, path: '*')
                        ]),
                    AutoRoute(
                        page: ServiceSectionRoute.page,
                        path: NavigationPaths.services),
                    AutoRoute(
                        page: VolunteersSectionRoute.page,
                        path: NavigationPaths.volunteers),
                    AutoRoute(
                        page: EmailTemplatesSectionRoute.page,
                        path: NavigationPaths.emailTemplates),
                    AutoRoute(
                        page: UsersSectionRoute.page,
                        path: NavigationPaths.users),
                    AutoRoute(
                        page: ChangesSectionRoute.page,
                        path: NavigationPaths.changes),
                    AutoRoute(
                        page: SettingsSectionRoute.page,
                        path: NavigationPaths.settings)
                  ]),
              AutoRoute(page: NavigationNotFoundRoute.page, path: '*')
            ],
            transitionsBuilder: TransitionsBuilders.noTransition),
        AutoRoute(
            page: MyScheduleRoute.page,
            path: "/:$linkFormatted/${MySchedulePage.ROUTE}"),
        // Counseling rozcestník is a full-screen page (own Scaffold + back
        // button), NOT a bottom-nav tab — so it must be a top-level occasion
        // route. As a child of the tabbed OccasionHomeRoute it could not be
        // resolved by the AutoTabsRouter (which only knows its tab routes), so
        // deep links / redirects to it fell back to the default Program tab.
        AutoRoute(
            page: CounselingRoute.page,
            path: "/:$linkFormatted/${CounselingPage.ROUTE}"),
        // Cleaning page: top-level occasion route (own Scaffold like Counseling)
        // with an optional `:id` self-child so `cleaning/:placeId` deep-links
        // straight into the report dialog (same idiom as EventEditPage).
        AutoRoute(
            page: CleaningRoute.page,
            path: "/:$linkFormatted/${CleaningPage.ROUTE}",
            children: [
              AutoRoute(path: ':id', page: CleaningRoute.page),
            ]),
        AutoRoute(
            page: ReceptionRoute.page,
            path: "/:$linkFormatted/${ReceptionPage.ROUTE}"),
        AutoRoute(
            page: TimetableRoute.page,
            path: "/:$linkFormatted/${TimetablePage.ROUTE}"),
        AutoRoute(
            page: GameRoute.page, path: "/:$linkFormatted/${GamePage.ROUTE}"),
        AutoRoute(
            page: SongbookRoute.page,
            path: "/:$linkFormatted/${SongbookPage.ROUTE}"),
        AutoRoute(
            page: UserStayRoute.page,
            path: "/:$linkFormatted/${UserStayPage.ROUTE}"),
        AutoRoute(page: MapEditorRoute.page, path: '/map-editor'),
        AutoRoute(
            page: EventEditRoute.page,
            path: "/:$linkFormatted/${EventEditPage.ROUTE}",
            children: [
              AutoRoute(
                path: ':id',
                page: EventEditRoute.page,
              ),
            ]),
        AutoRoute(
            page: OccasionHomeRoute.page,
            path: "/:$linkFormatted",
            children: [
              AutoRoute(page: UserRoute.page, path: UserPage.ROUTE),
              AutoRoute(
                  page: ScheduleNavigationRoute.page,
                  path: EventPage.ROUTE,
                  children: [
                    getSchedulePage(),
                    AutoRoute(page: EventRoute.page, path: ":id")
                  ]),
              AutoRoute(page: NewsRoute.page, path: NewsPage.ROUTE),

              // Use UnitPage for the nested /:occasionLink/unit path
              AutoRoute(
                  page: UnitRoute.page,
                  path: UnitPage.ROUTE,
                  maintainState: false),

              RedirectRoute(
                path: MapPage.ROUTE,
                redirectTo:
                    '${MapPage.ROUTE}/${PublicMapPage.overviewDestination}',
              ),
              AutoRoute(
                page: PublicMapRoute.page,
                path: '${MapPage.ROUTE}/:destination',
              ),
              AutoRoute(page: InfoRoute.page, path: InfoPage.ROUTE, children: [
                AutoRoute(
                  path: ':id',
                  page: InfoRoute.page,
                ),
              ]),
              AutoRoute(page: TimetableRoute.page, path: TimetablePage.ROUTE),
            ]),

        RedirectRoute(path: '*', redirectTo: getDefaultLink()),
      ];

  static AutoRoute getSchedulePage() {
    var scheduleFeat =
        FeatureService.getFeatureDetails(ScheduleFeature.metaSchedule);
    if (scheduleFeat is ScheduleFeature) {
      if (scheduleFeat.scheduleType == ScheduleFeature.scheduleTypeAdvanced) {
        return AutoRoute(page: ScheduleRoute.page, path: "", initial: true);
      }
      if (scheduleFeat.scheduleType == ScheduleFeature.scheduleTypeLight) {
        return AutoRoute(
            page: ScheduleLightRoute.page, path: "", initial: true);
      }
    }
    return AutoRoute(page: ScheduleBasicRoute.page, path: "", initial: true);
  }

  static String getDefaultLink() {
    if (!AppConfig.isAppSupported) {
      return "/";
    }

    if (RightsService.useOfflineVersion) {
      return getOccasionLandingPath(RightsService.currentLink!);
    }
    if (RightsService.currentLink != null) {
      return getOccasionLandingPath(RightsService.currentLink!);
    }

    if (AppConfig.isAllUnit) return "/";

    final unitId = RightsService.currentUnit()?.id ??
        RightsService.occasionLinkModel?.organization?.defaultUnit;
    return unitId == null ? "/" : "/${UnitPage.ROUTE}/$unitId";
  }

  static String getOccasionLandingPath(String occasionLink) =>
      "/$occasionLink/${EventPage.ROUTE}";

  static void Function()? regenerateRoutes;

  /// Static sl function to standardize the route format.
  static String sl(String route) {
    return route.startsWith('/') ? route : '/$route';
  }

  static List<String> getRootLinks() {
    return [
      ResetPasswordPage.ROUTE,
      ForgotPasswordPage.ROUTE,
      LoginPage.ROUTE,
      SignupPage.ROUTE,
      SettingsPage.ROUTE,
      InstallPage.ROUTE,
      UnitPage.ROUTE,
      AdminPage.ROUTE,
      FormPage.ROUTE,
      ScanPage.ROUTE,
      TransferPage.ROUTE,
      'app',
      'privacy',
      'terms',
      'support',
      'delete-account',
    ];
  }
}

/// Observer to monitor routing events for debugging or analytics purposes.
class RoutingObserver extends AutoRouteObserver {
  @override
  void didPush(Route route, Route? previousRoute) {}

  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) {}

  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) {}
}

/// This guard checks if the app is supported when landing on the root '/'.
/// If the app is supported, it redirects to the appropriate unit or occasion.
/// If not, it allows the user to see the OrganizationPage at '/'.
class InitialRedirectGuard extends AutoRouteGuard {
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final redirectPath = AppRouter.getDefaultLink();

    if (redirectPath != "/") {
      router.replacePath(redirectPath);
    } else {
      resolver.next(true);
    }
  }
}

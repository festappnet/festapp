import 'dart:async';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/config/url_strategy_noop.dart'
    if (dart.library.html) 'package:fstapp/config/url_strategy_web.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/synchro_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/client_sync/client_sync_endpoint_service.dart';
import 'package:fstapp/components/occasion/occasion_home_page.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/services/health_tracking_http_client.dart';
import 'package:fstapp/services/notification_helper.dart';
import 'package:fstapp/services/installation_cutover_service.dart';
import 'package:fstapp/startup/startup_failure_policy.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/search/global_search_dialog.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/web_styles_helper.dart';
import 'package:fstapp/services/web_bootstrap_bridge.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/backend_activation_service.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/time_travel_widget.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pwa_install/pwa_install.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  debugProfileBuildsEnabled = true;
  configureUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  final initialRoute = kIsWeb
      ? initialRouteForUri(RouterService.getCurrentBrowserUri())
      : WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  runApp(FestappBootstrap(
    initialRoute: initialRoute,
    initialize: initializeEverything,
    buildReadyApp: () => EasyLocalization(
      supportedLocales:
          AppConfig.availableLanguages().map((e) => e.locale).toList(),
      path: "assets/translations",
      fallbackLocale: AppConfig.availableLanguages().map((e) => e.locale).first,
      useOnlyLangCode: true,
      saveLocale: true,
      child: MyApp(initialRoute: initialRoute),
    ),
  ));
}

NotificationReconnectCoordinator? _notificationReconnectCoordinator;

String initialRouteForUri(Uri uri) {
  final path = uri.path == '/' && AppConfig.forceOccasionLink != null
      ? '/${AppConfig.forceOccasionLink}'
      : uri.path;
  return '$path${uri.hasQuery ? '?${uri.query}' : ''}';
}

/// Paints immediately on PWA, Android and iOS while startup restores the local
/// context and probes online services. A slow or unreachable backend therefore
/// cannot leave the process sitting on an OS/browser splash with no Flutter UI.
class FestappBootstrap extends StatefulWidget {
  static const loadingKey = Key('festapp-startup-loading');

  final String initialRoute;
  final Future<void> Function() initialize;
  final Widget Function() buildReadyApp;

  const FestappBootstrap({
    this.initialRoute = '/',
    required this.initialize,
    required this.buildReadyApp,
    super.key,
  });

  @override
  State<FestappBootstrap> createState() => _FestappBootstrapState();
}

class _FestappBootstrapState extends State<FestappBootstrap> {
  late final String _initialRoute = widget.initialRoute;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await widget.initialize();
    } catch (error) {
      // initializeEverything isolates its individual steps already. This final
      // boundary still guarantees a usable app shell after an unexpected error.
      AppLogger.error('Unexpected startup failure: $error');
    }
    if (!mounted) return;
    setState(() => _isReady = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) WebBootstrapBridge.markAppReady();
    });
  }

  MaterialPageRoute<void> _loadingRoute(RouteSettings settings) =>
      MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const Scaffold(
          key: FestappBootstrap.loadingKey,
          body: Center(child: CircularProgressIndicator()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_isReady) return widget.buildReadyApp();
    return MaterialApp(
      key: const ValueKey('festapp-startup-material-app'),
      debugShowCheckedModeBanner: false,
      initialRoute: _initialRoute,
      onGenerateRoute: _loadingRoute,
      onGenerateInitialRoutes: (initialRoute) => [
        _loadingRoute(RouteSettings(name: initialRoute)),
      ],
    );
  }
}

Future<void> initializeEverything() async {
  AppLogger.debug('Initialization started');

  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.debug('Widgets binding initialized');

  final resolvedBackend = await BackendActivationService().resolve();
  AppConfig.organization = resolvedBackend.organizationId;
  ConnectivityService.configureBackendOrigin(resolvedBackend.supabaseUrl);
  AppLogger.debug(
    'Backend selected: ${resolvedBackend.isCanonical ? 'canonical' : 'legacy'} '
    'for organization ${resolvedBackend.organizationId} '
    '(profile ${resolvedBackend.profileSha256.isEmpty ? 'legacy' : resolvedBackend.profileSha256.substring(0, 12)})',
  );

  var allowPersistedOccasionData = false;
  try {
    await InstallationCutoverService(
      generation: resolvedBackend.installationGeneration(
        AppConfig.effectivePushAppGeneration,
      ),
    ).run();
    allowPersistedOccasionData = true;
    AppLogger.debug('Installation generation is current');
  } catch (e) {
    // Fail closed: startup may continue online, but no pre-cutover occasion
    // cache is read until the idempotent migration succeeds.
    AppLogger.error('Installation cutover failed: $e');
  }

  SynchroService.configure(
    isLoggedIn: AuthService.isLoggedIn,
    getFullUserInfo: AuthService.getFullUserInfo,
    getCurrentOccasionId: RightsService.currentOccasionId,
    useLegacyAppConfig: !resolvedBackend.isCanonical,
  );

  try {
    PWAInstall().setup();
    AppLogger.debug('PWA setup completed');
  } catch (e) {
    AppLogger.error('PWA setup failed: $e');
  }

  try {
    await ConnectivityService.initialize();
    AppLogger.debug('Connectivity service initialized');
  } catch (e) {
    AppLogger.error('Connectivity service initialization failed: $e');
  }
  final startOffline = ConnectivityService.isOfflineNotifier.value;
  var effectiveOffline = startOffline;
  var hasCachedOccasionSettings = false;

  try {
    await initializeDateFormatting();
    AppLogger.debug('Date formatting initialized');
  } catch (e) {
    AppLogger.error('Date formatting initialization failed: $e');
  }

  try {
    await EasyLocalization.ensureInitialized();
    AppLogger.debug('EasyLocalization initialized');
  } catch (e) {
    AppLogger.error('EasyLocalization initialization failed: $e');
  }

  var supabaseInitialized = false;
  try {
    await Supabase.initialize(
      url: resolvedBackend.supabaseUrl,
      publishableKey: resolvedBackend.anonKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: SharedPreferencesLocalStorage(
          persistSessionKey: AppConfig.supabaseAuthStorageKey,
        ),
      ),
      // Observe every backend request's outcome so ConnectivityService can tell
      // when the server is unreachable (weak signal / outage), not just when the
      // network interface is down.
      httpClient: HealthTrackingHttpClient(),
    ).timeout(const Duration(seconds: 2));
    supabaseInitialized = true;
    AppLogger.debug('Supabase initialized');
  } catch (e) {
    effectiveOffline = true;
    AppLogger.error('Supabase initialization failed: $e');
  }

  // Supabase exposes its client before asynchronous session recovery finishes.
  // Configure the canonical sync owner even when that recovery times out, so
  // an offline cold start can still activate the persisted public generation.
  try {
    final syncEndpoints = await ClientSyncEndpointService().resolve();
    ClientSyncRuntime.configure(
      Supabase.instance.client,
      onLastSuccess: OfflineDataService.saveLastSyncedAt,
      publicHeadOrigin: syncEndpoints.headOrigin,
      publicAssetOrigin: syncEndpoints.assetOrigin,
    );
    if (supabaseInitialized && !effectiveOffline) {
      if (AuthService.isLoggedIn()) {
        await AuthService.refreshSession().timeout(const Duration(seconds: 2));
        AppLogger.debug('Session refreshed');
      } else {
        await AuthService.tryAuthUser().timeout(const Duration(seconds: 2));
        AppLogger.debug('Stored session recovery completed');
      }
      if (AuthService.isLoggedIn()) {
        await AuthService.validateCurrentOrganization()
            .timeout(const Duration(seconds: 2));
      }
    } else {
      AppLogger.debug('Offline start: skipped remote session validation');
    }
  } catch (e) {
    effectiveOffline = shouldEnterOfflineAfterSessionInitializationFailure(
      wasAlreadyOffline: effectiveOffline,
      supabaseInitialized: supabaseInitialized,
    );
    AppLogger.error('Client sync initialization failed: $e');
  }

  try {
    await TimeHelper.initializeTimeZone().timeout(const Duration(seconds: 2));
    AppLogger.debug('Tz setup completed');
  } catch (e) {
    AppLogger.error('Tz setup failed: $e');
  }

  try {
    final cachedSyncModel = allowPersistedOccasionData
        ? await ClientSyncRuntime.restoreLastContext()
        : null;
    if (cachedSyncModel != null) {
      AppLogger.debug('Restored cached client sync context');
    }
    var settings = allowPersistedOccasionData
        ? await OfflineDataService.getGlobalSettings()
        : null;
    if (settings != null) {
      hasCachedOccasionSettings = true;
      SynchroService.globalSettingsModel = settings;
      final cachedUser = AuthService.isLoggedIn()
          ? await OfflineDataService.getUserInfo()
          : null;
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          code: 200,
          clientSyncV1: cachedSyncModel != null,
          userInfo: cachedUser,
          occasionUser: cachedUser?.occasionUser,
          occasion: OccasionModel(
              id: cachedSyncModel?.occasion?.id,
              link: cachedSyncModel?.occasion?.link,
              organization: cachedSyncModel?.occasion?.organization,
              features: settings.features,
              isOpen: true,
              isHidden: false,
              isPromoted: false,
              data: settings.data,
              services: settings.services));
      TimeHelper.setTimeZoneLocation(
          RightsService.currentOccasion()?.data?["timezone"]);
      final cachedLink =
          AppConfig.forceOccasionLink ?? cachedSyncModel?.occasion?.link;
      if (cachedLink != null) {
        RightsService.currentLink = cachedLink;
        RouterService.currentOccasionLink = cachedLink;
      }
      AppLogger.debug('Global settings loaded');
    }
  } catch (e) {
    AppLogger.error('Offline data helper initialization failed: $e');
  }

  try {
    // Tabs own their existing online/cache refresh flow. Blocking first paint
    // on a serial refresh of every offline bundle leaves the app blank when
    // any backend endpoint is slow.
    if (effectiveOffline) {
      RightsService.useOfflineVersion = true;
      AppLogger.debug('Offline start: using cached occasion data');
    } else {
      await RightsService.updateAppData(force: true, refreshOffline: false)
          .timeout(occasionLoadTimeout(
        hasCachedSettings: hasCachedOccasionSettings,
      ));
      AppLogger.debug('Occasion loaded');
      if (AuthService.isLoggedIn() && !ClientSyncRuntime.isV1Selected) {
        unawaited(SynchroService.refreshUserOfflineData().then((_) {
          AppLogger.debug('Private offline snapshot refreshed');
        }, onError: (Object error) {
          AppLogger.error('Private offline snapshot refresh failed: $error');
        }));
      }
    }
  } catch (e) {
    AppLogger.error('Occasion loading failed: $e');
    RightsService.useOfflineVersion = true;
  }

  AppLogger.debug('Notification helper initializing');

  if (_notificationReconnectCoordinator == null) {
    final reconnect = NotificationReconnectCoordinator(
      startsOffline: effectiveOffline,
      initialize: NotificationHelper.initialize,
    );
    _notificationReconnectCoordinator = reconnect;
    ConnectivityService.isOfflineNotifier.addListener(() {
      unawaited(reconnect
          .connectivityChanged(ConnectivityService.isOfflineNotifier.value)
          .catchError((Object error) {
        AppLogger.error('Notification reconnect initialization failed: $error');
      }));
    });
  }
  NotificationHelper.initialize().then((_) {
    AppLogger.debug('Notification helper initialized');
  }, onError: (Object error) {
    AppLogger.error('Notification helper initialization failed: $error');
  });

  AppLogger.debug('Initialization completed');

  WebStylesHelper.setBodyBackgroundColor(ThemeConfig.appBarColor());
  WebStylesHelper.setMetaThemeColor(ThemeConfig.seed1);
}

class MyApp extends StatefulWidget {
  final String initialRoute;
  bool isTimeTravelVisible = false;

  MyApp({required this.initialRoute, super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Offset _offset = Offset.zero;

  DeepLink _resolveDeepLink(PlatformDeepLink platformDeepLink) {
    if (platformDeepLink.initial) {
      return DeepLink.path(
        widget.initialRoute,
        includePrefixMatches: false,
      );
    }
    return platformDeepLink;
  }

  /// Ctrl+F opens Global Search when the feature is enabled. Uses the root
  /// navigator's context because the shortcut lives above the Navigator.
  void _openGlobalSearch() {
    if (!FeatureService.isFeatureEnabled(FeatureConstants.globalSearch)) {
      return;
    }
    final context = RouterService.router.navigatorKey.currentContext;
    if (context == null) return;
    GlobalSearchDialog.show(context);
  }

  @override
  Widget build(BuildContext context) {
    TimeHelper.toggleTimeTravel = () {
      setState(() {
        widget.isTimeTravelVisible = !widget.isTimeTravelVisible;
      });
    };

    var baseTheme = ThemeConfig.baseTheme();
    return AdaptiveTheme(
      light: ThemeConfig.baseTheme(),
      dark: ThemeConfig.isDarkModeEnabled
          ? ThemeConfig.darkTheme(baseTheme)
          : baseTheme,
      initial: ThemeConfig.defaultThemeMode,
      builder: (theme, darkTheme) => MaterialApp.router(
        routerConfig: RouterService.router.config(
          deepLinkBuilder: _resolveDeepLink,
          navigatorObservers: () => [RoutingObserver()],
        ),
        debugShowCheckedModeBanner: false,
        builder: (context, child) {
          return CallbackShortcuts(
            bindings: {
              // Ctrl+F on Windows/Linux, Cmd+F on macOS (Command maps to meta,
              // not control) — bind both so global search opens on every OS.
              const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                  _openGlobalSearch,
              const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                  _openGlobalSearch,
            },
            child: Stack(
              children: [
                child!,
                Positioned(
                  left: _offset.dx,
                  top: _offset.dy,
                  child: GestureDetector(
                    onPanUpdate: (d) => setState(
                        () => _offset += Offset(d.delta.dx, d.delta.dy)),
                    child: Visibility(
                      visible: widget.isTimeTravelVisible,
                      child: TimeTravelWidget(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        localizationsDelegates: [
          ...context.localizationDelegates,
          FormBuilderLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        title: OccasionHomePage.homePageTitle,
        theme: theme,
        darkTheme: darkTheme,
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/features/map_feature.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/components/map/map_page_helper.dart';
import 'package:fstapp/components/map/counseling_hours_panel.dart';
import 'package:fstapp/components/map/map_path_direction_layout.dart';
import 'package:fstapp/components/map/map_location_accuracy.dart';
import 'package:fstapp/components/map/map_locate_coordinator.dart';
import 'package:fstapp/components/map/map_offscreen_location_indicator.dart';
import 'package:fstapp/components/map/map_scene.dart';
import 'package:fstapp/components/map/public_map_host.dart';
import 'package:fstapp/components/map/public_map_session.dart';
import 'package:fstapp/components/map/map_viewport_controller.dart';
import 'package:fstapp/components/map/map_renderer_host.dart';
import 'package:fstapp/components/map/map_renderer_benchmark_override.dart';
import 'package:fstapp/components/map/maplibre/maplibre_style_assembler.dart';
import 'package:fstapp/components/map/maplibre/maplibre_style_load_guard.dart';
import 'package:fstapp/components/map/offline_map_bundle_manager.dart';
import 'package:fstapp/components/map/offline_map_bundle_manifest.dart';
import 'package:fstapp/components/map/offline_map_configuration.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';
import 'package:fstapp/components/timeline/schedule_timeline.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/widgets/detail_dialog.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/map/map_description_popup.dart';
import 'package:fstapp/components/map/map_download_indicator.dart';
import 'package:fstapp/components/cleaning/cleaning_status.dart';
import 'package:fstapp/components/cleaning/db_cleaning.dart';
import 'package:fstapp/components/cleaning/cleaning_report_flow.dart';
import 'package:fstapp/components/cleaning/models/cleaning_place_status.dart';
import 'package:fstapp/components/map/map_place_model.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/components/icons/icons_strings.dart';
import 'package:fstapp/components/icons/place_type_model.dart';
import 'package:fstapp/components/icons/db_place_types.dart';
import 'package:fstapp/components/map/path_group_model.dart';
import 'package:fstapp/components/map/path_node.dart';
import 'package:fstapp/components/map/gpx_importer.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/widgets/drop_file.dart';
import 'package:cross_file/cross_file.dart';
import 'package:fstapp/data_services/data_extensions.dart';
import 'package:fstapp/components/groups/db_groups.dart';
import 'package:fstapp/components/map/db_places.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'place_model.dart';
import 'package:fstapp/services/platform_helper.dart';
import 'package:fstapp/services/responsive_service.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/map/offline_map_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/pop_button.dart';
import 'package:collection/collection.dart';
import 'package:latlong2/latlong.dart';
import 'package:fstapp/components/map/map_strings.dart';
import 'package:fstapp/components/map/external_map_navigation.dart';
import 'package:fstapp/components/map/ios_navigation_app_picker.dart';
import 'package:fstapp/services/launch_url_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';

import '../schedule/event_page.dart';
import '../speakers/counseling_page.dart';

sealed class MapEditorMode {
  const MapEditorMode();
}

final class PlaceMapEditorMode extends MapEditorMode {
  final PlaceModel place;

  const PlaceMapEditorMode(this.place);
}

final class PathMapEditorMode extends MapEditorMode {
  final PathGroupsModel pathGroup;

  const PathMapEditorMode(this.pathGroup);
}

@RoutePage()
class PublicMapPage extends StatelessWidget {
  static const overviewDestination = 'overview';

  final String destination;
  final String? placeType;

  const PublicMapPage({
    @PathParam('destination') this.destination = 'overview',
    @QueryParam('placeType') this.placeType,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final placeId = int.tryParse(destination);
    return _PublicMapHostPage(
      intent: placeId != null
          ? MapPlaceIntent(placeId)
          : placeType != null && placeType!.isNotEmpty
              ? MapCategoryIntent(placeType!)
              : null,
    );
  }
}

class _PublicMapHostPage extends StatelessWidget {
  final MapIntent? intent;

  const _PublicMapHostPage({this.intent});

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const MapPage(key: ValueKey('occasion-public-map-host')),
          if (intent != null) _PublicMapIntentAdapter(intent: intent),
        ],
      );
}

class _PublicMapIntentAdapter extends StatefulWidget {
  final MapIntent? intent;

  const _PublicMapIntentAdapter({this.intent});

  @override
  State<_PublicMapIntentAdapter> createState() =>
      _PublicMapIntentAdapterState();
}

class _PublicMapIntentAdapterState extends State<_PublicMapIntentAdapter> {
  MapIntent? _publishedIntent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final intent = widget.intent;
    if (intent == null || intent == _publishedIntent) return;
    _publishedIntent = intent;
    final session = PublicMapSessionScope.read(context);
    scheduleMicrotask(() {
      if (mounted && identical(_publishedIntent, intent)) {
        session?.acceptExternalIntent(intent);
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

@RoutePage()
class MapEditorPage extends StatelessWidget {
  final MapEditorMode mode;

  const MapEditorPage({required this.mode, super.key});

  @override
  Widget build(BuildContext context) => switch (mode) {
        PlaceMapEditorMode(:final place) => MapPage(place: place),
        PathMapEditorMode(:final pathGroup) =>
          MapPage(editPathGroup: pathGroup),
      };
}

class MapPage extends StatefulWidget {
  // Kept for compatibility with the repository-wide route naming convention.
  // ignore: constant_identifier_names
  static const ROUTE = "map";
  final PlaceModel? place;

  /// When set, the map opens in path-drawing mode for this group: tapping
  /// existing place markers appends place-ref nodes, tapping empty map appends
  /// free-point nodes, and Save returns the drawn path as a CSV string.
  final PathGroupsModel? editPathGroup;

  const MapPage({
    this.place,
    this.editPathGroup,
    super.key,
  });

  /// True while the map is in path-drawing mode. The occasion shell listens to
  /// this to hide its bottom navigation bar during editing.
  static final ValueNotifier<bool> isEditingNotifier = ValueNotifier(false);

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage>
    with TickerProviderStateMixin
    implements PublicMapHost {
  // Paths stay hidden until the user selects a group; nothing is drawn by default.
  static const bool _showAllPathsWhenNoGroupSelected = false;
  final MapViewportCoordinator _viewportController = MapViewportCoordinator();
  late final MapLocateCoordinator _locateCoordinator;

  List<IconModel> _icons = [];
  // Derived cleaning status + rating aggregate per toilet place id (empty unless
  // the cleaning feature is enabled). Colors the toilet pins for everyone.
  Map<int, CleaningPlaceStatus> _cleaningByPlace = {};
  Map<int, List<CounselingHoursRange>> _counselingHoursByPlace = {};
  final List<MapPlacePresentation> _places = [];
  final List<MapPlacePresentation> _selectedPlaces = [];
  MapPlacePresentation? focusedPlace;
  MapPlacePresentation? selectedPlace;

  List<PathGroupsModel> _pathGroups = [];
  Map<int, List<MapPathPresentation>> _allGroupPaths = {};
  int? _selectedGroupId;

  List<MapPathPresentation> _paths = [];
  double? _directionZoom;

  String pageTitle = AppConfig.mapTitle;
  bool isOnlyEditMode = false;

  LatLng? _mapCenter;
  late final MapFeature _mapFeature;
  bool _dependenciesInitialized = false;

  bool _useOffline = false;
  MapDownloadState _downloadState = const MapDownloadIdle();
  String? _offlinePackagePath;
  LegacyMapConfiguration? _legacyOfflineConfiguration;
  String? _mapLibreStyle;
  String? _offlineMapError;
  final MapLibreStyleRecoveryCoordinator _mapLibreRecovery =
      MapLibreStyleRecoveryCoordinator();
  int _mapLibreSurfaceGeneration = 0;
  int? _popupPlaceId;

  late final ScrollController _iconScrollController;

  bool _isMapTabActive = false;
  StreamSubscription<Position>? _userLocationSubscription;
  Future<void>? _userLocationCancellation;
  final ValueNotifier<LatLng?> _currentUserLocation = ValueNotifier(null);
  PublicMapSession? _mapSession;
  int _catalogEpoch = 0;
  bool _catalogFinal = false;
  Future<void>? _presentationFuture;
  int _publicMapEffectToken = 0;
  bool _isShowingGroupsInEditMode = false;

  /// Visible place types (categories) shown as the bottom filter bar. Loaded
  /// from the occasion; hidden types are excluded from the chips but their
  /// places fall into the trailing "Other" bucket.
  List<PlaceTypeModel> _placeTypes = [];

  /// Sentinel code for the trailing "Other" filter chip (untyped places and
  /// places whose type is not among the visible chips).
  static const String _otherPlaceTypeCode = "__other__";

  /// Currently selected place-type filter (a type `code`, [_otherPlaceTypeCode],
  /// or null while no types are loaded). Single-select.
  String? _selectedPlaceTypeCode;
  bool _placeTypeInitialized = false;
  String? _placeTypeSelectionFeedback;
  Timer? _placeTypeSelectionFeedbackTimer;

  /// Deep-link place-type filter (from `map?placeType=…`). When set it wins over
  /// the saved/default selection and filters even if that code is not a catalog
  /// place_type chip (e.g. toilets marked only via the "WC" checkbox).
  String? _deepLinkPlaceType;

  /// True once we know the place-type situation authoritatively enough to filter
  /// without flashing: either cached types were loaded (offline) or the online
  /// load finished. Until then the default marker view is held back so an empty
  /// offline type cache can't briefly paint *every* place unfiltered before the
  /// category filter kicks in.
  bool _placeTypesResolved = false;

  /// Place we were deep-linked to (e.g. from a user's accommodation link). It
  /// must stay visible on the map regardless of the active category filter.
  int? _forcedVisiblePlaceId;

  /// Working copy of the path being drawn (mode active when
  /// `widget.editPathGroup != null`). Each inner list is a segment of nodes.
  final List<List<PathNode>> _drawSegments = [];

  bool get _isDrawingPath => widget.editPathGroup != null;

  @override
  void initState() {
    super.initState();
    _isMapTabActive = _isDrawingPath || widget.place != null;
    _useOffline = kIsWeb && ConnectivityService.isOfflineNotifier.value;
    _locateCoordinator = MapLocateCoordinator(viewport: _viewportController);
    ConnectivityService.isOfflineNotifier.addListener(_onConnectivityChanged);
    _iconScrollController = ScrollController();
  }

  @override
  void dispose() {
    ConnectivityService.isOfflineNotifier
        .removeListener(_onConnectivityChanged);
    final session = _mapSession;
    session?.detachHost(this);
    if (_isDrawingPath) {
      MapPage.isEditingNotifier.value = false;
    }
    _iconScrollController.dispose();
    _placeTypeSelectionFeedbackTimer?.cancel();
    unawaited(_userLocationSubscription?.cancel());
    _currentUserLocation.dispose();
    _legacyOfflineConfiguration?.dispose();
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (!mounted || !_dependenciesInitialized) return;
    final isOffline = ConnectivityService.isOfflineNotifier.value;
    if (kIsWeb) {
      // Web has no native offline renderer. A transient connectivity result
      // must not swap the online Legacy surface for an empty offline base;
      // network tiles fail naturally while cached places and paths stay usable.
      if (_useOffline) setState(() => _useOffline = false);
      return;
    }
    if (isOffline) {
      unawaited(_initOfflineMap());
    } else if (!_offlineConfiguration.forceOffline) {
      setState(() => _useOffline = false);
    }
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    final mapSession = !_isDrawingPath && widget.place == null
        ? PublicMapSessionScope.watch(context)
        : null;
    if (!identical(mapSession, _mapSession)) {
      _mapSession?.detachHost(this);
      _mapSession = mapSession;
      _mapSession?.attachHost(this);
    }
    final active =
        mapSession?.isMapVisible ?? (_isDrawingPath || widget.place != null);
    if (_isMapTabActive != active) {
      _isMapTabActive = active;
      _publicMapEffectToken++;
      scheduleMicrotask(() {
        if (mounted && identical(_mapSession, mapSession)) {
          mapSession?.hostChanged();
        }
      });
    }
    _syncUserLocationTracking();
    // Inherited-widget changes may invoke this lifecycle more than once (for
    // example when Android finishes localization/startup). Map initialization
    // owns controllers, downloads, listeners and a late-final feature snapshot,
    // so it must only start once for this page instance.
    if (_dependenciesInitialized) return;
    _dependenciesInitialized = true;

    // Hide the occasion shell's bottom navigation bar while drawing a path.
    // Deferred to after the frame so we never notify listeners mid-build.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => MapPage.isEditingNotifier.value = _isDrawingPath);

    final feature = FeatureService.getFeatureDetails(FeatureConstants.map);
    final hasAuthoritativeMapConfiguration = feature is MapFeature;
    _mapFeature = (feature == null || feature is! MapFeature)
        ? MapFeature.getDefault()
        : feature;
    _mapCenter = widget.place != null
        ? LatLng(widget.place!.getLat(), widget.place!.getLng())
        : LatLng(
            _mapFeature.defaultMapLocation.lat,
            _mapFeature.defaultMapLocation.lng,
          );
    final offlineConfiguration = _offlineConfiguration;
    _useOffline = offlineConfiguration.useOfflineWhileConnectivityLoads(
      isKnownOffline: ConnectivityService.isOfflineNotifier.value,
      hasAuthoritativeConfiguration: hasAuthoritativeMapConfiguration,
      isWeb: kIsWeb,
    );
    if (!PlatformHelper.isWeb && offlineConfiguration.shouldInitialize) {
      // Renderer selection must be correct before the first await. Otherwise a
      // forced/offline MapLibre page briefly builds the online Legacy surface,
      // which starts tile and attribution-logo requests that can outlive it.
      // Preparing the base-map bundle must not block cached place content. A
      // deep-linked place can open while MapLibre finishes underneath it.
      unawaited(_initOfflineMap());
    }

    selectedPlace = null;

    if (_isDrawingPath) {
      // Seed the working path from the group being edited (deep copy so undo /
      // cancel never mutate the caller's model).
      _drawSegments
        ..clear()
        ..addAll((widget.editPathGroup!.pathData ?? [])
            .map((seg) => List<PathNode>.from(seg)));
      pageTitle = widget.editPathGroup!.title ?? MapStrings.drawPath;
    }

    var placeModel = widget.place;
    if (placeModel == null || placeModel.latLng == null) {
      await loadData();
    } else {
      if (placeModel.latLng.toString().isEmpty) {
        placeModel.latLng = {
          "lat": _mapFeature.defaultMapLocation.lat,
          "lng": _mapFeature.defaultMapLocation.lng
        };
      }
      pageTitle = placeModel.title ?? AppConfig.mapTitle;
      addPlacesToMap([placeModel]);
      if (_places.isNotEmpty) runEditPositionMode(_places.single);
      isOnlyEditMode = true;
    }
  }

  Future<void> _initOfflineMap() async {
    final configuration = _offlineConfiguration;
    final hasConnection = await _hasNetworkConnection();
    final startup = configuration.resolveStartup(
      hasConnection: hasConnection,
    );
    if (!mounted) return;

    late final OfflineMapContract? contract;
    late final bool useOffline;
    switch (startup) {
      case InvalidOfflineMapStartup():
        setState(() {
          _useOffline = true;
          _offlineMapError = MapStrings.offlineMapConfigurationIncomplete;
        });
        return;
      case ReadyOfflineMapStartup(contract: final selected):
        contract = selected;
        useOffline = true;
        break;
      case OnlineMapStartup(:final availableOfflineContract):
        contract = availableOfflineContract;
        useOffline = false;
        break;
    }
    if (_offlineMapError != null) {
      setState(() => _offlineMapError = null);
    }

    setState(() => _useOffline = useOffline);
    if (useOffline && contract != null) {
      await _prepareOfflineMap(
        contract,
        allowDownload: hasConnection,
      );
    }
  }

  void _syncUserLocationTracking() {
    if (!_isMapTabActive) {
      final subscription = _userLocationSubscription;
      _userLocationSubscription = null;
      if (subscription != null) {
        final cancellation = subscription.cancel();
        _userLocationCancellation = cancellation;
        unawaited(cancellation.whenComplete(() {
          if (identical(_userLocationCancellation, cancellation)) {
            _userLocationCancellation = null;
          }
          if (mounted && _isMapTabActive) _syncUserLocationTracking();
        }));
      }
      return;
    }
    if (_userLocationSubscription != null ||
        _userLocationCancellation != null) {
      return;
    }
    late final StreamSubscription<Position> subscription;
    subscription = MapLocationAccuracy.positionStream().listen(
      (position) {
        if (!mounted || !_isMapTabActive) return;
        _currentUserLocation.value = LatLng(
          position.latitude,
          position.longitude,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error('Map location tracking failed: $error\n$stackTrace');
        if (mounted) _currentUserLocation.value = null;
      },
      onDone: () {
        if (!identical(_userLocationSubscription, subscription)) return;
        _userLocationSubscription = null;
        if (mounted) _currentUserLocation.value = null;
      },
    );
    _userLocationSubscription = subscription;
  }

  Future<bool> _hasNetworkConnection() async {
    final connectivity = await Connectivity().checkConnectivity();
    return connectivity.isNotEmpty &&
        !connectivity.contains(ConnectivityResult.none);
  }

  Future<bool> _downloadOfflinePackage({bool forceRefresh = false}) async {
    if (!mounted) return false;
    final contract = _offlineConfiguration.selectedContract;
    if (contract == null) return false;
    return _prepareOfflineMap(contract, forceRefresh: forceRefresh);
  }

  Future<void> _recoverMapLibreStyleLoad() async {
    if (!mounted) return;
    switch (_mapLibreRecovery.beginRecovery()) {
      case MapLibreRecoveryDecision.ignore:
        return;
      case MapLibreRecoveryDecision.showFailure:
        setState(() {
          _mapLibreStyle = null;
          _offlineMapError = MapStrings.mapLibreBundleDownloadFailed;
        });
        return;
      case MapLibreRecoveryDecision.refreshBundle:
        setState(() {
          _mapLibreStyle = null;
          _offlineMapError = null;
          _mapLibreSurfaceGeneration++;
        });
        final recovered = await _downloadOfflinePackage(forceRefresh: true);
        _mapLibreRecovery.finishRecovery();
        if (!mounted || recovered) return;
        setState(() {
          _mapLibreStyle = null;
          _offlineMapError = MapStrings.mapLibreBundleDownloadFailed;
        });
    }
  }

  Future<void> _retryMapLibreBundle() async {
    _mapLibreRecovery.resetForManualRetry();
    setState(() => _mapLibreSurfaceGeneration++);
    await _downloadOfflinePackage(forceRefresh: true);
  }

  Future<bool> _prepareOfflineMap(
    OfflineMapContract contract, {
    bool allowDownload = true,
    bool forceRefresh = false,
  }) =>
      switch (contract) {
        final MapLibreOfflineMapContract mapLibre => _downloadMapLibreBundle(
            mapLibre,
            allowDownload: allowDownload,
            forceRefresh: forceRefresh,
          ),
        final LegacyOfflineMapContract legacy => _downloadLegacyBundle(
            legacy,
            _offlineConfiguration.bundleFor(legacy),
            allowDownload: allowDownload,
            forceRefresh: forceRefresh,
          ),
      };

  void _showOfflineDownloadComplete(MapDownloadCompleted completedState) {
    ToastHelper.Show(context, MapStrings.offlineMapReady);
    Timer(const Duration(seconds: 2), () {
      if (!mounted || !identical(_downloadState, completedState)) return;
      setState(() => _downloadState = const MapDownloadIdle());
    });
  }

  Future<bool> _downloadMapLibreBundle(
    MapLibreOfflineMapContract? selectedContract, {
    bool allowDownload = true,
    bool forceRefresh = false,
  }) async {
    if (!mounted) return false;
    final contract = selectedContract ??
        switch (_offlineConfiguration.selectedContract) {
          final MapLibreOfflineMapContract mapLibre => mapLibre,
          _ => null,
        };
    if (contract == null) {
      setState(
          () => _offlineMapError = MapStrings.mapLibreManifestNotConfigured);
      return false;
    }
    setState(() {
      _downloadState = const MapDownloadCheckingCache();
      _offlineMapError = null;
    });
    var downloadRequired = false;
    final assembledStyle = await ExceptionHandler.guard<String>(
      context,
      defaultErrorMessage: MapStrings.mapLibreBundleDownloadFailed,
      futureFunction: () async {
        final installation = await _installSharedBundle(
          contract,
          allowDownload: allowDownload,
          forceRefresh: forceRefresh,
          onDownloadRequired: () {
            downloadRequired = true;
            if (mounted) {
              setState(() => _downloadState = const MapDownloading(0));
            }
          },
          onProgress: (progress) {
            if (mounted) {
              setState(
                () => _downloadState = MapDownloading(progress.fraction),
              );
            }
          },
        );
        final styleAsset =
            installation.manifest.assetFor(OfflineMapAssetRole.style);
        final sourceStyle = await File(
          '${installation.directory.path}/${styleAsset.path}',
        ).readAsString();
        return MapLibreStyleAssembler.assemble(
          sourceStyleJson: sourceStyle,
          installation: installation,
        );
      },
    );
    if (!mounted) return false;
    if (assembledStyle == null) {
      setState(() {
        _downloadState = const MapDownloadIdle();
        _offlineMapError = MapStrings.mapLibreBundleDownloadFailed;
      });
      return false;
    }
    final completedState = downloadRequired ? MapDownloadCompleted() : null;
    setState(() {
      _mapLibreStyle = assembledStyle;
      _downloadState = completedState ?? const MapDownloadIdle();
      _useOffline = true;
    });
    if (downloadRequired) {
      _showOfflineDownloadComplete(completedState!);
    }
    return true;
  }

  Future<bool> _downloadLegacyBundle(
    LegacyOfflineMapContract legacy,
    MapLibreOfflineMapContract? sharedBundle, {
    bool allowDownload = true,
    bool forceRefresh = false,
  }) async {
    if (!mounted) return false;
    setState(() {
      _downloadState = const MapDownloadCheckingCache();
      _offlineMapError = null;
    });
    var downloadRequired = false;
    final openedConfiguration =
        await ExceptionHandler.guard<LegacyMapConfiguration>(
      context,
      defaultErrorMessage: MapStrings.legacyMapOpenFailed,
      futureFunction: () async {
        if (sharedBundle != null) {
          final installation = await _installSharedBundle(
            sharedBundle,
            allowDownload: allowDownload,
            forceRefresh: forceRefresh,
            onDownloadRequired: () {
              downloadRequired = true;
              if (mounted) {
                setState(() => _downloadState = const MapDownloading(0));
              }
            },
            onProgress: (progress) {
              if (mounted) {
                setState(
                  () => _downloadState = MapDownloading(progress.fraction),
                );
              }
            },
          );
          return LegacyMapConfiguration.openOfflineBundle(
            layer: _mapFeature.offlineMapLayer,
            contract: legacy,
            installation: installation,
          );
        }
        downloadRequired = forceRefresh;
        return _openStandaloneLegacyMap(
          legacy,
          allowDownload: allowDownload,
          forceRefresh: forceRefresh,
          onDownloadRequired: () {
            downloadRequired = true;
            if (mounted) {
              setState(() => _downloadState = const MapDownloading(0));
            }
          },
        );
      },
    );
    if (!mounted) {
      openedConfiguration?.dispose();
      return false;
    }
    if (openedConfiguration == null) {
      setState(() {
        _downloadState = const MapDownloadIdle();
        _offlineMapError = MapStrings.legacyMapOpenFailed;
      });
      return false;
    }
    _legacyOfflineConfiguration?.dispose();
    _legacyOfflineConfiguration = openedConfiguration;
    final completedState = downloadRequired ? MapDownloadCompleted() : null;
    setState(() {
      _downloadState = completedState ?? const MapDownloadIdle();
      _useOffline = true;
    });
    if (downloadRequired) {
      _showOfflineDownloadComplete(completedState!);
    }
    return true;
  }

  Future<LegacyMapConfiguration> _openStandaloneLegacyMap(
    LegacyOfflineMapContract contract, {
    required bool allowDownload,
    required bool forceRefresh,
    required VoidCallback onDownloadRequired,
  }) async {
    _offlinePackagePath ??=
        await OfflineMapHelper.getOfflinePackagePath(contract.packageUrl);
    final stylePath =
        await OfflineMapHelper.getOfflineStyleFilePath(contract.styleUrl);

    Future<LegacyMapConfiguration> open({required bool refresh}) async {
      final packageExists = await File(_offlinePackagePath!).exists();
      final styleExists = await File(stylePath).exists();
      if (allowDownload && (refresh || !packageExists || !styleExists)) {
        onDownloadRequired();
      }
      final package = await OfflineMapHelper.getOfflineMapPackage(
        contract.packageUrl,
        _offlinePackagePath!,
        (progress) {
          if (mounted) {
            setState(() => _downloadState = MapDownloading(progress));
          }
        },
        forceRefresh: refresh,
        allowDownload: allowDownload,
      );
      final style = await OfflineMapHelper.getOrDownloadFile(
        contract.styleUrl,
        stylePath,
        (_) {},
        forceRefresh: refresh,
        allowDownload: allowDownload,
      );
      if (package == null || style == null) {
        throw OfflineMapBundleException(
          'No downloaded Legacy offline map is available.',
        );
      }
      return LegacyMapConfiguration.openOffline(
        layer: _mapFeature.offlineMapLayer,
        contract: contract,
        mbtilesPath: _offlinePackagePath!,
      );
    }

    try {
      return await open(refresh: forceRefresh);
    } catch (_) {
      if (!allowDownload || forceRefresh) rethrow;
      return open(refresh: true);
    }
  }

  Future<OfflineMapBundleInstallation> _installSharedBundle(
    MapLibreOfflineMapContract contract, {
    bool allowDownload = true,
    bool forceRefresh = false,
    VoidCallback? onDownloadRequired,
    void Function(OfflineMapBundleProgress progress)? onProgress,
  }) async {
    final appSupport = await getApplicationSupportDirectory();
    final manager = OfflineMapBundleManager(
      // Keep the original directory name as the stable on-device cache
      // contract. The bundle is now shared by MapLibre and Legacy, but moving
      // it would force every existing installation to download it again.
      rootDirectory: Directory('${appSupport.path}/maplibre-bundles'),
    );
    final manifestUri = Uri.parse(contract.manifestUrl);
    try {
      if (!allowDownload) {
        final cached = await manager.openCached(manifestUri);
        if (cached == null) {
          throw OfflineMapBundleException(
            'No downloaded offline map bundle is available.',
          );
        }
        return cached;
      }
      final install = forceRefresh ? manager.update : manager.install;
      return await install(
        manifestUri,
        onDownloadRequired: onDownloadRequired,
        onProgress: onProgress,
      );
    } finally {
      manager.close();
    }
  }

  @override
  PublicMapHostSnapshot get snapshot {
    final renderObject = mounted ? context.findRenderObject() : null;
    final size = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.size
        : null;
    return PublicMapHostSnapshot(
      surfaceId: _viewportController.surfaceId,
      styleEpoch: Object.hash(
        _useOffline,
        _mapLibreStyle,
        _legacyOfflineConfiguration?.sourceName,
      ),
      readinessEpoch: _viewportController.readinessEpoch,
      catalogEpoch: _catalogEpoch,
      activeLayoutReady: _isMapTabActive &&
          _viewportController.isReady &&
          size != null &&
          size.width > 0 &&
          size.height > 0 &&
          _catalogEpoch > 0,
    );
  }

  @override
  Future<PublicMapHostResult> applyIntent(PublicMapEffect effect) async {
    if (!mounted ||
        !_isMapTabActive ||
        effect.snapshot.surfaceId != _viewportController.surfaceId ||
        !_viewportController.isReady) {
      return PublicMapHostResult.retryable('hostNotReady');
    }
    final effectToken = ++_publicMapEffectToken;

    switch (effect.intent) {
      case MapCategoryIntent(:final placeType):
        setState(() {
          _deepLinkPlaceType = placeType;
          _selectedPlaceTypeCode = placeType;
          _placeTypeInitialized = true;
          _forcedVisiblePlaceId = null;
        });
        final current = _viewportController.camera;
        final command = CameraCommand(
          surfaceId: _viewportController.surfaceId,
          destination: current.center,
          zoom: current.zoom,
        );
        return PublicMapHostResult.applied(CameraApplyResult(
          status: CameraApplyStatus.applied,
          surfaceId: command.surfaceId,
          command: command,
          actual: current,
        ));
      case MapPlaceIntent(:final placeId):
        final marker =
            _places.firstWhereOrNull((item) => item.place.id == placeId);
        if (marker == null) {
          return _catalogFinal
              ? PublicMapHostResult.unavailable('placeNotInCatalog')
              : PublicMapHostResult.retryable('catalogRefreshing');
        }
        setState(() {
          _forcedVisiblePlaceId = placeId;
          _places
            ..remove(marker)
            ..add(marker);
        });
        final camera = await _viewportController.applyCamera(CameraCommand(
          surfaceId: effect.snapshot.surfaceId,
          destination: marker.point,
          zoom: 18,
        ));
        if (!camera.isApplied) {
          return camera.status == CameraApplyStatus.rejected
              ? PublicMapHostResult.failed(camera.reason)
              : PublicMapHostResult.retryable(
                  camera.reason ?? 'cameraNotApplied',
                );
        }
        if (!mounted ||
            !_isMapTabActive ||
            effectToken != _publicMapEffectToken ||
            effect.snapshot.surfaceId != _viewportController.surfaceId ||
            effect.snapshot.catalogEpoch != _catalogEpoch) {
          return PublicMapHostResult.retryable('effectBecameStale');
        }
        final presentation = _onPlaceTap(placeId);
        _presentationFuture = presentation;
        presentation.catchError((Object error, StackTrace stackTrace) {
          AppLogger.error('Map place presentation failed: $error\n$stackTrace');
        }).whenComplete(() {
          if (identical(_presentationFuture, presentation)) {
            _presentationFuture = null;
          }
        });
        return PublicMapHostResult.applied(camera);
    }
  }

  @override
  Future<void> resetToOverview() async {
    if (!mounted ||
        !_isMapTabActive ||
        _isDrawingPath ||
        widget.place != null) {
      return;
    }

    final resetToken = ++_publicMapEffectToken;
    _placeTypeSelectionFeedbackTimer?.cancel();
    final savedPlaceType = await OfflineDataService.getSelectedPlaceType();
    if (!mounted || !_isMapTabActive || resetToken != _publicMapEffectToken) {
      return;
    }

    setState(() {
      _deepLinkPlaceType = null;
      _forcedVisiblePlaceId = null;
      _popupPlaceId = null;
      _selectedGroupId = null;
      _paths = _showAllPathsWhenNoGroupSelected
          ? _allGroupPaths.values.expand((paths) => paths).toList()
          : [];
      _placeTypeSelectionFeedback = null;
      _selectedPlaceTypeCode = savedPlaceType;
      _placeTypeInitialized = savedPlaceType != null;
      _initPlaceTypeSelection();

      final focused = focusedPlace;
      if (focused != null) {
        final index = _places.indexWhere(
          (marker) => marker.place.id == focused.place.id,
        );
        if (index != -1) {
          _places[index] = _places[index].withFocus(false);
        }
        focusedPlace = null;
      }
    });

    final center = _mapCenter;
    if (center != null && _viewportController.isReady) {
      await _viewportController.animateTo(
        center,
        zoom: _mapFeature.defaultMapZoom,
      );
    }
  }

  Future<void> _closePublicMap() async {
    if (await _mapSession?.closeVisit() ?? false) return;
    if (!mounted) return;
    if (context.router.canNavigateBack) {
      context.router.back();
    } else {
      RouterService.popOrHome(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offlineConfiguration = _offlineConfiguration;
    final renderer = MapRendererHost.resolveRenderer(
      configuredRenderer: offlineConfiguration.renderer,
      isOffline: _useOffline,
      isWeb: kIsWeb,
    );
    final rendererAvailableForLocate = switch (renderer) {
      OfflineMapRenderer.legacy => !_useOffline || _offlineMapError == null,
      OfflineMapRenderer.maplibre => _mapLibreStyle != null,
    };
    Widget buildMapWidget(LatLng? currentLocation) => MapRendererHost(
          renderer: offlineConfiguration.renderer,
          isOffline: _useOffline,
          model: MapSurfaceModel(
            active: _isMapTabActive,
            scene: _buildMapScene(currentLocation: currentLocation),
            icons: _icons,
            initialCenter: _mapCenter!,
            initialZoom: _mapFeature.defaultMapZoom,
            viewport: _viewportController,
            onMapTap: onMapTap,
            onPlaceTap: _onPlaceTap,
            onPlaceLongPress: _onPlaceLongPress,
            onCameraReady: () {
              final wasReady = _viewportController.isReady;
              _viewportController.markReady();
              if (mounted && !wasReady) setState(() {});
              _mapSession?.hostChanged();
            },
            onCameraChanged: () {
              if (mounted &&
                  (_popupPlaceId != null ||
                      _currentUserLocation.value != null)) {
                setState(() {});
              }
            },
            onZoomChanged: _onZoomChanged,
          ),
          legacy: _useOffline
              ? (_legacyOfflineConfiguration ??
                  LegacyMapConfiguration.offlineUnavailable(
                    _mapFeature.offlineMapLayer,
                  ))
              : LegacyMapConfiguration.online(_mapFeature.onlineMapLayer),
          mapLibre: MapLibreMapConfiguration(
            style: _mapLibreStyle,
            unavailable: _buildMapLibreUnavailable(),
            surfaceGeneration: _mapLibreSurfaceGeneration,
            onStyleLoadTimeout: () => unawaited(_recoverMapLibreStyleLoad()),
            onStyleLoadSuccess: _mapLibreRecovery.markStyleLoaded,
          ),
        );
    final mapWidget = renderer == OfflineMapRenderer.legacy
        ? ValueListenableBuilder<LatLng?>(
            valueListenable: _currentUserLocation,
            builder: (context, location, child) => buildMapWidget(location),
          )
        : buildMapWidget(null);
    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitle,
            style: TextStyle(color: ThemeConfig.appBarColorNegative())),
        leading: PopButton(
          color: ThemeConfig.appBarColorNegative(),
          onPressed: !_isDrawingPath && widget.place == null
              ? () => unawaited(_closePublicMap())
              : null,
        ),
        actions: [
          if (!kIsWeb &&
              offlineConfiguration.selectedContract != null &&
              !offlineConfiguration.forceOffline)
            Row(
              children: [
                Icon(
                  _useOffline ? Icons.landscape : Icons.cloud,
                  color: Colors.grey,
                ),
                Switch(
                  onChanged: _downloadState.isBusy
                      ? null
                      : (value) async {
                          final currentCamera = _viewportController.camera;
                          if (value) {
                            setState(() => _useOffline = true);
                            final ready = await _downloadOfflinePackage();
                            if (mounted && !ready) {
                              setState(() => _useOffline = false);
                            }
                          } else {
                            setState(() => _useOffline = false);
                          }
                          if (!mounted) return;
                          _viewportController.animateTo(
                            currentCamera.center,
                            zoom: currentCamera.zoom,
                          );
                        },
                  value: _useOffline,
                  activeThumbColor: Colors.grey[600],
                  inactiveThumbColor: Colors.grey[400],
                  inactiveTrackColor: Colors.grey[300],
                  activeTrackColor: Colors.grey[600],
                ),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_mapCenter != null) mapWidget,
          if (renderer == OfflineMapRenderer.maplibre)
            _buildMapLibreAttribution(),
          if (renderer == OfflineMapRenderer.legacy &&
              _useOffline &&
              _offlineMapError != null)
            _buildLegacyOfflineUnavailable(),
          if (_popupPlaceId != null) _buildPlacePopup(),
          MapDownloadIndicator(
            state: _downloadState,
            useOffline: _useOffline,
          ),
          if (_isDrawingPath) _buildDrawControls(),
          if (!_isDrawingPath && selectedPlace != null) _buildEditControls(),
          if (!_isDrawingPath && selectedPlace == null)
            MapPageHelper.buildGroupIconArea(
              context,
              _pathGroups,
              _selectedGroupId,
              _onGroupIconTap,
              _icons,
              scrollController: _iconScrollController,
            ),
          if (!_isDrawingPath && selectedPlace == null)
            MapPageHelper.buildSelectedGroupTitle(
              context,
              _pathGroups.firstWhereOrNull((g) => g.id == _selectedGroupId),
            ),
          if (!_isDrawingPath && selectedPlace == null)
            MapPageHelper.buildPlaceTypeFilterBar(
              context,
              _placeTypes,
              _selectedPlaceTypeCode,
              _otherPlaceTypeCode,
              _onPlaceTypeTap,
              _icons,
              showOther: MapPageHelper.hasOtherVisiblePlaces(
                _places,
                _placeTypes,
              ),
            ),
          if (!_isDrawingPath && selectedPlace == null)
            MapPageHelper.buildPlaceTypeSelectionFeedback(
              context,
              _placeTypeSelectionFeedback,
            ),
          if (_isMapTabActive && rendererAvailableForLocate)
            ValueListenableBuilder<LatLng?>(
              valueListenable: _currentUserLocation,
              builder: (context, location, child) {
                final projectedLocation = _projectUserLocation(location);
                if (projectedLocation == null) {
                  return const SizedBox.shrink();
                }
                return MapOffscreenLocationIndicator(
                  projectedLocation: projectedLocation,
                  occupiedRectsBuilder: (viewport) =>
                      _locateOverlayOccupiedRects(context, renderer, viewport),
                  onPressed: () => unawaited(_recenterOnCurrentUser()),
                );
              },
            ),
        ],
      ),
    );
  }

  Offset? _projectUserLocation(LatLng? location) {
    if (location == null || !_viewportController.isReady) return null;
    try {
      return _viewportController.coordinateToScreenPoint(location);
    } catch (error) {
      // A renderer can be between surface detach and attach during a switch.
      AppLogger.warning('Map location projection unavailable: $error');
      return null;
    }
  }

  List<Rect> _locateOverlayOccupiedRects(
    BuildContext context,
    OfflineMapRenderer renderer,
    Size viewport,
  ) {
    final obstacles = <Rect>[];

    if (_isDrawingPath) {
      obstacles.add(
        Rect.fromLTRB(
            0, viewport.height - 176, viewport.width, viewport.height),
      );
    } else if (selectedPlace != null) {
      obstacles.add(Rect.fromLTWH(0, 0, viewport.width, 120));
    } else {
      if (_pathGroups.isNotEmpty) {
        if (ResponsiveService.isMobile(context)) {
          obstacles.add(Rect.fromLTWH(8, 8, viewport.width - 16, 104));
        } else {
          final height = math.min(
            viewport.height - 16,
            _pathGroups.length * 92.0 + 12,
          );
          obstacles.add(
            Rect.fromLTWH(viewport.width - 96, 8, 88, height),
          );
          obstacles.add(
            Rect.fromCenter(
              center: Offset(viewport.width / 2, 49),
              width: 200,
              height: 50,
            ),
          );
        }
      }
      if (_placeTypes.isNotEmpty) {
        final showOther = MapPageHelper.hasOtherVisiblePlaces(
          _places,
          _placeTypes,
        );
        final chipCount = _placeTypes.length + (showOther ? 1 : 0);
        final width = math.min(viewport.width - 24, chipCount * 38.0 + 12);
        obstacles.add(
          Rect.fromLTWH(
            (viewport.width - width) / 2,
            viewport.height - 62,
            width,
            46,
          ),
        );
      }
      if (_placeTypeSelectionFeedback?.isNotEmpty == true) {
        obstacles.add(
          Rect.fromLTWH(24, viewport.height - 108, viewport.width - 48, 36),
        );
      }
    }

    if (renderer == OfflineMapRenderer.maplibre) {
      obstacles.add(
        Rect.fromLTWH(viewport.width - 208, 8, 200, 28),
      );
    }
    if (!_useOffline &&
        (_downloadState is MapDownloading ||
            _downloadState is MapDownloadCompleted)) {
      obstacles.add(
        Rect.fromLTWH(viewport.width - 56, 16, 40, 40),
      );
    }

    if (_popupPlaceId != null && _viewportController.isAttached) {
      final marker = _places.firstWhereOrNull(
        (item) => item.place.id == _popupPlaceId,
      );
      if (marker != null) {
        final point = _viewportController.coordinateToScreenPoint(marker.point);
        final left = math.max(
          8.0,
          math.min(point.dx - 150, viewport.width - 308),
        );
        obstacles.add(
          Rect.fromLTWH(left, math.max(8.0, point.dy - 190), 300, 190),
        );
      }
    }

    return obstacles;
  }

  Future<void> _recenterOnCurrentUser() async {
    if (_locateCoordinator.isLocating) return;
    final operation = ExceptionHandler.guard<MapLocateResult>(
      context,
      defaultErrorMessage: MapStrings.currentLocationUnavailable,
      futureFunction: () => _locateCoordinator.recenter(
        isActive: () => mounted && _isMapTabActive,
        displayedLocation: _currentUserLocation.value,
      ),
    );
    if (mounted) setState(() {});
    final result = await operation;
    if (!mounted) return;
    setState(() {});
    if (result == MapLocateResult.denied) {
      await ToastHelper.Show(
        context,
        MapStrings.currentLocationUnavailable,
        severity: ToastSeverity.NotOk,
      );
    }
  }

  OfflineMapRenderer get _offlineRenderer =>
      MapRendererBenchmarkOverride.resolve(
        _mapFeature.offlineMapLayer.offlineMapRenderer,
      );

  OfflineMapConfiguration get _offlineConfiguration =>
      OfflineMapConfiguration.fromLayer(
        _mapFeature.offlineMapLayer,
        renderer: _offlineRenderer,
      );

  Widget _buildMapLibreUnavailable() {
    if (_downloadState.isBusy) {
      return const SizedBox.expand();
    }
    return Center(
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _offlineMapError ?? MapStrings.mapLibreNotDownloaded,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: ConnectivityService.isOfflineNotifier.value
                    ? null
                    : () => unawaited(
                          _retryMapLibreBundle(),
                        ),
                icon: const Icon(Icons.download),
                label: Text(MapStrings.downloadMapAgain),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegacyOfflineUnavailable() {
    return Positioned.fill(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _offlineMapError ??
                        MapStrings.offlineMapConfigurationIncomplete,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: ConnectivityService.isOfflineNotifier.value ||
                            _downloadState.isBusy
                        ? null
                        : () => unawaited(
                              _retryMapLibreBundle(),
                            ),
                    icon: const Icon(Icons.download),
                    label: Text(MapStrings.downloadMapAgain),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapLibreAttribution() {
    final layer = _mapFeature.offlineMapLayer;
    final text = layer.text?.isNotEmpty == true
        ? layer.text!
        : MapStrings.openStreetMapAttribution;
    final link = layer.textLink?.isNotEmpty == true ? layer.textLink : null;
    return Positioned(
      top: 8,
      right: 8,
      child: SafeArea(
        child: Material(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            onTap: link == null
                ? null
                : () => LaunchUrlService.openExternalUrl(link),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(text, style: const TextStyle(fontSize: 10)),
            ),
          ),
        ),
      ),
    );
  }

  MapScene _buildMapScene({required LatLng? currentLocation}) {
    return MapScene(
      places: _getDisplayedPlaces(),
      paths: _paths,
      directions: MapPathDirectionLayout.directions(
        _paths,
        zoom: _directionZoom ?? _mapFeature.defaultMapZoom,
      ),
      drawPoints: _drawSegments
          .expand((segment) => segment)
          .where((node) => node.isPoint)
          .map((node) => MapDrawPointPresentation(
                coordinate: LatLng(node.lat!, node.lng!),
                colorValue: _drawPathColor().toARGB32(),
              ))
          .toList(growable: false),
      showCurrentLocation: _isMapTabActive,
      currentLocation: currentLocation,
    );
  }

  void _onZoomChanged(double zoom) {
    final bucket = (zoom * 2).round() / 2;
    if (_directionZoom == bucket || !mounted) return;
    setState(() => _directionZoom = bucket);
  }

  Future<void> _onPlaceTap(int placeId) async {
    final marker = _places.firstWhereOrNull((item) => item.place.id == placeId);
    if (marker == null) return;
    if (_isDrawingPath) {
      _addDrawNode(PathNode.place(placeId));
      return;
    }
    final place = marker.place;
    final counselingHours =
        _counselingHoursByPlace[place.id] ?? const <CounselingHoursRange>[];
    final isToilet = place.type == CleaningStatusHelper.toiletPlaceTypeCode &&
        FeatureService.isFeatureEnabled(FeatureConstants.cleaning);
    final hasLongDescription = HtmlHelper.isHtmlLong(place.description);
    final hasEvents =
        (place.events?.isNotEmpty ?? false) || counselingHours.isNotEmpty;
    final descriptionIsEmpty =
        !MapPageHelper.hasMeaningfulPlaceDescription(place.description);

    if (isToilet) {
      setState(() => _popupPlaceId = placeId);
      return;
    }
    setState(() => _popupPlaceId = null);
    if (hasLongDescription || hasEvents) {
      if (selectedPlace == null || placeId == selectedPlace!.place.id) {
        _setFocusedPlaceLogic(marker);
      }
      await showDialog(
        context: context,
        builder: (context) => DetailDialog(
          title: place.title,
          titleActions: [
            FilledButton.tonalIcon(
              onPressed: () => _navigateToPlace(place),
              icon: const Icon(Icons.directions_outlined),
              label: Text(MapStrings.navigate),
            ),
          ],
          canEdit: RightsService.isEditor(),
          onEditPressed: () {
            if (selectedPlace == null) runEditPositionMode(marker);
          },
          htmlDescription: place.description,
          customContentWidget: activityContent(
            place.events,
            counselingHours: counselingHours,
          ),
          shrinkWrapCustomContent: true,
        ),
      );
      if (selectedPlace == null || placeId == selectedPlace!.place.id) {
        _setFocusedPlaceLogic(marker);
      }
    } else if (descriptionIsEmpty) {
      if (selectedPlace == null || placeId == selectedPlace!.place.id) {
        _setFocusedPlaceLogic(marker);
      }
    } else {
      setState(() => _popupPlaceId = placeId);
    }
  }

  Future<bool> _navigateToPlace(MapPlaceModel place) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final apps = await ExternalMapNavigation.availableIosApps();
      if (!mounted) return false;
      final selected = await showModalBottomSheet<IosNavigationApp>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => IosNavigationAppPicker(
          apps: apps,
          title: MapStrings.chooseNavigationApp,
          onSelected: (app) => Navigator.of(sheetContext).pop(app),
        ),
      );
      if (selected == null) return false;
      return ExternalMapNavigation.launchIos(
        app: selected,
        latitude: place.latLng.latitude,
        longitude: place.latLng.longitude,
        label: place.title,
      );
    }

    return LaunchUrlService.openExternalUrl(
      MapPageHelper.navigationUri(
        latitude: place.latLng.latitude,
        longitude: place.latLng.longitude,
        label: place.title,
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      ).toString(),
    );
  }

  Future<void> _onPlaceLongPress(int placeId) async {
    final marker = _places.firstWhereOrNull(
      (candidate) => candidate.place.id == placeId,
    );
    if (marker == null) return;
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                marker.place.title,
                style: Theme.of(sheetContext).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_navigateToPlace(marker.place));
                },
                icon: const Icon(Icons.directions_outlined),
                label: Text(MapStrings.navigate),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlacePopup() {
    final marker =
        _places.firstWhereOrNull((item) => item.place.id == _popupPlaceId);
    if (marker == null || !_viewportController.isAttached) {
      return const SizedBox.shrink();
    }
    final point = _viewportController.coordinateToScreenPoint(marker.point);
    final size = MediaQuery.sizeOf(context);
    final left = math.max(8.0, math.min(point.dx - 150, size.width - 308));
    final top = math.max(8.0, point.dy - 190);
    final isToilet =
        marker.place.type == CleaningStatusHelper.toiletPlaceTypeCode &&
            FeatureService.isFeatureEnabled(FeatureConstants.cleaning);
    return Positioned(
      left: left,
      top: top,
      child: MapDescriptionPopup(
        place: marker.place,
        isEditing: selectedPlace != null,
        onClose: () => setState(() => _popupPlaceId = null),
        onNavigate: () => unawaited(_navigateToPlace(marker.place)),
        onChangePosition: () => runEditPositionMode(marker),
        cleaningStatus: isToilet
            ? (_cleaningByPlace[marker.place.id]?.status ??
                CleaningStatus.green)
            : null,
        onReportCleaning:
            isToilet ? () => _reportCleaningForPlace(marker.place) : null,
      ),
    );
  }

  List<MapPlacePresentation> _getDisplayedPlaces() {
    if (selectedPlace != null) {
      final List<MapPlacePresentation> backgroundPlaces =
          _places.where((m) => m.place.id != selectedPlace!.place.id).toList();
      return [...backgroundPlaces, ..._selectedPlaces];
    } else if (_isDrawingPath) {
      // Show every place so any can be tapped into the path. Free points are
      // renderer-neutral drawPoints in MapScene.
      return _places;
    } else if (!_placeTypesResolved) {
      // Types not loaded yet: show only a deep-linked place (if any) and hold the
      // rest back rather than flashing every place unfiltered for a frame.
      return _places.where((m) => m.place.id == _forcedVisiblePlaceId).toList();
    } else {
      return _places
          .where((m) =>
              m.place.id == _forcedVisiblePlaceId ||
              _placeMatchesSelectedType(m.place))
          .toList();
    }
  }

  /// Whether a place passes the active place-type filter. With no filter loaded
  /// every place matches; the "Other" bucket matches untyped places and places
  /// whose type is not among the visible chips.
  bool _placeMatchesSelectedType(MapPlaceModel place) {
    // A deep-link filter (e.g. toilets) applies even with no catalog place_types.
    if (_deepLinkPlaceType != null) {
      return place.type == _deepLinkPlaceType;
    }
    if (_selectedPlaceTypeCode == null || _placeTypes.isEmpty) return true;
    if (_selectedPlaceTypeCode == _otherPlaceTypeCode) {
      final visibleCodes = _placeTypes.map((t) => t.code).toSet();
      return place.type == null || !visibleCodes.contains(place.type);
    }
    return place.type == _selectedPlaceTypeCode;
  }

  void onMapTap(LatLng pos) {
    if (_isDrawingPath) {
      _addDrawNode(PathNode.point(pos.latitude, pos.longitude));
      return;
    }
    if (selectedPlace != null) {
      _selectedPlaces.remove(selectedPlace);
      selectedPlace =
          selectedPlace!.moveTo(LatLng(pos.latitude, pos.longitude));
      _selectedPlaces.add(selectedPlace!);
      setState(() {});
    } else {
      hideAll();
    }
  }

  void hideAll() {
    if (_popupPlaceId != null) {
      setState(() => _popupPlaceId = null);
    }
    if (focusedPlace != null) {
      setState(() {
        final oldFocusedPlaceIndex =
            _places.indexWhere((m) => m.place.id == focusedPlace!.place.id);
        if (oldFocusedPlaceIndex != -1) {
          _places[oldFocusedPlaceIndex] =
              _places[oldFocusedPlaceIndex].withFocus(false);
        }
        focusedPlace = null;
      });
    }
  }

  void runEditPositionMode(MapPlacePresentation marker) {
    _popupPlaceId = null;
    if (focusedPlace != null && focusedPlace!.place.id != marker.place.id) {
      final oldFocusedPlaceIndex =
          _places.indexWhere((m) => m.place.id == focusedPlace!.place.id);
      if (oldFocusedPlaceIndex != -1) {
        _places[oldFocusedPlaceIndex] =
            _places[oldFocusedPlaceIndex].withFocus(false);
      }
      focusedPlace = null;
    } else if (focusedPlace != null &&
        focusedPlace!.place.id == marker.place.id) {
      final oldFocusedPlaceIndex =
          _places.indexWhere((m) => m.place.id == focusedPlace!.place.id);
      if (oldFocusedPlaceIndex != -1) {
        _places[oldFocusedPlaceIndex] =
            _places[oldFocusedPlaceIndex].withFocus(false);
      }
      focusedPlace = null;
    }

    final editingPlace = marker.startEditing();
    final placeIndex =
        _places.indexWhere((item) => item.place.id == marker.place.id);
    if (placeIndex != -1) _places[placeIndex] = editingPlace;
    setState(() => selectedPlace = editingPlace);
    _selectedPlaces
      ..clear()
      ..add(selectedPlace!);
  }

  Future<void> saveNewPosition() async {
    if (isOnlyEditMode) {
      RouterService.goBack(context, {
        "lat": selectedPlace!.point.latitude,
        "lng": selectedPlace!.point.longitude
      });
      return;
    }
    await DbPlaces.saveLocation(selectedPlace!.place,
        selectedPlace!.point.latitude, selectedPlace!.point.longitude);
    if (!mounted) return;
    ToastHelper.Show(context, MapStrings.placeChanged);

    // We keep selectedPlace assigned until after potentially reloading places
    final savedPlaceId = selectedPlace!.place.id;

    if (_isShowingGroupsInEditMode) {
      _isShowingGroupsInEditMode = false;
      _selectedPlaces.clear();
      selectedPlace = null; // Exit edit mode
      await loadData(); // Reload default places and polylines
    } else {
      // Original logic for updating _places when not in _isShowingGroupsInEditMode
      var placeToRemove =
          _places.firstWhereOrNull((m) => m.place.id == savedPlaceId);
      if (placeToRemove != null) _places.remove(placeToRemove);
      _places.add(selectedPlace!.finishEditing());
      _selectedPlaces.clear();
      selectedPlace = null; // Exit edit mode
    }
    setState(() {}); // General UI update
  }

  void cancelNewPosition() {
    if (isOnlyEditMode) {
      RouterService.goBack(context);
      return;
    }

    final originalPlaceId = selectedPlace?.place.id;
    final oldPoint = selectedPlace?.oldPoint;

    if (_isShowingGroupsInEditMode) {
      _isShowingGroupsInEditMode = false;
      _selectedPlaces.clear();
      selectedPlace = null; // Exit edit mode first
      loadData().then((_) {
        // Reload default places
        // If we need to restore focus or re-select the original marker:
        if (originalPlaceId != null) {
          var originalMarkerInNewList =
              _places.firstWhereOrNull((m) => m.place.id == originalPlaceId);
          if (originalMarkerInNewList != null && oldPoint != null) {
            // Potentially re-focus or re-select, but for cancel, usually just revert and exit edit mode.
          }
        }
        setState(() {});
      });
    } else {
      // Original cancel logic
      if (selectedPlace != null && selectedPlace!.oldPoint != null) {
        final originalPlaceIndex =
            _places.indexWhere((m) => m.place.id == selectedPlace!.place.id);
        if (originalPlaceIndex != -1) {
          _places[originalPlaceIndex] = selectedPlace!.copyWith(
            coordinate: selectedPlace!.oldPoint!,
            isEditing: false,
            isFocused: false,
            showTitle: false,
            originalCoordinate: null,
          );
        }
      }
      _selectedPlaces.clear();
      selectedPlace = null;
      setState(() {});
    }
  }

  void showAllGroups() {
    setState(() {
      _isShowingGroupsInEditMode = true;
    });
    // selectedPlace remains active, edit mode continues
    // loadPlaces will repopulate _places with group places
    // addPlacesToMap will use _isShowingGroupsInEditMode to set titles
    // _getDisplayedPlaces will combine _places (groups) and _selectedPlaces (edited one)
    loadData(loadOtherGroups: true);
  }

  Future<void> loadData({bool loadOtherGroups = false}) async {
    _catalogFinal = false;
    // Preserve selected marker's ID if in edit mode to potentially re-apply state later if needed,
    // though current logic replaces _places list entirely.
    // The selectedPlace instance itself in _selectedPlaces should persist.

    var offlinePlaces = await OfflineDataService.getAllPlaces();
    _icons = await OfflineDataService.getAllIcons();

    // Load cached place types and pick the filter BEFORE the first render, so
    // cached places don't flash unfiltered while the online types are still
    // loading. The last selection is restored from offline storage; if there is
    // none (or it is no longer valid), _initPlaceTypeSelection falls back to
    // the default type.
    _placeTypes = (await OfflineDataService.getAllPlaceTypes())
        .where((t) => !(t.isHidden ?? false))
        .toList();
    if (!_placeTypeInitialized) {
      final savedCode = await OfflineDataService.getSelectedPlaceType();
      if (savedCode != null) {
        _selectedPlaceTypeCode = savedCode;
        _placeTypeInitialized = true;
      }
    }
    // Cached types are enough to filter the first paint; if there are none we
    // wait for the online pass so we don't flash every place unfiltered.
    if (_placeTypes.isNotEmpty) _placeTypesResolved = true;

    offlinePlaces.sortPlaces(false);
    var offlineList = loadOtherGroups
        ? offlinePlaces
        : offlinePlaces.where((e) => !(e.isHidden)).toList();
    await addOfflineEventsToPlace(offlineList);
    // Cache-first paint of the toilet colors, so they show without network;
    // the online pass below overwrites them with the live statuses.
    await _seedCleaningStatusFromCache();
    addPlacesToMap(offlineList);
    _initPlaceTypeSelection();
    _publishCatalog(isFinal: false);

    if (mounted) setState(() {});

    _pathGroups = (await OfflineDataService.getAllPathGroups())
        .where((p) => !(p.isHidden ?? false))
        .toList();
    _allGroupPaths = await MapPageHelper.loadGroupPaths(
        offlineList, // Use offline list for initial polyline calculation if it's primary
        _pathGroups);

    // Update polylines based on current selection
    if (_selectedGroupId == null) {
      if (_showAllPathsWhenNoGroupSelected) {
        _paths = _allGroupPaths.values.expand((list) => list).toList();
      } else {
        _paths = [];
      }
    } else {
      _paths = _allGroupPaths[_selectedGroupId!] ?? [];
    }

    if (mounted) setState(() {});

    // v1 readers consume the closed map_catalog aggregate above. Missing
    // places/types/paths/icons block publication; they are never side-loaded.
    if (ClientSyncRuntime.isV1Selected) {
      _publishCatalog(isFinal: true);
      return;
    }

    // The cache-first scene above is a complete, usable map state. The
    // forceOfflineMap setting selects only the base-map renderer; live places,
    // paths and status data may still refresh whenever connectivity is present.
    if (!await _hasNetworkConnection()) {
      _placeTypesResolved = true;
      if (_isDrawingPath) {
        _rebuildDrawOverlay();
      } else if (mounted) {
        setState(() {});
      }
      _publishCatalog(isFinal: true);
      return;
    }

    if (!mounted) return;
    await ExceptionHandler.guardVoid(
      context,
      futureFunction: () async {
        // online part
        final onlineIcons = await DbPlaces.getAllIcons();
        var onlinePlaceTypes = _placeTypes;

        try {
          var placeTypesFromDb = await DbPlaceTypes.getPlaceTypes();
          await OfflineDataService.saveAllPlaceTypes(placeTypesFromDb);
          onlinePlaceTypes =
              placeTypesFromDb.where((t) => !(t.isHidden ?? false)).toList();
        } catch (e) {
          AppLogger.error("Failed to load place types: $e");
        }

        List<PlaceModel> onlineList;
        var placesFromDb = await DbPlaces.getAllPlaces();
        await OfflineDataService.saveAllPlaces(placesFromDb);

        if (loadOtherGroups) {
          var dbGroups = await DbGroups.getGroupsWithPlaces();
          onlineList = dbGroups.where((e) => e.place != null).map((e) {
            e.place!.title = e.title;
            return e.place!;
          }).toList();
        } else {
          onlineList = placesFromDb.where((p) => !(p.isHidden)).toList();
        }
        onlineList.sortPlaces(false);

        await addEventsToPlace(onlineList);
        final onlineCleaningByPlace = await _getCleaningStatus();
        final onlinePathGroups = (await DbPlaces.getAllPathGroups())
            .where((p) => !(p.isHidden ?? false))
            .toList();
        final onlineGroupPaths = await MapPageHelper.loadGroupPaths(
          onlineList,
          onlinePathGroups,
        );

        // Commit the refreshed scene only after every required online read and
        // path calculation succeeded. A failed refresh must leave the complete
        // cache-first scene intact.
        if (!mounted) return;
        _icons = onlineIcons;
        _placeTypes = onlinePlaceTypes;
        _placeTypesResolved = true;
        _cleaningByPlace = onlineCleaningByPlace;
        addPlacesToMap(onlineList);
        _initPlaceTypeSelection();
        _publishCatalog(isFinal: false);
        _pathGroups = onlinePathGroups;
        _allGroupPaths = onlineGroupPaths;

        // Update polylines based on current selection
        if (_selectedGroupId == null) {
          if (_showAllPathsWhenNoGroupSelected) {
            _paths = _allGroupPaths.values.expand((list) => list).toList();
          } else {
            _paths = [];
          }
        } else {
          _paths = _allGroupPaths[_selectedGroupId!] ?? [];
        }

        // This setState call was inside addPlacesToMap, moved here for clarity after all data processing
        if (mounted) setState(() {});

        if (_isDrawingPath) _rebuildDrawOverlay();
      },
    );
    _publishCatalog(isFinal: true);
  }

  void _publishCatalog({required bool isFinal}) {
    _catalogFinal = isFinal;
    _catalogEpoch++;
    _mapSession?.hostChanged();
  }

  Future<void> addOfflineEventsToPlace(List<PlaceModel> places) async {
    final events = await OfflineDataService.getAllEvents();
    _counselingHoursByPlace =
        MapPageHelper.assignEventsToPlaces(places, events);
  }

  Future<void> addEventsToPlace(List<PlaceModel> places) async {
    if (ClientSyncRuntime.isV1Selected) {
      await addOfflineEventsToPlace(places);
      return;
    }
    final events =
        await DbEvents.getAllEvents(RightsService.currentOccasionId()!, false);
    _counselingHoursByPlace =
        MapPageHelper.assignEventsToPlaces(places, events);
  }

  bool _shouldShowPlaceTitle(int? placeId, int? currentFocusedPlaceId,
      int? editingPlaceId, Set<int> placeIdsInCurrentGroup) {
    if (_isShowingGroupsInEditMode) {
      // In "show all groups during edit" mode:
      // Show title for all markers EXCEPT the one currently being edited.
      return editingPlaceId == null || placeId != editingPlaceId;
    } else {
      // Normal mode (not showing all group titles during edit):
      // Show title if the marker is currently focused.
      if (currentFocusedPlaceId != null && placeId == currentFocusedPlaceId) {
        return true;
      }
      // Show title if a group is selected AND this marker belongs to that group.
      if (_selectedGroupId != null &&
          placeIdsInCurrentGroup.contains(placeId)) {
        return true;
      }
    }
    return false; // Default: do not show title.
  }

  Future<Map<int, CleaningPlaceStatus>> _getCleaningStatus() async {
    if (!FeatureService.isFeatureEnabled(FeatureConstants.cleaning)) {
      return {};
    }
    final oc = RightsService.currentOccasionId();
    if (oc == null) return _cleaningByPlace;
    try {
      final statuses = await DbCleaning.getStatus(oc);
      // Refresh-on-read: keep the offline copy of the public statuses fresh.
      await OfflineDataService.saveCleaningStatus(
          statuses.places, DateTime.now());
      return {for (final s in statuses.places) s.place: s};
    } catch (_) {
      // Offline / RPC failure: color the pins from the cached statuses.
      return await _getCachedCleaningStatus() ?? _cleaningByPlace;
    }
  }

  /// Seeds the toilet pin colors from the cached statuses so the offline
  /// render shows the last known colors (feature-gated like the live load).
  Future<void> _seedCleaningStatusFromCache() async {
    if (!FeatureService.isFeatureEnabled(FeatureConstants.cleaning)) return;
    final cached = await _getCachedCleaningStatus();
    if (cached != null) _cleaningByPlace = cached;
  }

  Future<Map<int, CleaningPlaceStatus>?> _getCachedCleaningStatus() async {
    final cached = await OfflineDataService.getCleaningStatus();
    return cached == null ? null : {for (final s in cached.places) s.place: s};
  }

  /// Status color for a place if it is a toilet and the feature is on, else null.
  Color? _cleaningPinColorFor(MapPlaceModel place) {
    if (place.type != CleaningStatusHelper.toiletPlaceTypeCode ||
        !FeatureService.isFeatureEnabled(FeatureConstants.cleaning)) {
      return null;
    }
    final status = _cleaningByPlace[place.id]?.status ?? CleaningStatus.green;
    return CleaningStatusHelper.color(status);
  }

  /// Opens the report dialog from a toilet popup and refreshes colors.
  Future<void> _reportCleaningForPlace(MapPlaceModel place) async {
    if (place.id == null) return;
    final changed = await CleaningReportFlow.report(
      context,
      placeId: place.id!,
      placeTitle: place.title,
    );
    if (changed && mounted) await loadData();
  }

  void addPlacesToMap(List<PlaceModel> places) {
    // A place without coordinates or a title can't become a map marker
    // (MapPlaceModel force-reads lat/lng and title). Skip it silently — a place
    // with no coordinates simply doesn't belong on the map.
    places = places.where((p) => p.hasCoordinates && p.title != null).toList();
    var focusedPlaceId = focusedPlace?.place.id;
    var editingPlaceId = selectedPlace?.place.id;

    Set<int> placeIdsInSelectedGroup = {};
    if (!_isShowingGroupsInEditMode && _selectedGroupId != null) {
      final group =
          _pathGroups.firstWhereOrNull((g) => g.id == _selectedGroupId);
      if (group != null && group.pathData != null) {
        placeIdsInSelectedGroup.addAll(group.pathData!
            .expand((segment) => segment)
            .map((node) => node.placeId)
            .whereType<int>());
      }
    }

    final wcIconId = FeatureService.isFeatureEnabled(FeatureConstants.cleaning)
        ? _icons
            .firstWhereOrNull((i) =>
                i.link == CleaningStatusHelper.toiletPlaceTypeCode ||
                i.link == 'wc')
            ?.id
        : null;

    var mappedPlaces = places.map((place) {
      // Toilets without their own icon still show the shared "wc" icon.
      if (wcIconId != null &&
          place.type == CleaningStatusHelper.toiletPlaceTypeCode &&
          place.icon == null) {
        place.icon = wcIconId;
      }
      var mapPlace = MapPlaceModel.fromPlaceModel(place);
      var pinColor = _cleaningPinColorFor(mapPlace);
      bool displayTitle = _shouldShowPlaceTitle(
          mapPlace.id, focusedPlaceId, editingPlaceId, placeIdsInSelectedGroup);

      return MapPlacePresentation(
        place: mapPlace,
        coordinate: mapPlace.latLng,
        pinColorValue:
            (pinColor ?? ThemeConfig.mapPinColor(context)).toARGB32(),
        showTitle: displayTitle,
        isFocused: mapPlace.id == focusedPlaceId,
        isEditing: mapPlace.id == editingPlaceId,
      );
    }).toList();

    _places.clear();
    _places.addAll(mappedPlaces);
    // setState is called in loadPlaces after this
  }

  bool isIconVisible(PlaceModel place) {
    return true;
  }

  void _onGroupIconTap(int groupId) async {
    List<MapPathPresentation> newPaths = [];
    List<LatLng> allPoints = [];

    if (_selectedGroupId == groupId) {
      _selectedGroupId = null;
      if (_showAllPathsWhenNoGroupSelected) {
        newPaths = _allGroupPaths.values.expand((list) => list).toList();
        allPoints = [];
      }
      // else newPaths is already [], allPoints is already []
    } else {
      _selectedGroupId = groupId;
      newPaths = _allGroupPaths[groupId] ?? [];
      allPoints = newPaths.expand((path) => path.points).toList();
    }

    final List<MapPlacePresentation> groupPlaces = [];
    final List<MapPlacePresentation> otherPlaces = [];
    Set<int> placeIdsInSelectedGroup = {};
    if (_selectedGroupId != null) {
      final group =
          _pathGroups.firstWhereOrNull((g) => g.id == _selectedGroupId);
      if (group != null && group.pathData != null) {
        placeIdsInSelectedGroup.addAll(group.pathData!
            .expand((segment) => segment)
            .map((node) => node.placeId)
            .whereType<int>());
      }
    }

    var focusedPlaceId = focusedPlace?.place.id;
    var editingPlaceId = selectedPlace?.place.id;

    for (final oldMarker in _places) {
      bool newShowTitleState = _shouldShowPlaceTitle(oldMarker.place.id!,
          focusedPlaceId, editingPlaceId, placeIdsInSelectedGroup);

      var updatedMarker = oldMarker;
      if (oldMarker.showTitle != newShowTitleState) {
        updatedMarker = oldMarker.copyWith(
          showTitle: newShowTitleState,
        );
      }

      if (placeIdsInSelectedGroup.contains(oldMarker.place.id!)) {
        groupPlaces.add(updatedMarker);
      } else {
        otherPlaces.add(updatedMarker);
      }
    }

    _places.clear();
    _places.addAll(otherPlaces);
    _places.addAll(groupPlaces);

    if (allPoints.isNotEmpty) {
      setState(() {
        _paths = newPaths;
      });
      await _viewportController.fitCoordinates(
        allPoints,
        padding: const EdgeInsets.fromLTRB(32, 160, 84, 12),
      );
      // Programmatic fit completion is the authoritative zoom point for
      // direction layout; do not depend solely on a renderer idle event.
      _onZoomChanged(_viewportController.directionLayoutZoom);
    } else {
      setState(() {
        _paths =
            newPaths; // Will be [] if deselected (and not _showAllPathsWhenNoGroupSelected) or if selected group has no lines
      });
    }
  }

  Widget _buildEditControls() {
    return Visibility(
      visible: selectedPlace != null,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: cancelNewPosition,
                  child: Text(CommonStrings.storno),
                ),
                const Padding(padding: EdgeInsets.all(16.0)),
                Visibility(
                  visible: !isOnlyEditMode,
                  child: ElevatedButton(
                    onPressed:
                        showAllGroups, // This now handles being in edit mode
                    child: Text(MapStrings.showGroups),
                  ),
                ),
                const Padding(padding: EdgeInsets.all(16.0)),
                ElevatedButton(
                  onPressed: () => ExceptionHandler.guardVoid(context,
                      futureFunction: saveNewPosition),
                  child: Text(MapStrings.saveLocation),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            child: Text(
              MapStrings.changeLocationHint,
              style: const TextStyle(color: Colors.black),
            ),
          ),
          Expanded(child: Container()),
        ],
      ),
    );
  }

  Color _drawPathColor() {
    final hex = widget.editPathGroup?.color;
    if (hex != null && hex.isNotEmpty) {
      try {
        return Color(int.parse(hex.replaceFirst('#', '0x')));
      } catch (_) {}
    }
    return Colors.blue;
  }

  /// Resolve a draw node to a coordinate: free points use their inline lat/lng,
  /// place refs are looked up among the loaded markers.
  LatLng? _resolveDrawNode(PathNode node) {
    if (node.isPoint) return LatLng(node.lat!, node.lng!);
    return _places.firstWhereOrNull((m) => m.place.id == node.placeId)?.point;
  }

  /// Recompute the live polyline and free-point markers from [_drawSegments].
  void _rebuildDrawOverlay() {
    final color = _drawPathColor();

    final paths = <MapPathPresentation>[];
    for (final seg in _drawSegments) {
      final pts = seg.map(_resolveDrawNode).whereType<LatLng>().toList();
      if (pts.length >= 2) {
        paths.add(MapPathPresentation(
          id: 'draw_${paths.length}',
          points: pts,
          colorValue: color.toARGB32(),
          strokeWidth: 3,
          kind: MapPathKind.draw,
        ));
      }
    }

    _paths = paths;
    if (mounted) setState(() {});
  }

  void _addDrawNode(PathNode node) {
    if (_drawSegments.isEmpty) _drawSegments.add(<PathNode>[]);
    _drawSegments.last.add(node);
    _rebuildDrawOverlay();
  }

  /// Remove the most recently added node (from the last non-empty segment).
  void _undoLastDrawNode() {
    for (var i = _drawSegments.length - 1; i >= 0; i--) {
      if (_drawSegments[i].isNotEmpty) {
        _drawSegments[i].removeLast();
        break;
      }
    }
    while (_drawSegments.length > 1 && _drawSegments.last.isEmpty) {
      _drawSegments.removeLast();
    }
    _rebuildDrawOverlay();
  }

  /// Start a fresh segment so the next taps form a disconnected path piece.
  void _newDrawSegment() {
    if (_drawSegments.isEmpty || _drawSegments.last.isNotEmpty) {
      _drawSegments.add(<PathNode>[]);
    }
    _rebuildDrawOverlay();
  }

  /// Replace the working path with imported [segments], redraw, and fit the
  /// camera to the new geometry.
  Future<void> _applyImportedSegments(List<List<PathNode>> segments) async {
    _drawSegments
      ..clear()
      ..addAll(segments);
    _rebuildDrawOverlay();

    final allPoints = _drawSegments
        .expand((s) => s)
        .map(_resolveDrawNode)
        .whereType<LatLng>()
        .toList();
    if (allPoints.length == 1) {
      await _viewportController.animateTo(allPoints.single);
    } else if (allPoints.length > 1) {
      await _viewportController.fitCoordinates(
        allPoints,
        padding: const EdgeInsets.fromLTRB(48, 48, 48, 120),
      );
    }
  }

  /// Import a route from a GPX file (Mapy.com, Strava, Garmin, komoot, …).
  Future<void> _importGpxFile(XFile file) async {
    List<List<PathNode>> segments;
    try {
      final content = await file.readAsString();
      segments = GpxImporter.parse(content);
    } catch (e) {
      AppLogger.error("Failed to read GPX: $e");
      segments = [];
    }

    if (segments.isEmpty) {
      if (mounted) {
        ToastHelper.Show(context, MapStrings.noRouteInGpx,
            severity: ToastSeverity.NotOk);
      }
      return;
    }
    await _applyImportedSegments(segments);
  }

  Future<void> _showImportDialog() async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(MapStrings.importRoute),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(MapStrings.importRouteHint),
              DropFile(
                height: 180,
                allowedExtensions: const ['gpx'],
                onFilePathChanged: (file) async {
                  Navigator.of(dialogContext).pop();
                  await _importGpxFile(file);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(CommonStrings.storno),
          ),
        ],
      ),
    );
  }

  /// Return the drawn path to the caller as the grid's CSV string.
  void _saveDrawPath() {
    final segments = _drawSegments.where((s) => s.isNotEmpty).toList();
    RouterService.goBack(context, PathGroupsModel.pathDataToCsv(segments));
  }

  Widget _buildDrawControls() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              MapStrings.drawPathHint,
              style: const TextStyle(color: Colors.black),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                // Build tools: import a route, then refine by hand.
                ElevatedButton.icon(
                  onPressed: _showImportDialog,
                  icon: const Icon(Icons.upload_file),
                  label: Text(MapStrings.importRoute),
                ),
                ElevatedButton.icon(
                  onPressed: _undoLastDrawNode,
                  icon: const Icon(Icons.undo),
                  label: Text(MapStrings.undo),
                ),
                ElevatedButton.icon(
                  onPressed: _newDrawSegment,
                  icon: const Icon(Icons.linear_scale),
                  label: Text(MapStrings.newSegment),
                ),
                // Visual gap separating the build tools from the save action.
                const SizedBox(width: 24),
                ElevatedButton.icon(
                  onPressed: _saveDrawPath,
                  icon: const Icon(Icons.check),
                  label: Text(MapStrings.saveRoute),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Pick the initial place-type filter once types are available: the default
  /// type (`is_default`) if any, otherwise the first (order-sorted) type. Keeps
  /// an existing selection unless it no longer matches any visible chip (e.g.
  /// initialized from a stale offline cache).
  void _initPlaceTypeSelection() {
    // A deep-link filter wins and must not be overridden by saved/default type.
    if (_deepLinkPlaceType != null) {
      _selectedPlaceTypeCode = _deepLinkPlaceType;
      _placeTypeInitialized = true;
      return;
    }
    if (_placeTypes.isEmpty) return;
    final otherSelectionIsAvailable =
        _selectedPlaceTypeCode == _otherPlaceTypeCode &&
            MapPageHelper.hasOtherVisiblePlaces(_places, _placeTypes);
    if (_placeTypeInitialized &&
        (otherSelectionIsAvailable ||
            _placeTypes.any((t) => t.code == _selectedPlaceTypeCode))) {
      return;
    }
    final defaultType =
        _placeTypes.firstWhereOrNull((t) => t.isDefault == true);
    _selectedPlaceTypeCode = (defaultType ?? _placeTypes.first).code;
    _placeTypeInitialized = true;
  }

  Future<void> _onPlaceTypeTap(String? code) async {
    if (code == null) return;
    // Tapping a chip returns to normal filtering, dropping any deep-link filter.
    _deepLinkPlaceType = null;
    final feedback = code == _otherPlaceTypeCode
        ? IconsStrings.placeTypesOther
        : _placeTypes.firstWhereOrNull((type) => type.code == code)?.title;
    _placeTypeSelectionFeedbackTimer?.cancel();
    setState(() {
      _forcedVisiblePlaceId = null;
      _selectedPlaceTypeCode = code;
      _placeTypeSelectionFeedback = feedback;
    });
    _placeTypeSelectionFeedbackTimer = Timer(
      const Duration(milliseconds: 1800),
      () {
        if (!mounted) return;
        setState(() => _placeTypeSelectionFeedback = null);
      },
    );
    await OfflineDataService.saveSelectedPlaceType(code);

    final points = _places
        .where((m) => _placeMatchesSelectedType(m.place))
        .map((m) => m.point)
        .toList();

    if (points.length == 1) {
      await _viewportController.animateTo(
        points.single,
        zoom: _mapFeature.defaultMapZoom,
      );
    } else if (points.length > 1) {
      await _viewportController.fitCoordinates(
        points,
        padding: const EdgeInsets.fromLTRB(48, 48, 48, 96),
      );
    }
  }

  void _setFocusedPlaceLogic(MapPlacePresentation placeToFocus) {
    // If we are in the mode of showing all group titles during edit, don't let tap-focus override them
    if (_isShowingGroupsInEditMode &&
        (selectedPlace != null &&
            placeToFocus.place.id != selectedPlace!.place.id)) {
      // If a group marker (not the one being edited) is tapped, show its popup but don't change its title state from true.
      // The popup logic is handled in showPopupOrDialogFor.
      // Here we just avoid toggling its 'showTitle' if it's a background group marker.
      return;
    }

    setState(() {
      final placeIdToFocus = placeToFocus.place.id;
      bool newFocusSet = false;
      MapPlacePresentation? placeToBringToTop;

      for (int i = 0; i < _places.length; i++) {
        // Do not change focus state of the marker currently being edited
        if (selectedPlace != null &&
            _places[i].place.id == selectedPlace!.place.id) {
          if (_places[i].place.id == placeIdToFocus) {
            // If the edited marker itself is somehow re-focused
            focusedPlace =
                _places[i]; // Keep it as the focused marker conceptually
            newFocusSet = true;
          }
          continue;
        }

        if (_places[i].place.id == placeIdToFocus) {
          if (!_places[i].showTitle) {
            _places[i] = _places[i].withFocus(true);
          }
          focusedPlace = _places[i];
          placeToBringToTop = _places[i];
          newFocusSet = true;
        } else {
          if (_places[i].showTitle) {
            // Only defocuse if not part of selected group that should show title or not in group edit mode display
            bool shouldRetainTitle = false;
            if (_selectedGroupId != null) {
              final group =
                  _pathGroups.firstWhereOrNull((g) => g.id == _selectedGroupId);
              if (group != null &&
                  group.pathData != null &&
                  group.pathData!.any((segment) => segment
                      .any((node) => node.placeId == _places[i].place.id))) {
                shouldRetainTitle = true;
              }
            }
            if (!shouldRetainTitle) {
              _places[i] = _places[i].withFocus(false);
            }
          }
        }
      }
      if (!newFocusSet) {
        focusedPlace = null;
      }

      if (placeToBringToTop != null) {
        _places.removeWhere((m) => m.place.id == placeToBringToTop!.place.id);
        _places.add(placeToBringToTop);
      }
    });
  }

  Widget activityContent(
    List<TimeBlockItem>? events, {
    List<CounselingHoursRange> counselingHours = const [],
  }) {
    return Column(
      children: [
        if (counselingHours.isNotEmpty)
          CounselingHoursPanel(
            ranges: counselingHours,
            onRangePressed: _openCounselingRange,
          ),
        if (events != null && events.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
            child: ScheduleTimeline(
              eventGroups:
                  TimeBlockHelper.splitTimeBlocksByDay(events, context),
              onEventPressed: (int id) {
                RouterService.navigateOccasion(
                        context, "${EventPage.ROUTE}/$id")
                    .then((_) => loadData());
              },
              showAddNewEventButton: () => false,
              onAddNewEvent: null,
              nodePosition: 0.35,
            ),
          ),
      ],
    );
  }

  void _openCounselingRange(CounselingHoursRange range) {
    Navigator.of(context, rootNavigator: true).pop();
    final route = range.entryEventId == null
        ? CounselingPage.ROUTE
        : '${EventPage.ROUTE}/${range.entryEventId}';
    RouterService.navigateOccasion(context, route).then((_) => loadData());
  }
}

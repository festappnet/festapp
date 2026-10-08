import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/activities/activities_component_strings.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/information/db_information.dart';
import 'package:fstapp/components/unit/db_units.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/feedback/feedack_floating_button.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/components/unit/views/occasion_card.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/widgets/header/universal_header.dart';

const double kVerticalPadding = 32.0;

/// Abstract base widget that holds the common path parameter.
abstract class UnitPageBase extends StatefulWidget {
  final int? id;

  const UnitPageBase({@pathParam this.id, super.key});
}

/// Abstract base state containing all the logic previously in _UnitPageState.
/// It is generic (<T extends UnitPageBase>) to work with any widget
/// that extends UnitPageBase.
abstract class UnitPageBaseState<T extends UnitPageBase> extends State<T> {
  UnitModel? _unit;
  List<OccasionModel> _occasions = [];
  InformationModel? _quote;
  final ScrollController _scrollController = ScrollController();
  int? _currentUnitId;

  // State for the search functionality
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    // Add listener for search
    _searchController.addListener(() {
      if (_searchQuery != _searchController.text.toLowerCase()) {
        setState(() {
          _searchQuery = _searchController.text.toLowerCase();
        });
      }
    });
    _initialLoad();
  }

  // Handles the very first load when the widget is created.
  Future<void> _initialLoad() async {
    // Immediately load from cache for a faster UI response.
    final cachedOccasions = await OfflineDataService.getAllOccasions();

    if (mounted) {
      setState(() {
        _occasions = cachedOccasions;
      });
    }

    // Determine the ID: prioritize URL (from widget.id), then fallback to current user's unit.
    final idToLoad = widget.id ?? RightsService.currentUnit()?.id;

    await _loadDataForUnit(idToLoad);
  }

  // Centralized method to fetch and set all data for a given unit ID.
  Future<void> _loadDataForUnit(int? unitId) async {
    await RightsService.updateAppData(unitId: unitId, refreshOffline: false);

    // **CHANGED**: Added mounted check before using context
    if (!mounted) return;

    final currentId = RightsService.currentUnit()?.id;
    if (widget.id != null && currentId != null && widget.id != currentId) {
      RouterService.goToUnit(context, currentId);
    }

    _currentUnitId = RightsService.currentUnit()?.id;

    final unit = await DbUnits.getPublicOccasions(
        AppConfig.organization, RightsService.currentUnit()?.id);

    if (!mounted) return;

    final occasions = unit.occasions ?? [];
    await OfflineDataService.saveAllOccasions(occasions);

    InformationModel? quote;
    if (FeatureService.isFeatureEnabled(FeatureConstants.quotes,
        features: unit.features)) {
      quote = await DbInformation.getCurrentQuote(unitId!);
    }

    // This final mounted check is correct and will catch the await above
    if (mounted) {
      setState(() {
        _unit = unit;
        _occasions = occasions;
        _quote = quote;
      });
    }
  }

  Future<void> _handleSignIn() async {
    if (RightsService.currentUnit()?.id == null) return;
    final newUnitId = RightsService.currentUnit()!.id!;

    await _loadDataForUnit(newUnitId);

    if (!mounted) return;

    if (widget.id != null) {
      await RouterService.goToUnit(context, newUnitId);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Filter occasions based on the search query
    final filteredOccasions = _searchQuery.isEmpty
        ? _occasions
        : _occasions.where((o) {
            final title = o.title?.toLowerCase() ?? '';
            return title.contains(_searchQuery);
          }).toList();

    final presentEvents = filteredOccasions
        .where((o) => o.startTime!.isBefore(now) && o.endTime!.isAfter(now))
        .toList();
    final upcomingEvents =
        filteredOccasions.where((o) => o.startTime!.isAfter(now)).toList();
    upcomingEvents.sort((a, b) => a.startTime!.compareTo(b.startTime!));
    final pastEvents =
        filteredOccasions.where((o) => o.endTime!.isBefore(now)).toList();

    // Define the grid delegate here to be reused
    final gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 400.0, // This will make cards smaller
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio:
          OccasionCard.kCardWidth / OccasionCard.kCardHeight, // 16:9
    );

    // Define the admin callback
    VoidCallback? adminCallback;
    if (RightsService.currentUser()?.units?.isNotEmpty ?? false) {
      adminCallback = () {
        RouterService.handlePostLoginNavigation(context).then((_) {
          if (_currentUnitId != null) {
            _loadDataForUnit(_currentUnitId!);
          }
        });
      };
    }

    return Scaffold(
      floatingActionButton:
          AppConfig.isFeedbackEnabled ? const FeedbackFloatingButton() : null,
      // Ensure the button sits above the bottom safe area
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

      body: CustomScrollView(
        controller: _scrollController,
        cacheExtent: 500,
        slivers: [
          UniversalHeader(
            scrollController: _scrollController,
            onSignIn: _handleSignIn,
            onAdminPressed: adminCallback,
          ),
          // Search Bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                  top: 16.0, left: 16.0, right: 16.0, bottom: 8.0),
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: ActivitiesComponentStrings.hintSearchEvents,
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: ThemeConfig.whiteColor(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide:
                            BorderSide(color: ThemeConfig.grey300(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide:
                            BorderSide(color: ThemeConfig.grey300(context)),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Quote section rendered as HTML in a paper-like container.
          if (_unit != null && _quote != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: kVerticalPadding, horizontal: 16.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
                    child: Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: ThemeConfig.whiteColor(context),
                        border: Border.all(color: ThemeConfig.grey300(context)),
                        borderRadius: BorderRadius.circular(8.0),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4.0,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: HtmlView(
                        html: _quote!.description ?? "",
                        isSelectable: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // "Happening Now" title for present events.
          if (presentEvents.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 16.0, horizontal: 16.0),
                child: Text(
                  CommonStrings.happeningNow,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          // Grid of present occasion cards.
          if (presentEvents.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              sliver: SliverGrid(
                gridDelegate: gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final occasion = presentEvents[index];
                    // Wrap each card in a RepaintBoundary.
                    return RepaintBoundary(
                      child: OccasionCard(
                        occasion: occasion,
                        isPast: false,
                        isPresent: true,
                      ),
                    );
                  },
                  childCount: presentEvents.length,
                ),
              ),
            ),
          // "Upcoming Events" title.
          if (upcomingEvents.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 16.0, horizontal: 16.0),
                child: Text(
                  CommonStrings.upcomingEvents,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          // Grid of upcoming occasion cards.
          if (upcomingEvents.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              sliver: SliverGrid(
                gridDelegate: gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final occasion = upcomingEvents[index];
                    return RepaintBoundary(
                      child: OccasionCard(
                        occasion: occasion,
                        isPast: false,
                        isPresent: false,
                      ),
                    );
                  },
                  childCount: upcomingEvents.length,
                ),
              ),
            ),
          // "Past Events" title.
          if (pastEvents.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 16.0, horizontal: 16.0),
                child: Text(
                  CommonStrings.pastEvents,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          // Grid of past occasion cards.
          if (pastEvents.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              sliver: SliverGrid(
                gridDelegate: gridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final occasion = pastEvents[index];
                    return RepaintBoundary(
                      child: OccasionCard(
                        occasion: occasion,
                        isPast: true,
                        isPresent: false,
                      ),
                    );
                  },
                  childCount: pastEvents.length,
                ),
              ),
            ),
          // Extra space below the last item.
          const SliverToBoxAdapter(
            child: SizedBox(height: 64),
          ),
        ],
      ),
    );
  }
}

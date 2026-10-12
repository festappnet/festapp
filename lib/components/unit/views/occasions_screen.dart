import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/unit/app_landing.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/components/_shared/admin_strings.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/unit_strings.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/components/occasion/occasion_creation_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/components/unit/views/occasion_edit_card.dart';

class OccasionsScreen extends StatefulWidget {
  final UnitModel unit;
  final List<OccasionModel>? initialOccasions;
  const OccasionsScreen({super.key, required this.unit, this.initialOccasions});

  @override
  _OccasionsScreenState createState() => _OccasionsScreenState();
}

class _OccasionsScreenState extends State<OccasionsScreen> {
  List<OccasionModel> _allOccasions = [];
  List<OccasionModel> _filteredOccasions = [];
  bool _isLoading = true;
  AppLanding? _landing;
  bool _landingFailed = false;
  bool _savingLanding = false;
  int _landingGeneration = 0;

  Future<void> _loadLanding() async {
    final generation = ++_landingGeneration;
    try {
      final landing = await AppLanding.load(widget.unit.id!);
      if (!mounted || generation != _landingGeneration) return;
      setState(() {
        _landing = landing;
        _landingFailed = false;
      });
    } catch (_) {
      if (!mounted || generation != _landingGeneration) return;
      setState(() => _landingFailed = true);
    }
  }

  Future<void> _setLanding(int? occasionId) async {
    final landing = _landing;
    if (landing == null || !landing.canManage || _savingLanding) return;
    final unitId = widget.unit.id!;
    final generation = ++_landingGeneration;
    setState(() => _savingLanding = true);
    final saved = await ExceptionHandler.guard(context,
        futureFunction: () => landing.save(unitId, occasionId));
    if (!mounted || generation != _landingGeneration) return;
    setState(() {
      _savingLanding = false;
      if (saved != null) _landing = saved;
    });
    if (saved == null) await _loadLanding();
  }

  Widget _buildLandingStatus() {
    if (_landingFailed) {
      return TextButton.icon(
          onPressed: _loadLanding,
          icon: const Icon(Icons.refresh),
          label: Text(UnitStrings.landingLoadFailed));
    }
    return _landing == null || _savingLanding
        ? const LinearProgressIndicator()
        : const SizedBox.shrink();
  }

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _initializeOccasions();
    _loadLanding();
    _searchController.addListener(_filterOccasions);
    _searchFocusNode.addListener(_onSearchFocusChange);
  }

  @override
  void didUpdateWidget(covariant OccasionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.unit.id != oldWidget.unit.id) {
      _landing = null;
      _landingFailed = false;
      _savingLanding = false;
      _loadLanding();
    }
    if (widget.unit.id != oldWidget.unit.id ||
        widget.initialOccasions != oldWidget.initialOccasions) {
      _initializeOccasions();
    }
  }

  void _initializeOccasions() {
    if (widget.initialOccasions != null) {
      _allOccasions = widget.initialOccasions!;
      _filteredOccasions = widget.initialOccasions!;
      _isLoading = false;
      // Re-apply filter if search was active
      if (_searchController.text.isNotEmpty) {
        _filterOccasions();
      }
    } else {
      _loadOccasions();
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterOccasions);
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchFocusChange() {
    if (mounted) {
      setState(() {
        _isSearching = _searchFocusNode.hasFocus;
      });
    }
  }

  Future<void> _loadOccasions() async {
    if (!_isLoading) setState(() => _isLoading = true);
    var occasions = await DbOccasions.getAllOccasionsForEdit(widget.unit.id!);
    if (mounted) {
      setState(() {
        _allOccasions = occasions;
        _filteredOccasions = occasions;
        _isLoading = false;
      });
    }
  }

  void _filterOccasions() {
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _filteredOccasions = _allOccasions;
      });
      return;
    }
    final normalizedQuery = Utilities.removeDiacritics(query.toLowerCase());
    setState(() {
      _filteredOccasions = _allOccasions.where((occasion) {
        final normalizedTitle =
            Utilities.removeDiacritics(occasion.title?.toLowerCase() ?? "");
        return normalizedTitle.contains(normalizedQuery);
      }).toList();
    });
  }

  Future<void> _addNewEvent() async {
    final newOccasion = await OccasionCreationHelper.createNewOccasion(
        context, widget.unit, _allOccasions);

    if (newOccasion != null && mounted) {
      await _loadOccasions();
    }
  }

  Future<void> _handleView(OccasionModel occasion) async {
    try {
      if (occasion.link == null) return;
      await RouterService.navigateToOccasionAdministration(context,
          occasion: occasion);
    } catch (e) {
      ToastHelper.Show(context, UnitStrings.loadEventFailed);
    }
  }

  Future<void> _handleCreateCopy(OccasionModel occasion) async {
    final conf = await DialogHelper.showConfirmationDialog(
        context, UnitStrings.createCopy, UnitStrings.createCopyConfirm);
    if (conf == true && mounted) {
      bool mediaCopied = false;
      final created = await DialogHelper.showProgressDialogAsync(
        context,
        UnitStrings.createCopy,
        1,
        isBasic: true,
        futures: [
          () async {
            mediaCopied = await DbOccasions.duplicateOccasion(occasion.id!);
          },
        ],
      );
      if (!mounted) return;
      if (!created) {
        ToastHelper.Show(context, UnitStrings.createCopyFailed);
        return;
      }
      ToastHelper.Show(
          context,
          mediaCopied
              ? UnitStrings.createCopySuccess
              : UnitStrings.createCopyMediaFailed);
      try {
        await _loadOccasions();
      } catch (e) {
        if (!mounted) return;
        ToastHelper.Show(context, UnitStrings.loadEventFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final presentEvents = _filteredOccasions
        .where((o) => o.startTime!.isBefore(now) && o.endTime!.isAfter(now))
        .toList();
    final upcomingEvents =
        _filteredOccasions.where((o) => o.startTime!.isAfter(now)).toList();
    upcomingEvents.sort((a, b) => a.startTime!.compareTo(b.startTime!));
    final pastEvents =
        _filteredOccasions.where((o) => o.endTime!.isBefore(now)).toList();
    pastEvents.sort((a, b) => b.endTime!.compareTo(a.endTime!));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async {
                  await _loadOccasions();
                  if (!_savingLanding) await _loadLanding();
                },
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeaderControls()),
                    if (_filteredOccasions.isEmpty &&
                        _searchController.text.isNotEmpty)
                      SliverFillRemaining(
                          child: Center(child: Text(UnitStrings.noEventsFound)))
                    else ...[
                      if (presentEvents.isNotEmpty) ...[
                        _buildSectionHeader(
                            context, CommonStrings.happeningNow),
                        _buildGrid(presentEvents, isPresent: true),
                      ],
                      if (upcomingEvents.isNotEmpty) ...[
                        _buildSectionHeader(
                            context, CommonStrings.upcomingEvents),
                        _buildGrid(upcomingEvents),
                      ],
                      if (pastEvents.isNotEmpty) ...[
                        _buildSectionHeader(context, CommonStrings.pastEvents),
                        _buildGrid(pastEvents),
                      ],
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 64)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeaderControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            CommonStrings.events,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16.0),
          if (_landing == null || _landingFailed || _savingLanding) ...[
            _buildLandingStatus(),
            const SizedBox(height: 16),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              const double buttonWidthThreshold = 550.0;
              bool showButton = true;
              if (constraints.maxWidth < buttonWidthThreshold) {
                showButton = !_isSearching;
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _buildSearchField()),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) => SizeTransition(
                        sizeFactor: animation,
                        axis: Axis.horizontal,
                        child: child),
                    child: showButton
                        ? Row(
                            key: const ValueKey('add-button'),
                            children: [
                              const SizedBox(width: 16),
                              FilledButton.icon(
                                onPressed: _addNewEvent,
                                icon: const Icon(Icons.add, size: 18),
                                label: Text(UnitStrings.addNewEvent),
                                style: FilledButton.styleFrom(
                                  // This will force the button to be at least 48px tall.
                                  minimumSize: const Size(0, 48),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 10.0),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        StylesConfig.commonRoundness),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(key: ValueKey('empty-box')),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final theme = Theme.of(context);
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      decoration: InputDecoration(
        hintText: AdministrationStrings.findOccasionHint,
        prefixIcon: Icon(Icons.search, size: 20, color: theme.hintColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(StylesConfig.commonRoundness),
          borderSide: BorderSide(color: theme.dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(StylesConfig.commonRoundness),
          borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(StylesConfig.commonRoundness),
          borderSide: BorderSide(color: theme.primaryColor, width: 1.5),
        ),
        isDense: true,
        // Reduced vertical padding to make the search field smaller.
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                // By removing padding and constraints, the IconButton won't add extra vertical space.
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.clear, size: 20),
                onPressed: () => _searchController.clear(),
              )
            : null,
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }

  Widget _buildGrid(List<OccasionModel> occasions, {bool isPresent = false}) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 420,
          mainAxisExtent: 110,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final occasion = occasions[index];
            return OccasionEditCard(
              occasion: occasion,
              onTap: () => _handleView(occasion),
              onCreateCopy: () => _handleCreateCopy(occasion),
              isPresent: isPresent,
              isAppLanding: _landing?.enabled == true &&
                  _landing?.occasionId == occasion.id,
              onSetAppLanding: _landing?.enabled == true &&
                      _landing?.canManage == true &&
                      !_savingLanding &&
                      AppConfig.forceOccasionLink == null &&
                      (occasion.isOpen == true ||
                          _landing?.occasionId == occasion.id)
                  ? () => _setLanding(
                      _landing?.occasionId == occasion.id ? null : occasion.id)
                  : null,
            );
          },
          childCount: occasions.length,
        ),
      ),
    );
  }
}

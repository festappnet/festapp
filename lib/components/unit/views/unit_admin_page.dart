import 'package:fstapp/components/navigation/navigation_paths.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/components/_shared/app_panel_helper.dart';
import 'package:fstapp/components/_shared/red_strip_widget.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/unit_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/unit/views/occasions_screen.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/unit/views/quotes_tab.dart';
import 'package:fstapp/components/unit/views/unit_users_screen.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/unit/views/unit_settings_screen.dart';
import 'package:fstapp/components/email_templates/views/email_templates_tab.dart';
import '../../occasion/occasion_model.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

@RoutePage()
class UnitAdminPage extends StatefulWidget {
  final int? id;
  static const double contentMaxWidth = 1000;
  const UnitAdminPage({super.key, @pathParam required this.id});
  @override
  State<UnitAdminPage> createState() => _UnitAdminPageState();
}

class _UnitAdminPageState extends State<UnitAdminPage> {
  UnitModel? _unit;
  List<OccasionModel>? _occasions;
  bool _failed = false;
  int _generation = 0;
  bool _loading = false;
  StackRouter? _root;
  @override
  void initState() {
    super.initState();
    RightsService.occasionLinkModelNotifier.addListener(_contextChanged);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Localizations.localeOf(context);
    context.dependOnInheritedWidgetOfExactType<RouteDataScope>();
    final root = context.router.root;
    if (_root != root) {
      _root?.removeListener(_contextChanged);
      _root = root;
      root.addListener(_contextChanged);
    }
  }

  void _contextChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading || !context.routeData.isActive) return;
      if (RightsService.currentUnit()?.id != widget.id ||
          RightsService.currentOccasionId() != null)
        _load(force: true);
      else if (!AuthService.isLoggedIn())
        _load();
      else
        setState(() {
          _failed = !RightsService.isUnitEditorView();
        });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    ++_generation;
    _root?.removeListener(_contextChanged);
    RightsService.occasionLinkModelNotifier.removeListener(_contextChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(UnitAdminPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _unit = null;
      _occasions = null;
      _load();
    }
  }

  Future<void> _load({bool force = false}) async {
    final generation = ++_generation;
    _loading = true;
    final id = widget.id;
    if (id == null) {
      setState(() => _failed = true);
      _loading = false;
      return;
    }
    if (!AuthService.isLoggedIn()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          context.router.root.replace(LoginRoute(
              redirect: context.router.root.urlState.uri.toString()));
      });
      return;
    }
    try {
      await RightsService.updateAppData(
          unitId: id,
          force: force || RightsService.currentOccasionId() != null,
          refreshOffline: false);
      if (!mounted || generation != _generation) return;
      final unit = RightsService.currentUnit();
      if (unit?.id != id || !RightsService.isUnitEditorView()) {
        setState(() => _failed = true);
        return;
      }
      final occasions = await DbOccasions.getAllOccasionsForEdit(id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _unit = unit;
        _occasions = occasions;
        _failed = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (generation == _generation) _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = Scaffold(
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(UnitStrings.loadUnitFailed),
      TextButton(
          onPressed: () => _load(force: true), child: Text(CommonStrings.retry))
    ])));
    if (_failed && _unit == null) return failure;
    if (_unit == null ||
        RightsService.currentUnit()?.id != widget.id ||
        RightsService.currentOccasionId() != null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final denied = _failed || !RightsService.isUnitEditorView();
    return Stack(fit: StackFit.expand, children: [
      Offstage(
          offstage: denied,
          child: TickerMode(
              enabled: !denied,
              child: UnitAdministrationScope(
                  unit: _unit!,
                  occasions: _occasions,
                  onUpdated: () => _load(force: true),
                  child: const AutoRouter()))),
      if (denied) failure,
    ]);
  }
}

class UnitAdministrationScope extends InheritedWidget {
  final UnitModel unit;
  final List<OccasionModel>? occasions;
  final VoidCallback onUpdated;
  const UnitAdministrationScope(
      {super.key,
      required this.unit,
      required this.occasions,
      required this.onUpdated,
      required super.child});
  static UnitAdministrationScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UnitAdministrationScope>()!;
  @override
  bool updateShouldNotify(UnitAdministrationScope oldWidget) =>
      oldWidget.unit != unit || oldWidget.occasions != occasions;
}

class UnitAdministrationBody extends StatelessWidget {
  final List<RoutedTabDefinition> tabs;
  final TabController controller;
  final Widget child;
  const UnitAdministrationBody({
    super.key,
    required this.tabs,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: SideMenu.collapsedWidth),
        child: child,
      ),
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        child: SideMenu(tabs: tabs, controller: controller),
      ),
    ],
  );
}

class SideMenu extends StatefulWidget {
  final List<RoutedTabDefinition> tabs;
  final TabController controller;
  static const double collapsedWidth = 56;
  static const double expandedWidth = 220;
  const SideMenu({super.key, required this.tabs, required this.controller});
  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  bool _isExpanded = false;
  String? _hoveredLabel;
  @override
  Widget build(BuildContext context) => MouseRegion(
      onEnter: (_) => setState(() => _isExpanded = true),
      onExit: (_) => setState(() => _isExpanded = false),
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: _isExpanded ? SideMenu.expandedWidth : SideMenu.collapsedWidth,
          color: Theme.of(context).canvasColor,
          child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) =>
                  ListView(padding: EdgeInsets.zero, children: [
                    for (var i = 0; i < widget.tabs.length; i++)
                      _buildMenuItem(
                          context: context,
                          icon: widget.tabs[i].icon,
                          label: widget.tabs[i].label,
                          isSelected: widget.controller.index == i,
                          isExpanded: _isExpanded,
                          isHovered: _hoveredLabel == widget.tabs[i].label,
                          onHover: (label) =>
                              setState(() => _hoveredLabel = label),
                          onTap: () {
                            if (widget.controller.index != i)
                              widget.controller.index = i;
                          })
                  ]))));
  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isSelected,
    required bool isExpanded,
    required bool isHovered,
    required VoidCallback onTap,
    required Function(String?) onHover,
  }) {
    final bool isHighlighted = isSelected || isHovered;

    final Color highlightColor;
    if (Theme.of(context).brightness == Brightness.dark) {
      highlightColor = Colors.white.withOpacity(0.15);
    } else {
      highlightColor = Theme.of(context).splashColor;
    }

    const double horizontalMargin = 4.0;
    const double iconSize = 22.0;
    final double iconHorizontalPadding =
        (SideMenu.collapsedWidth - (horizontalMargin * 2) - iconSize) / 2;

    return MouseRegion(
      onEnter: (_) => onHover(label),
      onExit: (_) => onHover(null),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(
              horizontal: horizontalMargin, vertical: 2.0),
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          decoration: BoxDecoration(
            color: isHighlighted ? highlightColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: iconHorizontalPadding),
                child: Icon(icon, size: iconSize),
              ),
              Expanded(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 100),
                  opacity: isExpanded ? 1.0 : 0.0,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    softWrap: false,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@RoutePage()
class UnitOccasionsPage extends StatelessWidget {
  const UnitOccasionsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = UnitAdministrationScope.of(context);
    return Center(
        child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: UnitAdminPage.contentMaxWidth),
            child: OccasionsScreen(
                unit: scope.unit, initialOccasions: scope.occasions)));
  }
}

@RoutePage()
class UnitUsersPage extends StatelessWidget {
  const UnitUsersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = UnitAdministrationScope.of(context);
    return UnitUsersScreen(unit: scope.unit);
  }
}

@RoutePage()
class UnitEmailTemplatesPage extends StatelessWidget {
  const UnitEmailTemplatesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = UnitAdministrationScope.of(context);
    return EmailTemplatesTab(unitId: scope.unit.id!);
  }
}

@RoutePage()
class UnitSettingsPage extends StatelessWidget {
  const UnitSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = UnitAdministrationScope.of(context);
    return UnitSettingsScreen(unit: scope.unit, onUnitUpdated: scope.onUpdated);
  }
}

@RoutePage()
class UnitQuotesPage extends StatelessWidget {
  const UnitQuotesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = UnitAdministrationScope.of(context);
    return QuotesTab(unitId: scope.unit.id!);
  }
}

@RoutePage()
class UnitAdministrationTabsPage extends StatelessWidget {
  const UnitAdministrationTabsPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: RightsService.occasionLinkModelNotifier,
      builder: (context, _) => _build(context));
  Widget _build(BuildContext context) {
    Localizations.localeOf(context);
    context.dependOnInheritedWidgetOfExactType<RouteDataScope>();
    final scope = UnitAdministrationScope.of(context);
    final tabs = <RoutedTabDefinition>[
      RoutedTabDefinition(
          slug: NavigationPaths.occasions,
          route: const UnitOccasionsRoute(),
          label: CommonStrings.events,
          icon: Icons.calendar_month),
      if (RightsService.canSeeUnitUsers()) ...[
        RoutedTabDefinition(
            slug: NavigationPaths.users,
            route: const UnitUsersRoute(),
            label: CommonStrings.users,
            icon: Icons.people),
        RoutedTabDefinition(
            slug: NavigationPaths.emailTemplates,
            route: const UnitEmailTemplatesRoute(),
            label: UnitStrings.emailTemplates,
            icon: Icons.email),
        RoutedTabDefinition(
            slug: NavigationPaths.settings,
            route: const UnitSettingsRoute(),
            label: CommonStrings.settings,
            icon: Icons.settings)
      ],
      if (FeatureService.isFeatureEnabled(FeatureConstants.quotes,
          features: scope.unit.features))
        RoutedTabDefinition(
            slug: NavigationPaths.quotes,
            route: const UnitQuotesRoute(),
            label: UnitStrings.quotes,
            icon: Icons.format_quote),
      if (RightsService.isUnitEditor())
        RoutedTabDefinition(
            slug: NavigationPaths.bankAccounts,
            route: const UnitBankAccountsNavigationRoute(),
            label: BankAccountStrings.bankAccountsTitle,
            icon: Icons.account_balance),
    ];
    return RoutedTabScaffold(
        key: ValueKey(scope.unit.id),
        tabs: tabs,
        builder: (context, child, controller) => Column(children: [
              const SafeArea(bottom: false, child: RedStripWidget()),
              Expanded(
                  child: Scaffold(
                      appBar: AppPanelHelper.buildAdaptiveAdminAppBar(context),
                      body: UnitAdministrationBody(
                          tabs: tabs, controller: controller, child: child),
                      floatingActionButton: FloatingActionButton(
                          onPressed: () => RouterService.navigate(
                              context, 'unit/${scope.unit.id}'),
                          child: const Icon(Icons.remove_red_eye_rounded))))
            ]));
  }
}

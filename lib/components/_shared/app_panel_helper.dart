import 'package:fstapp/components/_shared/breadcrumb_row.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/project_picker_widget.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/forms/views/reservation_page.dart';
import 'package:fstapp/components/occasion/admin_page.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/occasion/occasion_creation_helper.dart';
import 'package:fstapp/components/unit/unit_creation_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/header/user_header_widget.dart';
import 'package:fstapp/widgets/logo_widget.dart';
import 'admin_strings.dart';

/// A simple, private helper class to neatly store information for our action menu.
class _ActionMenuItem {
  final String label;
  final IconData? icon;
  final VoidCallback onSelect;

  _ActionMenuItem({
    required this.label,
    this.icon,
    required this.onSelect,
  });

  // Override for correct comparison
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ActionMenuItem &&
          runtimeType == other.runtimeType &&
          label == other.label;

  @override
  int get hashCode => label.hashCode;
}

class AppPanelHelper {
  /// This method returns a breadcrumb widget for navigating units and occasions.
  /// This is now primarily used for the desktop layout.
  static Widget _buildBreadcrumbs(
      BuildContext originalContext, BuildContext context) {
    final allUnits = RightsService.currentUser()?.units ?? [];
    final currentUnit = RightsService.currentUnit();
    final occasionsInCurrentUnit = RightsService.currentUser()?.occasions ?? [];
    final currentOccasion = RightsService.currentOccasion();

    List<Widget> breadcrumbItems = [];

    // Unit Selector
    if (currentUnit != null) {
      breadcrumbItems.add(_buildBreadcrumbSegment<UnitModel>(
        context: context,
        title: currentUnit.title ?? '---',
        isBold: currentOccasion == null,
        items: allUnits,
        selectedItem: currentUnit,
        itemTitleBuilder: (item) => item.title ?? '---',
        itemIdBuilder: (item) => item.id,
        onItemSelected: (item) async {
          await RouterService.navigateToUnitAdmin(originalContext, item);
        },
        onCreateNew: (RightsService
                    .occasionLinkModel?.organization?.isUnitCreationEnabled ==
                true)
            ? () async {
                final newUnit =
                    await UnitCreationHelper.createNewUnit(originalContext);
                if (newUnit != null) {
                  await RouterService.navigateToUnitAdmin(
                      originalContext, newUnit);
                }
              }
            : null,
        onTitleTap: () async => await RouterService.navigateToUnitAdmin(
            originalContext, currentUnit),
        searchHintText: AdministrationStrings.findUnitHint,
        createNewText: AdministrationStrings.newUnitButton,
      ));
    }

    // Separator, Occasion Selector, and new Action Selector
    // Skip on unit-level pages (e.g. /unit/5/edit) where occasion context is stale
    // App-bar builders can inherit a different route scope than the page.
    final currentRoutePath = originalContext.routeData.path;
    final isUnitLevelPage = currentRoutePath.contains('/unit/') &&
        currentRoutePath.contains('/edit');
    if (currentUnit != null && currentOccasion != null && !isUnitLevelPage) {
      final onAppBarColor =
          Theme.of(context).appBarTheme.foregroundColor ?? Colors.white;
      // Separator
      breadcrumbItems.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: Text("/",
            style:
                TextStyle(fontSize: 16, color: onAppBarColor.withOpacity(0.4))),
      ));

      // Occasion Selector
      breadcrumbItems.add(_buildBreadcrumbSegment<OccasionModel>(
        context: context,
        title: currentOccasion.title ?? '---',
        isBold: true,
        items: occasionsInCurrentUnit,
        selectedItem: currentOccasion,
        itemTitleBuilder: (item) => item.title ?? '---',
        itemIdBuilder: (item) => item.id,
        itemDateBuilder: (item) => item.startTime,
        onItemSelected: (item) async {
          if (item.link != null) {
            await RouterService.navigateToOccasionAdministration(
                originalContext,
                occasion: item);
          }
        },
        onCreateNew: !RightsService.isUnitEditor()
            ? null
            : () async {
                final newOccasion =
                    await OccasionCreationHelper.createNewOccasion(
                        originalContext, currentUnit, occasionsInCurrentUnit);
                if (newOccasion != null && newOccasion.link != null) {
                  await RouterService.navigateToOccasionAdministration(
                      originalContext,
                      occasionLink: newOccasion.link!);
                }
              },
        onTitleTap: () async {
          if (currentOccasion.link != null) {
            await RouterService.navigateToOccasionAdministration(
                originalContext,
                occasionLink: currentOccasion.link!,
                occasion: currentOccasion);
          }
        },
        searchHintText: AdministrationStrings.findOccasionHint,
        createNewText: AdministrationStrings.newOccasionButton,
      ));

      // Build the state-aware action menu
      if (AppConfig.isAppSupported) {
        final adminAction = _ActionMenuItem(
          label: CommonStrings.eventManagement,
          icon: Icons.admin_panel_settings,
          onSelect: () async =>
              await RouterService.navigateOccasion(context, AdminPage.ROUTE),
        );

        final viewAppAction = _ActionMenuItem(
          label: AdministrationStrings.viewApp,
          icon: Icons.visibility,
          onSelect: () async =>
              await RouterService.navigateOccasion(context, ""),
        );

        final reservationsAction = _ActionMenuItem(
          label: AdministrationStrings.reservations,
          icon: Icons.shopping_cart,
          onSelect: () async => await RouterService.navigateOccasion(
              context, ReservationsPage.ROUTE),
        );

        final List<_ActionMenuItem> availableActions = [];

        if (FeatureService.isFeatureEnabled(FeatureConstants.form,
                features: currentOccasion.features) &&
            RightsService.canSeeReservations()) {
          availableActions.add(reservationsAction);
        }

        // Condition for Event Management: User has editor view rights
        if (RightsService.canSeeAdministration()) {
          availableActions.add(adminAction);
        }

        // View App is always available if the app is supported
        availableActions.add(viewAppAction);

        _ActionMenuItem currentAction;

        if (currentRoutePath.endsWith(ReservationsPage.ROUTE)) {
          currentAction = reservationsAction;
        } else if (currentRoutePath.endsWith(AdminPage.ROUTE)) {
          currentAction = adminAction;
        } else {
          currentAction = viewAppAction;
        }

        if (availableActions.length > 1) {
          breadcrumbItems.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text("/",
                style: TextStyle(
                    fontSize: 16, color: onAppBarColor.withOpacity(0.4))),
          ));
          breadcrumbItems.add(_buildActionPickerSegment(
            context: context,
            currentAction: currentAction,
            availableActions: availableActions,
          ));
        }
      }
    }

    return BreadcrumbRow(
      children: breadcrumbItems,
    );
  }

  /// A dedicated builder for the final action picker segment.
  static Widget _buildActionPickerSegment({
    required BuildContext context,
    required _ActionMenuItem currentAction,
    required List<_ActionMenuItem> availableActions,
    bool iconOnly = false,
  }) {
    final theme = Theme.of(context);
    final onAppBarColor = theme.appBarTheme.foregroundColor ?? Colors.white;
    final textStyle = TextStyle(
        fontSize: 16, color: onAppBarColor, fontWeight: FontWeight.bold);
    final iconColor = onAppBarColor.withOpacity(0.7);
    final hoverColor = Colors.black.withOpacity(0.15);

    Widget visiblePart;
    if (iconOnly && currentAction.icon != null) {
      visiblePart = Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 2, 6),
        child: Icon(currentAction.icon, color: onAppBarColor, size: 24),
      );
    } else {
      visiblePart = Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentAction.icon != null) ...[
              Icon(currentAction.icon, color: onAppBarColor, size: 18),
              const SizedBox(width: 6),
            ],
            Text(currentAction.label, style: textStyle),
          ],
        ),
      );
    }

    // The entire segment is now the trigger for the custom dialog
    return Builder(builder: (buttonContext) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            hoverColor: hoverColor,
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              _showActionPicker(
                  buttonContext: buttonContext,
                  currentAction: currentAction,
                  availableActions: availableActions);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                visiblePart,
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child:
                      Icon(Icons.arrow_drop_down, color: iconColor, size: 22),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  /// Displays a custom rounded dialog for selecting an action.
  static void _showActionPicker({
    required BuildContext buttonContext,
    required _ActionMenuItem currentAction,
    required List<_ActionMenuItem> availableActions,
  }) {
    final overlay = Overlay.of(buttonContext);
    late OverlayEntry overlayEntry;

    final renderBox = buttonContext.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    final menuActions =
        availableActions.where((action) => action != currentAction).toList();

    final theme = Theme.of(buttonContext);
    final isDarkMode = theme.brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.grey[300] : Colors.grey[800];
    final listIconColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];
    final titleTextStyle =
        theme.textTheme.bodyMedium?.copyWith(color: textColor);

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                onTap: () => overlayEntry.remove(),
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned(
              top: offset.dy + size.height + 8,
              left: offset.dx,
              child: Material(
                elevation: 4.0,
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFF2D2D2D)
                    : Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0)),
                child: SizedBox(
                  width: 240,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    shrinkWrap: true,
                    children: menuActions.map((action) {
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 0),
                        leading: action.icon != null
                            ? Icon(action.icon, size: 20, color: listIconColor)
                            : null,
                        title: Text(
                          action.label,
                          style: titleTextStyle,
                        ),
                        onTap: () {
                          overlayEntry.remove();
                          action.onSelect();
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(overlayEntry);
  }

  /// Builds a single, hoverable segment of the breadcrumb.
  static Widget _buildBreadcrumbSegment<T>({
    required BuildContext context,
    required String title,
    required List<T> items,
    required T selectedItem,
    required String Function(T) itemTitleBuilder,
    required Object? Function(T) itemIdBuilder,
    required Function(T) onItemSelected,
    required VoidCallback? onCreateNew,
    required VoidCallback onTitleTap,
    required String searchHintText,
    required String createNewText,
    DateTime? Function(T item)? itemDateBuilder,
    bool isBold = false,
  }) {
    final theme = Theme.of(context);
    final onAppBarColor = theme.appBarTheme.foregroundColor ?? Colors.white;
    final textStyle = TextStyle(
        fontSize: 17,
        color: onAppBarColor,
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal);
    // The bold face is Gill Sans; keep both title weights on Futura's line metrics.
    final titleStrut = StrutStyle(
      fontFamily: ThemeConfig.fontFamily,
      fontSize: 17,
      fontWeight: FontWeight.normal,
      forceStrutHeight: true,
    );
    final iconColor = onAppBarColor.withOpacity(0.7);
    final hoverColor = Colors.black.withOpacity(0.15);

    if (items.length <= 1 && onCreateNew == null) {
      return InkWell(
        onTap: onTitleTap,
        hoverColor: hoverColor,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          child: Text(title,
              style: textStyle,
              strutStyle: titleStrut,
              overflow: TextOverflow.ellipsis),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTitleTap,
            hoverColor: hoverColor,
            child: Padding(
              padding:
                  const EdgeInsets.only(left: 8, right: 6, top: 6, bottom: 6),
              child: Text(
                title,
                style: textStyle,
                strutStyle: titleStrut,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Builder(
            builder: (BuildContext inkWellContext) {
              return InkWell(
                onTap: () {
                  _showPicker<T>(
                    context: inkWellContext,
                    items: items,
                    selectedItem: selectedItem,
                    itemTitleBuilder: itemTitleBuilder,
                    itemIdBuilder: itemIdBuilder,
                    itemDateBuilder: itemDateBuilder,
                    onItemSelected: onItemSelected,
                    onCreateNew: onCreateNew,
                    searchHintText: searchHintText,
                    createNewText: createNewText,
                    happeningNowText: itemDateBuilder != null
                        ? CommonStrings.happeningNow
                        : null,
                    upcomingText: itemDateBuilder != null
                        ? CommonStrings.upcomingEvents
                        : null,
                    pastText: itemDateBuilder != null
                        ? CommonStrings.pastEvents
                        : null,
                  );
                },
                hoverColor: hoverColor,
                child: Padding(
                  padding: const EdgeInsets.only(
                      left: 2, right: 4, top: 6, bottom: 6),
                  child: Transform.scale(
                    scaleY: 0.8,
                    child: Icon(Icons.unfold_more_rounded,
                        size: 20, color: iconColor),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Displays the custom picker using a direct Overlay for precise positioning and dismissibility.
  static void _showPicker<T>({
    required BuildContext context,
    required List<T> items,
    required T selectedItem,
    required String Function(T) itemTitleBuilder,
    required Object? Function(T) itemIdBuilder,
    required Function(T) onItemSelected,
    required VoidCallback? onCreateNew,
    required String searchHintText,
    required String createNewText,
    DateTime? Function(T item)? itemDateBuilder,
    String? happeningNowText,
    String? upcomingText,
    String? pastText,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final pickerTopPosition = offset.dy + size.height + 8;
    // Calculate available height, leaving some padding at the bottom.
    final availableHeight = screenHeight - pickerTopPosition - 16;

    const pickerWidth = 300.0;
    const screenPadding = 8.0;
    double finalLeft = offset.dx;

    // Adjust horizontal position to keep the picker on screen
    if (finalLeft + pickerWidth > screenWidth) {
      finalLeft = screenWidth - pickerWidth - screenPadding;
    }
    if (finalLeft < screenPadding) {
      finalLeft = screenPadding;
    }

    overlayEntry = OverlayEntry(
      builder: (context) {
        return FocusScope(
          node: FocusScopeNode(),
          autofocus: true,
          child: RawKeyboardListener(
            focusNode: FocusNode(),
            onKey: (RawKeyEvent event) {
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                overlayEntry.remove();
              }
            },
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => overlayEntry.remove(),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  left: finalLeft,
                  top: pickerTopPosition,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      // Ensure a minimum height but don't overflow the screen.
                      maxHeight: availableHeight < 150 ? 150 : availableHeight,
                    ),
                    child: Material(
                      elevation: 4.0,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF2D2D2D)
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0)),
                      child: ProjectPicker<T>(
                        onDismiss: () => overlayEntry.remove(),
                        items: items,
                        selectedItem: selectedItem,
                        itemTitleBuilder: itemTitleBuilder,
                        itemIdBuilder: itemIdBuilder,
                        itemDateBuilder: itemDateBuilder,
                        onItemSelected: onItemSelected,
                        onCreateNew: onCreateNew,
                        hintText: searchHintText,
                        createNewText: createNewText,
                        happeningNowText: happeningNowText,
                        upcomingText: upcomingText,
                        pastText: pastText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    overlay.insert(overlayEntry);
  }

  /// This method returns an adaptive AppBar based on the screen width.
  static PreferredSizeWidget buildAdaptiveAdminAppBar(BuildContext context,
      {List<RoutedTabDefinition>? activeTabs, TabController? tabController}) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Use a more standard breakpoint for mobile vs. desktop layouts.
    if (screenWidth < 720) {
      return buildProfessionalMobileAdminAppBar(
          context, activeTabs, tabController);
    } else {
      return buildDesktopAdminAppBar(context, activeTabs, tabController);
    }
  }

  /// Desktop/Tablet version of the AppBar.
  static PreferredSizeWidget buildDesktopAdminAppBar(
    BuildContext context,
    List<RoutedTabDefinition>? activeTabs,
    TabController? tabController,
  ) {
    final compact = activeTabs != null;
    return AppBar(
      toolbarHeight: compact ? 52 : 60,
      automaticallyImplyLeading: false,
      // Use a fully custom title area
      leading: null,
      titleSpacing: 0.0,
      // No default spacing
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo on the far left, acting like a leading widget
          GestureDetector(
            onTap: () async {
              await RouterService.navigateHome(context);
            },
            child: Padding(
              // Add padding to space it from the screen edge and from the breadcrumbs
              padding:
                  EdgeInsets.fromLTRB(16, compact ? 6 : 8, 24, compact ? 6 : 8),
              child: LogoWidget(height: 40, forceDark: true),
            ),
          ),
          // Breadcrumbs take up the remaining space
          Expanded(
            child: ValueListenableBuilder<OccasionLinkModel?>(
              valueListenable: RightsService.occasionLinkModelNotifier,
              builder: (listenableContext, _, __) {
                return _buildBreadcrumbs(context, listenableContext);
              },
            ),
          ),
        ],
      ),

      actions: [
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: UserHeaderWidget(
              compact: compact,
              appBarIconColor: ThemeConfig.lllBackground,
            ))
      ],
      bottom: activeTabs == null
          ? null
          : _buildAdminTabs(context, activeTabs, tabController),
    );
  }

  /// A professionally redesigned mobile version of the AppBar with Unit switcher on the left.
  static PreferredSizeWidget buildProfessionalMobileAdminAppBar(
    BuildContext context,
    List<RoutedTabDefinition>? activeTabs,
    TabController? tabController,
  ) {
    final onAppBarColor =
        Theme.of(context).appBarTheme.foregroundColor ?? Colors.white;
    final iconColor = onAppBarColor.withOpacity(0.9);
    final separatorColor = onAppBarColor.withOpacity(0.5);

    return AppBar(
      automaticallyImplyLeading: false,
      leadingWidth: 56,
      titleSpacing: 4.0,
      leading: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: GestureDetector(
          onTap: () async {
            await RouterService.navigateHome(context);
            // final currentUnit = RightsService.currentUnit();
            // if (currentUnit != null &&
            //     RightsService.canUserSeeUnitWorkspace()) {
            //   // This 'context' is correct (it's the one passed into the function)
            //   await RouterService.navigateToUnitAdmin(context, currentUnit);
            // }
          },
          child: LogoWidget(height: 40, forceDark: true),
        ),
      ),
      title: ValueListenableBuilder<OccasionLinkModel?>(
        valueListenable: RightsService.occasionLinkModelNotifier,
        builder: (listenableContext, _, __) {
          final allUnits = RightsService.currentUser()?.units ?? [];
          final currentUnit = RightsService.currentUnit();
          final occasionsInUnit = RightsService.currentUser()?.occasions ?? [];
          final currentOccasion = RightsService.currentOccasion();

          if (currentUnit == null) return const SizedBox.shrink();

          return Row(
            children: [
              Flexible(
                flex: 2,
                child: (allUnits.length <= 1 &&
                        (RightsService.occasionLinkModel?.organization
                                ?.isUnitCreationEnabled !=
                            true))
                    ? TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: onAppBarColor,
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.normal),
                        ),
                        onPressed: () async {
                          await RouterService.navigateToUnitAdmin(
                              context, currentUnit);
                        },
                        child: Text(
                          currentUnit.title ?? '---',
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    // If multiple units, display the picker button.
                    : Builder(builder: (buttonContext) {
                        return TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: onAppBarColor,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            textStyle:
                                const TextStyle(fontWeight: FontWeight.normal),
                          ),
                          onPressed: () => _showPicker<UnitModel>(
                            context: buttonContext,
                            items: allUnits,
                            selectedItem: currentUnit,
                            itemTitleBuilder: (i) => i.title ?? '---',
                            itemIdBuilder: (i) => i.id,
                            onItemSelected: (item) async =>
                                await RouterService.navigateToUnitAdmin(
                                    context, item),
                            onCreateNew: (RightsService.occasionLinkModel
                                        ?.organization?.isUnitCreationEnabled ==
                                    true)
                                ? () async {
                                    final newUnit =
                                        await UnitCreationHelper.createNewUnit(
                                            context);
                                    if (newUnit != null) {
                                      await RouterService.navigateToUnitAdmin(
                                          context, newUnit);
                                    }
                                  }
                                : null,
                            searchHintText: AdministrationStrings.findUnitHint,
                            createNewText: AdministrationStrings.newUnitButton,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                  child: Text(currentUnit.title ?? '---',
                                      overflow: TextOverflow.ellipsis)),
                              Icon(Icons.unfold_more_rounded,
                                  size: 20, color: iconColor),
                            ],
                          ),
                        );
                      }),
              ),
              if (currentOccasion != null) ...[
                // Separator
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: Text("/",
                      style: TextStyle(fontSize: 16, color: separatorColor)),
                ),
                // Occasion Switcher still has priority with a higher flex factor.
                Flexible(
                  flex: 5,
                  child: Builder(builder: (buttonContext) {
                    return TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: onAppBarColor,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _showPicker<OccasionModel>(
                        context: buttonContext,
                        items: occasionsInUnit,
                        selectedItem: currentOccasion,
                        itemTitleBuilder: (i) => i.title ?? '---',
                        itemIdBuilder: (i) => i.id,
                        itemDateBuilder: (i) => i.startTime,
                        onItemSelected: (item) async {
                          if (item.link != null) {
                            await RouterService
                                .navigateToOccasionAdministration(context,
                                    occasionLink: item.link!, occasion: item);
                          }
                        },
                        onCreateNew: null,
                        searchHintText: AdministrationStrings.findOccasionHint,
                        createNewText: AdministrationStrings.newOccasionButton,
                        happeningNowText: CommonStrings.happeningNow,
                        upcomingText: CommonStrings.upcomingEvents,
                        pastText: CommonStrings.pastEvents,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                              child: Text(currentOccasion.title ?? '---',
                                  overflow: TextOverflow.ellipsis)),
                          Icon(Icons.unfold_more_rounded,
                              size: 20, color: iconColor),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        ValueListenableBuilder<OccasionLinkModel?>(
          valueListenable: RightsService.occasionLinkModelNotifier,
          builder: (listenableContext, _, __) {
            final currentOccasion = RightsService.currentOccasion();
            if (currentOccasion == null || !AppConfig.isAppSupported) {
              return const SizedBox.shrink();
            }

            final actions = <_ActionMenuItem>[];

            // Condition for Reservations: Feature enabled AND user has order view rights
            if (FeatureService.isFeatureEnabled(FeatureConstants.form,
                    features: currentOccasion.features) &&
                RightsService.canSeeReservations()) {
              actions.add(_ActionMenuItem(
                  label: AdministrationStrings.reservations,
                  icon: Icons.shopping_cart,
                  onSelect: () async => await RouterService.navigateOccasion(
                      context, ReservationsPage.ROUTE)));
            }

            // Condition for Event Management: User has editor view rights
            if (RightsService.canSeeAdministration()) {
              actions.add(_ActionMenuItem(
                  label: CommonStrings.eventManagement,
                  icon: Icons.admin_panel_settings,
                  onSelect: () async => await RouterService.navigateOccasion(
                      context, AdminPage.ROUTE)));
            }

            if (RightsService.isAdmin()) {
              final orgId = RightsService.currentUnit()?.organization ??
                  RightsService.currentUser()?.units?.firstOrNull?.organization;
              if (orgId != null) {
                actions.add(_ActionMenuItem(
                    label: "Organization Settings",
                    icon: Icons.settings_applications,
                    onSelect: () async => await RouterService.navigate(
                        context, "/organizationEdit/$orgId")));
              }
            }

            // View App is always available if the app is supported
            actions.add(_ActionMenuItem(
                label: AdministrationStrings.viewApp,
                icon: Icons.visibility,
                onSelect: () async =>
                    await RouterService.navigateOccasion(context, "")));

            if (actions.length <= 1) return const SizedBox.shrink();

            // Action menu
            return PopupMenuButton<_ActionMenuItem>(
              icon: Icon(Icons.more_vert, color: iconColor),
              tooltip: CommonStrings.moreOptions,
              onSelected: (action) => action.onSelect(),
              itemBuilder: (BuildContext context) {
                return actions.map((_ActionMenuItem action) {
                  return PopupMenuItem<_ActionMenuItem>(
                    value: action,
                    child: Row(
                      children: [
                        if (action.icon != null) ...[
                          Icon(action.icon,
                              size: 20,
                              color:
                                  Theme.of(context).textTheme.bodyLarge?.color),
                          const SizedBox(width: 12),
                        ],
                        Text(action.label),
                      ],
                    ),
                  );
                }).toList();
              },
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(right: 4.0),
          child: UserHeaderWidget(appBarIconColor: ThemeConfig.lllBackground),
        ),
      ],
      bottom: activeTabs == null
          ? null
          : _buildAdminTabs(context, activeTabs, tabController),
    );
  }

  static PreferredSizeWidget _buildAdminTabs(
    BuildContext context,
    List<RoutedTabDefinition> tabs,
    TabController? controller,
  ) {
    final theme = Theme.of(context);
    final foreground = theme.appBarTheme.foregroundColor ??
        ThemeConfig.textColorForBackground(ThemeConfig.appBarColor());
    final fontSize = theme.textTheme.labelLarge?.fontSize ?? 14;
    final height = (MediaQuery.textScalerOf(context).scale(fontSize) + 24)
        .clamp(38.0, double.infinity);
    final tabBar = TabBar(
      controller: controller,
      onTap: (index) =>
          resetNestedTabs(context.tabsRouter, tabs[index].route.routeName),
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelColor: foreground,
      unselectedLabelColor: foreground.withValues(alpha: 0.8),
      indicatorColor: ThemeConfig.seed2,
      indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: ThemeConfig.seed2, width: 2)),
      tabs: tabs
          .map((tab) => Tab(
                height: height,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tab.icon),
                    const SizedBox(width: 8),
                    Text(tab.label),
                  ],
                ),
              ))
          .toList(),
    );
    // AppBar centers an intrinsically sized scrollable strip. Give this
    // administration strip the full width so its start alignment stays left.
    return PreferredSize(
      preferredSize: tabBar.preferredSize,
      child: SizedBox(width: double.infinity, child: tabBar),
    );
  }
}

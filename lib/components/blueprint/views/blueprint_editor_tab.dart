import 'dart:convert';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:fstapp/components/blueprint/blueprint_group.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:collection/collection.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

import '../../_shared/common_strings.dart';
import '../../eshop/db_tickets.dart';
import '../blueprint_seat.dart';
import '../seat_reservation/widgets/seat_reservation_widget.dart';
import 'blueprint_controls_bar.dart';
import 'blueprint_create_order_dialog.dart';
import 'blueprint_groups_panel.dart';
import 'blueprint_legend.dart';
import 'blueprint_mobile_scroll_view.dart';
import 'blueprint_product_dialogs.dart';

enum BlueprintSelectionMode {
  none,
  emptyArea,
  addBlack,
  addAvailable,
  swapSeats,
  createNewOrder
}

class BlueprintTab extends StatefulWidget {
  const BlueprintTab(
      {super.key, this.prototypeBlueprint, this.onPrototypeSave});

  /// Runs the existing editor against an in-memory plan for the setup demo.
  const BlueprintTab.prototype({
    super.key,
    required this.prototypeBlueprint,
    required this.onPrototypeSave,
  });

  final BlueprintModel? prototypeBlueprint;
  final ValueChanged<BlueprintModel>? onPrototypeSave;

  @override
  State<BlueprintTab> createState() => _BlueprintTabState();
}

class _BlueprintTabState extends State<BlueprintTab> {
  final _snapshot = EditorSnapshot();
  String? _prototypeBaseline;
  Object? get _draft => blueprint == null
      ? null
      : {
          'title': blueprint!.title,
          'data': blueprint!.data,
          'configuration': blueprint!.configuration,
          'groups': blueprint!.groups,
          'background_svg': blueprint!.backgroundSvg,
          'objects':
              _seatLayoutController.slots.map((s) => s.seat).nonNulls.toList(),
        };
  BlueprintModel? blueprint;
  BlueprintGroupModel? currentGroup;
  String? occasionLink;

  BlueprintSelectionMode currentSelectionMode = BlueprintSelectionMode.none;
  late final VenueSeatController<BlueprintObjectModel, Object>
      _seatLayoutController;

  // State for Swap Seats feature
  BlueprintSeat? _seatToSwap1;
  BlueprintSeat? _seatToSwap2;

  // State for Create New Order feature
  final Set<BlueprintSeat> _selectedSeatsForOrder = {};
  bool _initialLoadStarted = false;
  bool get _isPrototype => widget.prototypeBlueprint != null;
  bool get _canEdit => _isPrototype || RightsService.canEditOccasion();

  @override
  void initState() {
    super.initState();
    _seatLayoutController = VenueSeatController<BlueprintObjectModel, Object>(
      adapter: blueprintSeatAdapter,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isPrototype) {
      if (!_initialLoadStarted) {
        _initialLoadStarted = true;
        loadData();
      }
      return;
    }
    if (occasionLink == null &&
        context.routeData.inheritedPathParams.isNotEmpty) {
      occasionLink = context.routeData.inheritedPathParams
          .getString(AppRouter.linkFormatted);
    }
    loadData();
  }

  @override
  void dispose() {
    if (_isPrototype && blueprint != null) {
      blueprint!.objects =
          _seatLayoutController.slots.map((s) => s.seat).nonNulls.toList();
      widget.onPrototypeSave?.call(blueprint!);
    }
    _seatLayoutController.dispose();
    super.dispose();
  }

  /// Helper to check if a seat is in a state that prevents modification
  bool _isSeatOccupied(BlueprintObjectModel? obj) {
    if (obj == null || obj.stateEnum == null) return false;
    final state = obj.stateEnum;
    return state == BlueprintSeatState.ordered ||
        state == BlueprintSeatState.used ||
        state == BlueprintSeatState.selected ||
        state == BlueprintSeatState.selectedByMe;
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        Container(
          width: 250,
          padding: const EdgeInsets.all(16.0),
          child: _buildLeftPanel(),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMainContent(),
        ),
        const SizedBox(width: 16),
        Container(
          width: 250,
          padding: const EdgeInsets.all(16.0),
          child: _buildRightPanel(),
        ),
      ],
    );
  }

  /// Left Panel: The Legend and Action Buttons
  Widget _buildLeftPanel() {
    final Map<BlueprintSeatState, int> stateCounts = {};
    if (blueprint?.objects != null) {
      for (var obj in blueprint!.objects!) {
        // Only count actual spots, not potential auxiliary objects if any
        if (obj.type == BlueprintModel.metaSpotType) {
          final state = obj.stateEnum ?? BlueprintSeatState.available;
          stateCounts[state] = (stateCounts[state] ?? 0) + 1;
        }
      }
    }

    return BlueprintLegend(
      currentSelectionMode: currentSelectionMode,
      onModeSelected: _handleModeSelected,
      // Pass the count and the callback for the Create Order button
      selectedCount: _selectedSeatsForOrder.length,
      onConfirmOrder: _processNewOrder,
      stateCounts: stateCounts,
      allowOrderActions: !_isPrototype,
    );
  }

  /// Main Content: Controls and Seat Layout
  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        blueprint == null
            ? const SizedBox.shrink()
            : BlueprintControlsBar(
                blueprint: blueprint,
                seatLayoutController: _seatLayoutController,
                canEdit: _canEdit,
                allowRemoteUpload: !_isPrototype,
              ),
        const SizedBox(height: 16),
        Flexible(
          child: blueprint == null
              ? const Center(child: CircularProgressIndicator())
              : TooltipTheme(
                  data: TooltipThemeData(
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .inverseSurface
                          .withValues(alpha: .95),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onInverseSurface,
                        ),
                  ),
                  child: VenueSeatViewer<BlueprintObjectModel, Object>(
                    editorMode: true,
                    controller: _seatLayoutController,
                    onSeatPressed: handleSeatTap,
                    tooltipBuilder: (context, slot) =>
                        slot.seat?.blueprintTooltip(context) ?? '',
                    shouldShowTooltipOnTap: (_) =>
                        currentSelectionMode == BlueprintSelectionMode.none,
                  )),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Right Panel: The Groups List
  Widget _buildRightPanel() {
    final bool canEdit = _canEdit;
    return BlueprintGroupsPanel(
      blueprint: blueprint,
      currentGroup: currentGroup,
      canEdit: canEdit,
      onGroupSelected: _onGroupSelected,
      onAddGroup: canEdit ? addGroup : null,
      onDeleteGroup: canEdit ? deleteGroup : null,
      onEditGroupProduct: canEdit && !_isPrototype ? _editGroupProduct : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _seatLayoutController.showTooltipFor(null),
          behavior: HitTestBehavior.translucent,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 800) {
                return _buildDesktopLayout();
              } else {
                return BlueprintMobileScrollView(
                  screenWidth: constraints.maxWidth,
                  leftPanel: _buildLeftPanel(),
                  mainContent: _buildMainContent(),
                  rightPanel: _buildRightPanel(),
                );
              }
            },
          ),
        ),
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _seatLayoutController,
        builder: (context, _) => EditorActionBar(
          hasChanges: blueprint != null && _snapshot.differs(_draft),
          enabled: _canEdit,
          onSave: saveChanges,
          onDiscard: loadData,
        ),
      ),
    );
  }

  //
  // LOGIC & HANDLERS
  //

  void _onGroupSelected(BlueprintGroupModel? group) {
    setState(() {
      currentGroup = group;
    });
    _seatLayoutController.showTooltipFor(null);
    _seatLayoutController.highlightGroup(currentGroup?.id);
  }

  /// Handles mode changes. Toggles off if the same mode is clicked.
  void _handleModeSelected(BlueprintSelectionMode mode) {
    if (_isPrototype &&
        (mode == BlueprintSelectionMode.createNewOrder ||
            mode == BlueprintSelectionMode.swapSeats)) return;
    // 1. If clicking the SAME mode, toggle it OFF.
    if (currentSelectionMode == mode) {
      _resetAllSelections();
      _seatLayoutController.showTooltipFor(null);
      setState(() {
        currentSelectionMode = BlueprintSelectionMode.none;
      });
      return;
    }

    // 2. If clicking a DIFFERENT mode, clear previous state and switch.
    _resetAllSelections();
    _seatLayoutController.showTooltipFor(null);

    setState(() {
      currentSelectionMode = mode;
    });

    // Toast helpers for complex modes
    if (mode == BlueprintSelectionMode.swapSeats) {
      ToastHelper.Show(context, BlueprintStrings.swapHelpSelectFirst);
    } else if (mode == BlueprintSelectionMode.createNewOrder) {
      ToastHelper.Show(context, BlueprintStrings.createOrderHelp);
    }
  }

  /// Clears temporary selections (Swap or Create Order) and resets visuals.
  void _resetAllSelections() {
    // Clear Swap Highlighting
    if (_seatToSwap1 != null) {
      _seatLayoutController.setSwapHighlight(_seatToSwap1!, false);
    }
    if (_seatToSwap2 != null) {
      _seatLayoutController.setSwapHighlight(_seatToSwap2!, false);
    }
    _seatToSwap1 = null;
    _seatToSwap2 = null;

    // Clear Create Order Selections
    for (var seat in _selectedSeatsForOrder) {
      // Revert the visual state to the actual data state
      _seatLayoutController.setSelection(seat, false);
    }
    _selectedSeatsForOrder.clear();
  }

  void addGroup() async {
    final defaultName = "${blueprint!.groups!.length + 1}";

    final newTitle = await DialogHelper.showInputDialog(
      context: context,
      dialogTitle: CommonStrings.addNew,
      labelText: BlueprintStrings.dialogGroupNumber,
      initialValue: defaultName,
    );

    if (newTitle != null && newTitle.isNotEmpty) {
      final newGroup = BlueprintGroupModel(
          title: newTitle, id: blueprint!.getFirstAvailableGroupId());

      setState(() {
        blueprint!.groups!.add(newGroup);
        blueprint!.groups!
            .sort((a, b) => Utilities.naturalCompare(a.title!, b.title!));
        currentGroup = newGroup;
      });
      _seatLayoutController.highlightGroup(currentGroup?.id);
    }
  }

  void deleteGroup() {
    if (currentGroup == null) return;
    final bool hasOccupiedSeats = currentGroup!.objects.any(_isSeatOccupied);

    if (hasOccupiedSeats) {
      ToastHelper.Show(context, BlueprintStrings.toastOccupiedCannotBeChanged,
          severity: ToastSeverity.NotOk);
      return;
    }

    final objectsToRemove =
        List<BlueprintObjectModel>.from(currentGroup!.objects);

    for (var obj in objectsToRemove) {
      blueprint!.objects!.remove(obj);
      final slot = _seatLayoutController.slotAt(obj.seatRow, obj.seatColumn);
      if (slot != null) _seatLayoutController.removeSeat(slot);
    }

    setState(() {
      blueprint!.groups!.remove(currentGroup);
      currentGroup = null;
    });
    _seatLayoutController.highlightGroup(null);
  }

  /// Main Tap Handler
  void handleSeatTap(BlueprintSeat model) {
    if (currentSelectionMode != BlueprintSelectionMode.createNewOrder &&
        _isSeatOccupied(model.seat)) {
      if (currentSelectionMode == BlueprintSelectionMode.none) {
        // Do nothing; the package layout handles the tooltip.
        return;
      }
      if (currentSelectionMode != BlueprintSelectionMode.swapSeats) {
        ToastHelper.Show(context, BlueprintStrings.toastOccupiedCannotBeChanged,
            severity: ToastSeverity.NotOk);
        return;
      }
    }

    switch (currentSelectionMode) {
      case BlueprintSelectionMode.addBlack:
        _handleAddBlack(model);
        break;
      case BlueprintSelectionMode.addAvailable:
        _handleAddAvailable(model);
        break;
      case BlueprintSelectionMode.emptyArea:
        _handleEmptyArea(model);
        break;
      case BlueprintSelectionMode.swapSeats:
        _handleSwapSeats(model);
        break;
      case BlueprintSelectionMode.createNewOrder:
        _handleCreateNewOrder(model);
        break;
      default:
        break;
    }
  }

  void _handleCreateNewOrder(BlueprintSeat model) {
    // Only spots (tables/seats) can be ordered, not black areas or empty space
    if (model.seat == null ||
        model.seat!.type == BlueprintModel.metaTableAreaType) {
      return;
    }

    setState(() {
      if (_selectedSeatsForOrder.contains(model)) {
        // Deselect
        _selectedSeatsForOrder.remove(model);

        // Restore the visual look to its actual state (available, ordered, etc.)
        _seatLayoutController.setSelection(model, false);
      } else {
        // Select
        _selectedSeatsForOrder.add(model);

        // Visually change to "Selected By Me" (Green Checkmark)
        // using the controller's visual-only update method
        _seatLayoutController.setSelection(model, true);
      }
    });
  }

  void _processNewOrder() async {
    if (_selectedSeatsForOrder.isEmpty) return;

    final spotIds =
        _selectedSeatsForOrder.map((s) => s.seat?.id).nonNulls.toList();

    if (spotIds.isEmpty) return;

    final dynamic result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BlueprintCreateOrderDialog(
        selectedSpotIds: spotIds,
      ),
    );

    if (result == true) {
      ToastHelper.Show(context, BlueprintStrings.orderCreatedSuccess,
          severity: ToastSeverity.Ok);
      _handleModeSelected(BlueprintSelectionMode.none);
      await loadData();
    }
  }

  void _handleAddBlack(BlueprintSeat model) {
    if (_isSeatOccupied(model.seat)) {
      ToastHelper.Show(context, BlueprintStrings.toastOccupiedCannotBeChanged,
          severity: ToastSeverity.NotOk);
      return;
    }

    if (model.seat != null &&
        model.seat!.type == BlueprintModel.metaTableAreaType) {
      return;
    }
    if (model.seat != null &&
        model.seat!.type != BlueprintModel.metaTableAreaType) {
      blueprint!.objects!.remove(model.seat!);
    }
    model.seat =
        model.seat ?? BlueprintObjectModel(x: model.column, y: model.row);
    model.seat!.type = BlueprintModel.metaTableAreaType;
    model.seat!.setSeatState(BlueprintSeatState.blocked);
    blueprint!.objects!.add(model.seat!);
    _seatLayoutController.addSeat(model.seat!, highlightGroup: false);
  }

  void _handleAddAvailable(BlueprintSeat model) {
    if (_isSeatOccupied(model.seat)) {
      ToastHelper.Show(context, BlueprintStrings.toastOccupiedCannotBeChanged,
          severity: ToastSeverity.NotOk);
      return;
    }

    if (currentGroup == null) {
      ToastHelper.Show(context, BlueprintStrings.toastSelectGroupFirst,
          severity: ToastSeverity.NotOk);
      return;
    }

    if (model.seat != null && model.seat!.type == BlueprintModel.metaSpotType) {
      return;
    }

    if (model.seat != null && model.seat!.type != BlueprintModel.metaSpotType) {
      blueprint!.objects!.remove(model.seat!);
    }

    // Inherit product from group or first available
    final groupProduct = currentGroup!.product ??
        (currentGroup!.objects.isNotEmpty
            ? currentGroup!.objects.first.product
            : null);

    model.seat =
        model.seat ?? BlueprintObjectModel(x: model.column, y: model.row);
    model.seat!.type = BlueprintModel.metaSpotType;
    model.seat!.setSeatState(BlueprintSeatState.available);

    model.seat!.product = groupProduct ?? blueprint!.spotProducts.firstOrNull;
    model.seat!.group = currentGroup;
    model.seat!.title = currentGroup?.getNextBoxName().toUpperCase();

    currentGroup?.objects.add(model.seat!);
    blueprint!.objects!.add(model.seat!);

    _seatLayoutController.addSeat(
      model.seat!,
      highlightGroup: currentGroup != null,
    );

    ToastHelper.Show(
        context, "${BlueprintStrings.toastSpotAdded} ${model.seat!.title}");
    setState(() {});
  }

  void _handleEmptyArea(BlueprintSeat model) {
    var objectToRemove = model.seat;
    if (objectToRemove != null) {
      if (_isSeatOccupied(objectToRemove)) {
        ToastHelper.Show(context, BlueprintStrings.toastOccupiedCannotBeChanged,
            severity: ToastSeverity.NotOk);
        return;
      }

      if (objectToRemove.stateEnum == BlueprintSeatState.blocked) {
        ToastHelper.Show(context, BlueprintStrings.toastAreaRemoved);
      } else {
        ToastHelper.Show(context, BlueprintStrings.toastSpotRemoved);
      }
      blueprint!.objects!.remove(objectToRemove);
      for (var group in blueprint!.groups!) {
        group.objects.remove(objectToRemove);
      }
      _seatLayoutController.removeSeat(model);
      setState(() {});
    }
  }

  void _handleSwapSeats(BlueprintSeat model) {
    final obj = model.seat;
    if (obj == null ||
        obj.stateEnum == BlueprintSeatState.blocked ||
        obj.stateEnum == BlueprintSeatState.empty) {
      ToastHelper.Show(context, BlueprintStrings.swapErrorEmpty,
          severity: ToastSeverity.NotOk);
      return;
    }

    if (model == _seatToSwap1) {
      _seatLayoutController.setSwapHighlight(model, false);
      _seatToSwap1 = null;
      return;
    }
    if (model == _seatToSwap2) {
      _seatLayoutController.setSwapHighlight(model, false);
      _seatToSwap2 = null;
      return;
    }

    if (_seatToSwap1 == null) {
      _seatToSwap1 = model;
      _seatLayoutController.setSwapHighlight(model, true);
      ToastHelper.Show(
          context, BlueprintStrings.swapHelpSelectSecond(obj.toString()));
      return;
    }

    if (_seatToSwap2 == null) {
      _seatToSwap2 = model;
      _seatLayoutController.setSwapHighlight(model, true);
      _showSwapConfirmationDialog();
    }
  }

  void _showSwapConfirmationDialog() async {
    if (_seatToSwap1 == null || _seatToSwap2 == null) return;

    final obj1 = _seatToSwap1!.seat!;
    final obj2 = _seatToSwap2!.seat!;

    final summary1 = obj1.getSwapSummary();
    final seatName1 = obj1.toString();
    final summary2 = obj2.getSwapSummary();
    final seatName2 = obj2.toString();

    final confirmed = await DialogHelper.showConfirmationDialogRichText(
      context,
      BlueprintStrings.swapConfirmTitle,
      Text.rich(
        TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
                text:
                    "${BlueprintStrings.swapConfirmMessage(summary1, seatName1, summary2, seatName2)}\n\n"),
            TextSpan(
              text: summary1,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: " ($seatName1)\n"),
            const TextSpan(
              text: " \u2195 ",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: "\n$summary2",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: " ($seatName2)"),
          ],
        ),
        textAlign: TextAlign.center,
      ),
      confirmButtonMessage: CommonStrings.confirm,
      cancelButtonMessage: CommonStrings.storno,
    );

    if (confirmed == true) {
      _performSwap();
    } else {
      _clearSwapSelection();
    }
  }

  Future<void> _performSwap() async {
    if (_seatToSwap1 == null || _seatToSwap2 == null) return;

    final obj1 = _seatToSwap1!.seat!;
    final obj2 = _seatToSwap2!.seat!;

    final tempOrderProductTicket = obj1.orderProductTicket;
    final tempStateEnum = obj1.stateEnum ?? BlueprintSeatState.available;

    obj1.orderProductTicket = obj2.orderProductTicket;
    obj1.setSeatState(obj2.stateEnum ?? BlueprintSeatState.available);

    obj2.orderProductTicket = tempOrderProductTicket;
    obj2.setSeatState(tempStateEnum);

    await DbTickets.swapSpotTickets(obj1.id!, obj2.id!);
    ToastHelper.Show(context, BlueprintStrings.swapSuccess,
        severity: ToastSeverity.Ok);

    _seatLayoutController.refreshSeat(obj1);
    _seatLayoutController.refreshSeat(obj2);

    await loadData();
  }

  void _clearSwapSelection() {
    if (_seatToSwap1 != null) {
      _seatLayoutController.setSwapHighlight(_seatToSwap1!, false);
    }
    if (_seatToSwap2 != null) {
      _seatLayoutController.setSwapHighlight(_seatToSwap2!, false);
    }
    _seatToSwap1 = null;
    _seatToSwap2 = null;
  }

  void _editGroupProduct(BlueprintGroupModel group) async {
    if (blueprint == null) return;

    // Open the Unified Manager Dialog
    await showDialog(
      context: context,
      builder: (context) => GroupProductManagerDialog(
        blueprint: blueprint!,
        group: group,
      ),
    );

    // Refresh UI after dialog closes to show changes in price/titles
    setState(() {});
  }

  Future<void> saveChanges() async {
    if (blueprint == null) return;
    try {
      // Ensure blueprint model objects are in sync
      blueprint!.objects =
          _seatLayoutController.slots.map((s) => s.seat).nonNulls.toList();

      for (var obj in blueprint!.objects!) {
        if (obj.product != null) {
          obj.spotProduct = obj.product!.id;
        }
      }

      if (_isPrototype) {
        widget.onPrototypeSave?.call(blueprint!);
        _prototypeBaseline = jsonEncode(blueprint);
      } else {
        await DbForms.updateBlueprint(blueprint!);
      }
      ToastHelper.Show(context, CommonStrings.saved,
          severity: ToastSeverity.Ok);
      await loadData();
    } catch (e) {
      ToastHelper.Show(context, e.toString().replaceFirst("Exception: ", ""),
          severity: ToastSeverity.NotOk);
    }
  }

  Future<void> loadData() async {
    _resetAllSelections(); // Ensure clean state
    blueprint = _isPrototype
        ? BlueprintModel.fromJson(jsonDecode(
                _prototypeBaseline ??= jsonEncode(widget.prototypeBlueprint))
            as Map<String, dynamic>)
        : await DbForms.getBlueprintForEdit(occasionLink!);
    if (blueprint != null) {
      _seatLayoutController.loadPlan(
        rows: blueprint!.configuration?.height ?? 1,
        columns: blueprint!.configuration?.width ?? 1,
        seats: (blueprint!.objects ?? const [])
            .where((object) => object.x != null && object.y != null),
        seatSize: SeatReservationWidget.boxSize.toDouble(),
        backdrop: switch (blueprint!.backgroundSvg) {
          final String source when source.isNotEmpty =>
            VenueBackdrop.parse(source),
          _ => null,
        },
      );
    }
    _snapshot.accept(_draft);
    if (mounted) {
      setState(() {});
    }
  }
}

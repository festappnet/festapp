import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/eshop/views/ticket_batches_page.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import '../../_shared/editor_file_drop_region.dart';
import '../../_shared/editor_file_drop_strings.dart';
import '../../images/db_images.dart';
import '../../images/image_file_format.dart';
import '../../images/image_upload_limits.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:festapp_core/eshop.dart';
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
import '../../occasion/setup/occasion_setup_strings.dart';
import '../../eshop/db_tickets.dart';
import '../blueprint_seat.dart';
import '../seat_reservation/widgets/seat_reservation_widget.dart';
import 'blueprint_controls_bar.dart';
import 'blueprint_create_order_dialog.dart';
import 'blueprint_groups_panel.dart';
import 'blueprint_legend.dart';
import 'blueprint_mobile_scroll_view.dart';
import 'blueprint_product_dialogs.dart';
import 'blueprint_viewport.dart';

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
      {super.key,
      this.prototypeBlueprint,
      this.onPrototypeSave,
      this.onPrototypeComplete,
      this.loadBlueprint,
      this.uploadBackground,
      this.saveBlueprint});

  /// Runs the existing editor against a setup draft and its persistence callback.
  const BlueprintTab.prototype({
    super.key,
    required this.prototypeBlueprint,
    required this.onPrototypeSave,
    this.onPrototypeComplete,
  })  : loadBlueprint = null,
        uploadBackground = null,
        saveBlueprint = null;

  final Future<BlueprintModel?> Function()? loadBlueprint;
  final Future<void> Function(BlueprintModel)? saveBlueprint;
  final Future<String> Function(Uint8List, int?)? uploadBackground;
  final BlueprintModel? prototypeBlueprint;
  final FutureOr<void> Function(BlueprintModel)? onPrototypeSave;

  /// Called only after the prototype is durably saved and its baseline accepted.
  final VoidCallback? onPrototypeComplete;

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
  bool _backgroundBusy = false;
  bool _loading = false;
  bool _saving = false;
  bool _allowPrototypePop = false;
  bool get _canImport =>
      mounted &&
      _canEdit &&
      blueprint != null &&
      !_backgroundBusy &&
      !_loading &&
      !_saving &&
      editorFileDropIsActive(context);
  Map<String, dynamic> _prototypeData(BlueprintModel plan) => {
        ...plan.toJson(),
        BlueprintModel.metaSpots: (plan.objects ?? [])
            .where((o) => o.type == BlueprintModel.metaSpotType)
            .map((o) => o.toJson())
            .toList(),
        'products': (plan.products ?? [])
            .map((p) => {
                  ...p.toJson(),
                  ProductModel.metaTypeField: p.productTypeString,
                  ProductModel.metaProductTypeTitleStringField:
                      p.productTypeTitleString,
                })
            .toList(),
      };

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
    if (_isPrototype || widget.loadBlueprint != null) {
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
    if (!_initialLoadStarted) {
      _initialLoadStarted = true;
      loadData();
    }
  }

  @override
  void dispose() {
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
      onCreateBatch: FeatureService.isTicketPregenerationEnabled()
          ? () async {
              final ids = _selectedSeatsForOrder
                  .map((s) => s.seat?.id)
                  .nonNulls
                  .toList();
              final created = await ExceptionHandler.guard<bool>(context,
                  futureFunction: () => createTicketBatchFromSpots(context,
                      blueprintId: blueprint!.id!, spotIds: ids));
              if (created == true && mounted) {
                _handleModeSelected(BlueprintSelectionMode.none);
                await loadData();
              }
            }
          : null,
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
                canEdit: _canEdit && !_backgroundBusy && !_loading && !_saving,
                allowRemoteUpload: !_isPrototype,
                onImportSvg: () => _pickBackground(svg: true),
                onImportImage: () => _pickBackground(svg: false),
                onRemoveBackground: _removeBackground,
              ),
        const SizedBox(height: 16),
        Flexible(
          child: blueprint == null
              ? const Center(child: CircularProgressIndicator())
              : BlueprintViewport(
                  controller: _seatLayoutController,
                  child: TooltipTheme(
                      data: TooltipThemeData(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .inverseSurface
                              .withValues(alpha: .95),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        textStyle:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface,
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
                      ))),
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
    return PopScope(
        canPop: !_isPrototype ||
            _allowPrototypePop ||
            (!_saving && !_snapshot.differs(_draft)),
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop || !_isPrototype || _saving) return;
          final discard = await confirmDiscardChanges(context);
          if (discard == true && mounted) {
            setState(() => _allowPrototypePop = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.of(context).pop();
            });
          }
        },
        child: Scaffold(
          body: EditorFileDropRegion(
            enabled: _canImport,
            active: TickerMode.valuesOf(context).enabled,
            hint: EditorFileDropStrings.hint,
            allowedExtensions: [
              if (!_isPrototype) ...editorRasterExtensions,
              'svg'
            ],
            onFileDropped: importBackground,
            child: AbsorbPointer(
              absorbing: _backgroundBusy || _loading || _saving,
              child: SafeArea(
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
            ),
          ),
          bottomNavigationBar: AnimatedBuilder(
            animation: _seatLayoutController,
            builder: (context, _) => _isPrototype
                ? SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.centerRight,
                        heightFactor: 1,
                        child: FilledButton(
                          onPressed: _canEdit &&
                                  blueprint != null &&
                                  !_backgroundBusy &&
                                  !_loading &&
                                  !_saving
                              ? saveChanges
                              : null,
                          child:
                              Text(OccasionSetupStrings.story('saveAndReturn')),
                        ),
                      ),
                    ),
                  )
                : EditorActionBar(
                    hasChanges: blueprint != null && _snapshot.differs(_draft),
                    enabled:
                        _canEdit && !_backgroundBusy && !_loading && !_saving,
                    onSave: saveChanges,
                    onDiscard: loadData,
                  ),
          ),
        ));
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

  Future<void> _pickBackground({required bool svg}) async {
    if (!_canImport || (!svg && _isPrototype)) return;
    final draft = blueprint;
    setState(() => _backgroundBusy = true);
    try {
      final file = await DialogHelper.dropFilesHere(
          context,
          svg
              ? BlueprintStrings.dialogImportSvgTitle
              : BlueprintStrings.dialogImportImageTitle,
          CommonStrings.ok,
          CommonStrings.storno,
          allowedExtensions: svg ? const ['svg'] : editorRasterExtensions,
          singleFileOnly: true,
          onInvalidDrop: () => ToastHelper.Show(
              context, EditorFileDropStrings.singleFile,
              severity: ToastSeverity.NotOk));
      if (!mounted ||
          !identical(draft, blueprint) ||
          !_canEdit ||
          file == null) {
        return;
      }
      await _importBackground(file, draft!);
    } finally {
      if (mounted) setState(() => _backgroundBusy = false);
    }
  }

  Future<void> importBackground(XFile file) async {
    if (!_canImport) return;
    final draft = blueprint!;
    setState(() => _backgroundBusy = true);
    try {
      await _importBackground(file, draft);
    } finally {
      if (mounted) setState(() => _backgroundBusy = false);
    }
  }

  Future<void> _importBackground(XFile file, BlueprintModel draft) async {
    await ExceptionHandler.guard(context, futureFunction: () async {
      final svg = file.name.toLowerCase().endsWith('.svg');
      if (!svg && _isPrototype) return;
      String source;
      if (svg) {
        source = await file.readAsString();
        if (!source.trim().startsWith('<svg')) {
          throw FormatException(BlueprintStrings.toastInvalidSvg);
        }
      } else {
        if (await file.length() > ImageUploadLimits.maxInputBytes) {
          throw FormatException(EditorFileDropStrings.tooLarge);
        }
        final bytes = await file.readAsBytes();
        ImageFileFormat.detect(bytes);
        source = await (widget.uploadBackground?.call(bytes, draft.occasion) ??
            DbImages.uploadImage(bytes, draft.occasion, null,
                profile: ImageUploadProfile.blueprintBackground));
      }
      final backdrop = VenueBackdrop.parse(source);
      if (!mounted || !identical(draft, blueprint) || !_canEdit) return;
      setState(() {
        _seatLayoutController.setBackdrop(backdrop);
        draft.backgroundSvg = source;
      });
      ToastHelper.Show(
          context,
          svg
              ? BlueprintStrings.toastSvgUploadSuccess
              : BlueprintStrings.toastImageUploadSuccess);
    });
  }

  Future<void> _removeBackground() async {
    if (!_canImport) return;
    final draft = blueprint!;
    setState(() => _backgroundBusy = true);
    try {
      final confirmed = await DialogHelper.showConfirmationDialog(
          context,
          BlueprintStrings.dialogConfirmRemoveBackgroundTitle,
          BlueprintStrings.dialogConfirmRemoveBackgroundContent);
      if (confirmed != true ||
          !mounted ||
          !identical(draft, blueprint) ||
          !_canEdit) {
        return;
      }
      setState(() {
        _seatLayoutController.setBackdrop(null);
        draft.backgroundSvg = null;
      });
    } finally {
      if (mounted) setState(() => _backgroundBusy = false);
    }
  }

  Future<void> saveChanges() async {
    if (!_canImport) return;
    setState(() => _saving = true);
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
        await widget.onPrototypeSave?.call(blueprint!);
        _prototypeBaseline = jsonEncode(_prototypeData(blueprint!));
      } else {
        await (widget.saveBlueprint?.call(blueprint!) ??
            DbForms.updateBlueprint(blueprint!));
      }
      if (!mounted) return;
      ToastHelper.Show(context, CommonStrings.saved,
          severity: ToastSeverity.Ok);
      await _reloadData();
      if (_isPrototype && mounted && widget.onPrototypeComplete != null) {
        setState(() => _allowPrototypePop = true);
        // Let PopScope observe the accepted baseline before the parent closes.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onPrototypeComplete?.call();
        });
      }
    } catch (e) {
      ToastHelper.Show(context, e.toString().replaceFirst("Exception: ", ""),
          severity: ToastSeverity.NotOk);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> loadData() async {
    if (_backgroundBusy || _saving || _loading) return;
    await _reloadData();
  }

  Future<void> _reloadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      _resetAllSelections(); // Ensure clean state
      blueprint = _isPrototype
          ? BlueprintModel.fromJson(jsonDecode(_prototypeBaseline ??=
                  jsonEncode(_prototypeData(widget.prototypeBlueprint!)))
              as Map<String, dynamic>)
          : await (widget.loadBlueprint?.call() ??
              DbForms.getBlueprintForEdit(occasionLink!));
      if (!mounted) return;
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

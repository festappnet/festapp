import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/inventory/models/inventory_context_model.dart';
import 'package:fstapp/components/inventory/models/inventory_pool_bundle.dart';
import 'package:fstapp/components/inventory/models/inventory_pool_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/inventory/db_inventory_pools.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

import '../../map/place_model.dart';
import 'inventory_contexts_editor.dart';
import 'inventory_strings.dart';
import 'place_search_dialog.dart';
import 'product_search_dialog.dart';
import 'quick_search_dialog.dart';

class InventoryPoolSettingsView extends StatefulWidget {
  final int poolId;
  final VoidCallback? onPoolUpdated;
  final VoidCallback? onPoolDeleted;

  const InventoryPoolSettingsView({
    super.key,
    required this.poolId,
    this.onPoolUpdated,
    this.onPoolDeleted,
  });

  @override
  _InventoryPoolSettingsViewState createState() =>
      _InventoryPoolSettingsViewState();
}

class _LoadResult {
  final InventoryPoolBundle bundle;
  final OccasionModel? occasion;
  _LoadResult(this.bundle, this.occasion);
}

class _InventoryPoolSettingsViewState extends State<InventoryPoolSettingsView> {
  final _htmlSave = HtmlSaveCoordinator();
  @override
  Widget build(BuildContext context) => HtmlEditingScope(
    coordinator: _htmlSave, child: _buildHtmlParent(context));

  static const int _datePickerPaddingDays = 7;
  final _formKey = GlobalKey<FormState>();
  InventoryPoolBundle? _bundle;
  List<InventoryContextModel> _originalContexts = [];
  String? _originalDescription;
  bool _originalIsAutoResourceAssignment = true;
  bool _originalIsEditableByUser = false;
  PlaceModel? _originalPlace;
  OccasionModel? _occasion;
  bool _isLoading = true;
  bool _isSaving = false;

  late TextEditingController _poolTitleController;
  late TextEditingController _sellableCapacityController;
  InventoryPoolType _selectedType = InventoryPoolType.other;

  @override
  void initState() {
    super.initState();
    _poolTitleController = TextEditingController();
    _sellableCapacityController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _htmlSave.dispose();
    _poolTitleController.dispose();
    _sellableCapacityController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final result = await ExceptionHandler.guard<_LoadResult>(
      context,
      futureFunction: () async {
        final bundle =
            await DbInventoryPools.getInventoryPoolBundle(widget.poolId);
        OccasionModel? occasion;
        if (bundle.pool.occasionId != null) {
          occasion = await DbUsers.getOccasion(bundle.pool.occasionId!);
        }
        return _LoadResult(bundle, occasion);
      },
      defaultErrorMessage: InventoryStrings.settingsErrorLoad,
    );

    if (mounted) {
      if (result != null) {
        // Link products to contexts BEFORE creating the original backup
        if (result.bundle.contexts != null && result.bundle.products != null) {
          for (var context in result.bundle.contexts!) {
            if (context.productId != null) {
              context.product = result.bundle.products!
                  .firstWhereOrNull((p) => p.id == context.productId);
            }
          }
        }

        setState(() {
          _bundle = result.bundle;
          _occasion = result.occasion;
          _originalContexts =
              result.bundle.contexts?.map((c) => c.copyWith()).toList() ?? [];
          _poolTitleController.text = result.bundle.pool.title ?? '';
          _sellableCapacityController.text =
              result.bundle.pool.sellableCapacity?.toString() ?? '';
          _selectedType = result.bundle.pool.type;

          _originalDescription = result.bundle.pool.description;
          _originalIsAutoResourceAssignment =
              result.bundle.pool.isAutoResourceAssignment;
          _originalIsEditableByUser = result.bundle.pool.isEditableByUser;

          _originalPlace = result.bundle.places
              ?.firstWhereOrNull((p) => p.id == result.bundle.pool.placeId);
          _bundle!.pool.place = _originalPlace;
        });
      }
      setState(() => _isLoading = false);
    }
  }

  void _updateContextsOrder() {
    if (_bundle?.contexts == null) return;
    for (int i = 0; i < _bundle!.contexts!.length; i++) {
      _bundle!.contexts![i].order = i;
    }
  }

  Future<void> _saveChanges(BuildContext currentContext) async {
    await ExceptionHandler.guardVoid(currentContext, futureFunction: () =>
      _htmlSave.save(() => _performHtmlSave(currentContext), context: currentContext));
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _performHtmlSave(BuildContext currentContext) async {
    if (!_formKey.currentState!.validate() || _bundle == null) return;

    final contextsToDelete = _originalContexts
        .where((orig) =>
            orig.id != null &&
            !_bundle!.contexts!.any((curr) => curr.id == orig.id))
        .toList();

    if (contextsToDelete.isNotEmpty) {
      final confirmed = await DialogHelper.showConfirmationDialog(
        currentContext,
        InventoryStrings.settingsConfirmDeletionTitle,
        InventoryStrings.settingsConfirmContextDeletionContent(
            contextsToDelete.length),
      );
      if (confirmed != true) return;
    }

    setState(() => _isSaving = true);

    _bundle!.pool.title = _poolTitleController.text.trim();
    _bundle!.pool.sellableCapacity =
        int.tryParse(_sellableCapacityController.text);
    _bundle!.pool.type = _selectedType;
    _updateContextsOrder();

    _bundle!.pool.description = await _htmlSave.prepare(_bundle!.pool.description ?? '',
      HtmlMediaOwner.occasion(_bundle!.pool.occasionId), originalHtml: _originalDescription);
    final updatedBundle = await ExceptionHandler.guard(
      currentContext,
      futureFunction: () =>
          DbInventoryPools.updateInventoryPoolBundle(_bundle!),
      defaultErrorMessage: InventoryStrings.settingsErrorSave,
    );

    if (mounted) {
      if (updatedBundle != null) {
      _htmlSave.markSaved();
        // Link products to contexts BEFORE creating the original backup
        if (updatedBundle.contexts != null && updatedBundle.products != null) {
          for (var context in updatedBundle.contexts!) {
            if (context.productId != null) {
              context.product = updatedBundle.products!
                  .firstWhereOrNull((p) => p.id == context.productId);
            }
          }
        }
        setState(() {
          _bundle = updatedBundle;
          _originalContexts =
              updatedBundle.contexts?.map((c) => c.copyWith()).toList() ?? [];
          _poolTitleController.text = updatedBundle.pool.title ?? '';
          _sellableCapacityController.text =
              updatedBundle.pool.sellableCapacity?.toString() ?? '';
          _selectedType = updatedBundle.pool.type;
          _originalDescription = updatedBundle.pool.description;
          _originalIsAutoResourceAssignment =
              updatedBundle.pool.isAutoResourceAssignment;
          _originalIsEditableByUser = updatedBundle.pool.isEditableByUser;
          _originalPlace = updatedBundle.places
              ?.firstWhereOrNull((p) => p.id == updatedBundle.pool.placeId);
          _bundle!.pool.place = _originalPlace;
        });
        await ToastHelper.Show(
            currentContext, InventoryStrings.settingsSuccessSave,
            severity: ToastSeverity.Ok);
        widget.onPoolUpdated?.call();
      }
      setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete(BuildContext currentContext) async {
    final confirmed = await DialogHelper.showConfirmationDialog(
      currentContext,
      InventoryStrings.settingsDeletePoolButton,
      InventoryStrings.settingsConfirmPoolDeletionContent,
    );
    if (confirmed != true || _bundle == null) return;

    final success = await ExceptionHandler.guardVoid(
      currentContext,
      futureFunction: () => DbInventoryPools.deleteInventoryPool(
        _bundle!.pool.id!,
        expectedVersion: _bundle!.aggregateVersion,
      ),
      defaultErrorMessage: InventoryStrings.settingsErrorDelete,
    );

    if (success && mounted) {
      await ToastHelper.Show(
          currentContext, InventoryStrings.settingsSuccessDelete,
          severity: ToastSeverity.Ok);
      widget.onPoolDeleted?.call();
    }
  }

  Future<void> _cancelEdit() async {
    if (!await confirmHtmlDiscard(context, _htmlSave) || !mounted) return;
    _htmlSave.markSaved();
    setState(() {
      _bundle?.contexts = _originalContexts.map((c) => c.copyWith()).toList();
      _poolTitleController.text = _bundle?.pool.title ?? '';
      _sellableCapacityController.text =
          _bundle?.pool.sellableCapacity?.toString() ?? '';
      _selectedType = _bundle?.pool.type ?? InventoryPoolType.other;
      if (_bundle != null) {
        _bundle!.pool.description = _originalDescription;
        _bundle!.pool.isAutoResourceAssignment =
            _originalIsAutoResourceAssignment;
        _bundle!.pool.isEditableByUser = _originalIsEditableByUser;
        _bundle!.pool.place = _originalPlace;
        _bundle!.pool.placeId = _originalPlace?.id;
      }
    });
  }

  /// Builds the pool-type selector limited to the types the occasion's
  /// ServicesFeature permits. When exactly one type is permitted and the pool
  /// already matches it, the selector is hidden ("exclusive" mode). A legacy
  /// pool whose type is no longer permitted keeps its type as an extra option
  /// so it can be migrated rather than silently misrepresented.
  Widget _buildTypeSelector(BuildContext context) {
    final allowed = allowedInventoryPoolTypes();
    if (allowed.length == 1 && allowed.first == _selectedType) {
      return const SizedBox.shrink();
    }
    final types = allowed.contains(_selectedType)
        ? allowed
        : <InventoryPoolType>[_selectedType, ...allowed];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          InventoryStrings.settingsTypeLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Center(
          child: ToggleButtons(
            isSelected: types.map((t) => t == _selectedType).toList(),
            onPressed: (int index) {
              setState(() => _selectedType = types[index]);
            },
            borderRadius: BorderRadius.circular(8.0),
            children: types.map((type) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(type.icon, size: 18),
                    const SizedBox(width: 8),
                    Text(type.displayName),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _removeContext(InventoryContextModel context) {
    setState(() {
      if (context.id != null) {
        _bundle!.contexts!.removeWhere((c) => c.id == context.id);
      } else {
        _bundle!.contexts!.removeWhere((c) => c == context);
      }
      _updateContextsOrder();
    });
  }

  void _addContextBack(InventoryContextModel context) {
    setState(() {
      context.order = context.order! - 1;
      _bundle!.contexts!.add(context);
      _bundle!.contexts!
          .sort((a, b) => (a.order ?? 999).compareTo(b.order ?? 999));
      _updateContextsOrder();
    });
  }

  void _reorderContext(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _bundle!.contexts!.removeAt(oldIndex);
      _bundle!.contexts!.insert(newIndex, item);
      _updateContextsOrder();
    });
  }

  Future<void> _showEditContextDialog(
      {InventoryContextModel? contextModel}) async {
    final bool isNew = contextModel == null;
    final model = contextModel?.copyWith() ??
        InventoryContextModel(inventoryPoolId: widget.poolId);

    final result = await showDialog<InventoryContextModel>(
      context: context,
      builder: (dialogContext) {
        final titleController = TextEditingController(text: model.title);
        final dateController = TextEditingController();
        final dateNotifier = ValueNotifier<DateTime?>(model.blockDate);

        if (model.blockDate != null) {
          dateController.text =
              DateFormat.yMMMd(dialogContext.locale.toString())
                  .format(model.blockDate!);
        }

        return AlertDialog(
          title: Text(isNew
              ? InventoryStrings.contextDialogAddTitle
              : InventoryStrings.contextDialogEditTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: titleController,
                decoration: InputDecoration(
                    labelText: InventoryStrings.contextDialogTitleLabel,
                    border: const OutlineInputBorder(),
                    hintText: InventoryStrings.contextDialogTitleHint),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: dateController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: InventoryStrings.contextDialogDateLabel,
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                onTap: () async {
                  const datePadding = Duration(days: _datePickerPaddingDays);
                  final DateTime firstDate =
                      (_occasion?.startTime ?? DateTime(2020))
                          .subtract(datePadding);
                  final DateTime lastDate =
                      (_occasion?.endTime ?? DateTime(2030)).add(datePadding);

                  final newDate = await showDatePicker(
                    context: dialogContext,
                    locale: dialogContext.locale,
                    initialDate: dateNotifier.value ??
                        _occasion?.startTime ??
                        DateTime.now(),
                    firstDate: firstDate,
                    lastDate: lastDate,
                  );
                  if (newDate != null) {
                    dateNotifier.value = newDate;
                    dateController.text =
                        DateFormat.yMMMd(dialogContext.locale.toString())
                            .format(newDate);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(CommonStrings.storno),
            ),
            ElevatedButton(
              onPressed: () {
                model.title = titleController.text.trim().isEmpty
                    ? null
                    : titleController.text.trim();
                model.blockDate = dateNotifier.value;
                if (model.title == null && model.blockDate == null) {
                  ToastHelper.Show(
                      context, InventoryStrings.contextDialogValidationError,
                      severity: ToastSeverity.NotOk);
                  return;
                }
                Navigator.of(dialogContext).pop(model);
              },
              child: Text(CommonStrings.save),
            ),
          ],
        );
      },
    );

    if (result != null) {
      setState(() {
        if (isNew) {
          _bundle!.contexts!.add(result);
        } else {
          final index = _bundle!.contexts!.indexWhere((c) => c.id == result.id);
          if (index != -1) {
            _bundle!.contexts![index] = result;
          }
        }
        _updateContextsOrder();
      });
    }
  }

  Future<void> _showSelectPlaceDialog() async {
    if (_bundle?.places == null) return;

    final result = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => PlaceSearchDialog(
        allPlaces: _bundle!.places!,
        currentPlace: _bundle!.pool.place,
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      if (result is PlaceModel) {
        _bundle!.pool.place = result;
        _bundle!.pool.placeId = result.id;
      } else if (result is UnassignAction) {
        _bundle!.pool.place = null;
        _bundle!.pool.placeId = null;
      }
    });
  }

  // MODIFICATION: Signature updated to accept the filtered list.
  Future<void> _showSelectProductDialog(InventoryContextModel contextModel,
      List<ProductModel> assignableProducts) async {
    final result = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => ProductSearchDialog(
        allProducts: assignableProducts,
        currentProduct: contextModel.product,
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      final contextIndex = _bundle!.contexts!
          .indexWhere((c) => c.id == contextModel.id || c == contextModel);
      if (contextIndex == -1) return;

      if (result is ProductModel) {
        _bundle!.contexts![contextIndex].product = result;
        _bundle!.contexts![contextIndex].productId = result.id;
      } else if (result is UnassignAction) {
        _bundle!.contexts![contextIndex].product = null;
        _bundle!.contexts![contextIndex].productId = null;
      }
    });
  }


  Widget _buildHtmlParent(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_bundle == null) {
      return Scaffold(
          body:
              Center(child: Text(InventoryStrings.settingsErrorCouldNotLoad)));
    }

    final activeContexts = _bundle!.contexts!;
    activeContexts.sort((a, b) => (a.order ?? 999).compareTo((b.order ?? 999)));

    final deletedContexts = _originalContexts
        .where((orig) =>
            orig.id != null &&
            !activeContexts.any((curr) => curr.id == orig.id))
        .toList();

    return Scaffold(
      body: Builder(
        builder: (innerContext) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
              child: Form(
                key: _formKey,
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              InventoryStrings.settingsConfigureTitle(
                                  _bundle!.pool.title ?? 'Pool'),
                              style: Theme.of(innerContext)
                                  .textTheme
                                  .headlineSmall,
                            ),
                            const SizedBox(height: 24),
                            Text(
                                InventoryStrings
                                    .settingsPoolSettingsSectionTitle,
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _poolTitleController,
                              decoration: InputDecoration(
                                labelText: InventoryStrings.poolTitleLabel,
                                border: const OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? InventoryStrings.validationTitleEmpty
                                      : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _sellableCapacityController,
                              decoration: InputDecoration(
                                labelText: InventoryStrings
                                    .settingsSellableCapacityLabel,
                                hintText: InventoryStrings
                                    .settingsSellableCapacityHint,
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(InventoryStrings.settingsDescriptionLabel,
                                style: Theme.of(context).textTheme.labelLarge),
                            const SizedBox(height: 8),
                            InputDecorator(
                              decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.all(12)),
                              child: EditableHtmlField(html: _bundle!.pool.description, coordinator: _htmlSave,
                                owner: HtmlMediaOwner.occasion(_bundle!.pool.occasionId),
                                onChanged: (html) => setState(() => _bundle!.pool.description = html))),
                            const SizedBox(height: 24),
                            _buildTypeSelector(context),
                            const SizedBox(height: 24),
                            Text(InventoryStrings.settingsPlaceLabel,
                                style: Theme.of(context).textTheme.labelLarge),
                            const SizedBox(height: 8),
                            InputDecorator(
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(_bundle!.pool.place?.title ??
                                    InventoryStrings.settingsNoPlaceAssigned),
                                trailing: ElevatedButton(
                                  onPressed: _showSelectPlaceDialog,
                                  child: Text(CommonStrings.edit),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                  InventoryStrings.settingsAutoAssignmentLabel),
                              subtitle: Text(InventoryStrings
                                  .settingsAutoAssignmentSubtitle),
                              value: _bundle!.pool.isAutoResourceAssignment,
                              onChanged: (bool value) {
                                setState(() {
                                  _bundle!.pool.isAutoResourceAssignment =
                                      value;
                                });
                              },
                            ),
                            const Divider(height: 40),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    InventoryStrings
                                        .settingsContextsSectionTitle,
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  tooltip: InventoryStrings
                                      .settingsAddContextTooltip,
                                  onPressed: () => _showEditContextDialog(),
                                )
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (activeContexts.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16.0),
                                child: Center(
                                    child: Text(
                                        InventoryStrings.settingsNoContexts)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: InventoryContextsEditor(
                        activeContexts: activeContexts,
                        deletedContexts: deletedContexts,
                        originalContexts: _originalContexts,
                        pool: _bundle?.pool,
                        allProducts: _bundle?.products ?? [],
                        onReorder: _reorderContext,
                        onEdit: (context) =>
                            _showEditContextDialog(contextModel: context),
                        onEditProduct: _showSelectProductDialog,
                        onRemove: _removeContext,
                        onRestore: _addContextBack,
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          children: [
                            const SizedBox(height: 48),
                            Center(
                              child: TextButton(
                                onPressed: () => _confirmDelete(innerContext),
                                child: Text(
                                  InventoryStrings.settingsDeletePoolButton,
                                  style: TextStyle(
                                      color:
                                          ThemeConfig.redColor(innerContext)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 48),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: Builder(builder: (innerContext) {
        return Container(
          color: ThemeConfig.appBarColor(),
          padding: const EdgeInsets.all(10),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : _cancelEdit,
                  child: Text(CommonStrings.storno),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  icon: _isSaving
                      ? const SizedBox.shrink()
                      : const Icon(Icons.save, size: 18),
                  label: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(InventoryStrings.settingsSaveChanges),
                  onPressed:
                      _isSaving ? null : () => _saveChanges(innerContext),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

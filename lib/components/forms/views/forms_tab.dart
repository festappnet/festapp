import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import '../form_strings.dart';
import 'form_creation_helper.dart';
import 'package:fstapp/app_router.gr.dart';

@RoutePage(name: 'FormsListRoute')
class FormsTab extends StatelessWidget {
  const FormsTab({super.key});

  @override
  Widget build(BuildContext context) => const FormsListView();
}

class FormsListView extends StatefulWidget {
  final Future<List<FormModel>> Function(String)? loadForms;
  const FormsListView({super.key, this.loadForms});

  @override
  State<FormsListView> createState() => _FormsTabState();
}

class _FormsTabState extends State<FormsListView> {
  List<FormModel> _forms = [];
  String? occasionLink;
  bool _isLoading = true;
  String? _loadError;
  int _loadGeneration = 0;

  String? _previousOccasionLink;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newOccasionLink = context.routeData.inheritedPathParams
        .get(AppRouter.linkFormatted, null);

    if (newOccasionLink != null && newOccasionLink != _previousOccasionLink) {
      occasionLink = newOccasionLink;
      _previousOccasionLink = newOccasionLink;
      loadData();
    }
  }

  Future<void> loadData() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final identity = occasionLink;
      if (identity == null) return;
      final forms = await (widget.loadForms ??
          DbForms.getAllFormsByOccasionLink)(identity);
      if (!mounted || generation != _loadGeneration) return;
      _forms = forms;
      if (forms.length == 1 &&
          forms.single.link?.isNotEmpty == true &&
          context.routeData.queryParams.get('list')?.toString().toLowerCase() !=
              'true') {
        // Replace the selector so Back does not bounce through it again.
        context.router.markUrlStateForReplace();
        await context.router.replaceAll([
          FormDetailRoute(
            formLink: forms.single.link!,
          ).copyWith(
              queryParams: context.router.root.urlState.uri.queryParametersAll)
        ]);
        return;
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        _loadError = ExceptionHandler.toFriendlyMessage(error);
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleCardTap(FormModel form) async {
    await context.router.push(FormDetailRoute(formLink: form.link!));
  }

  Future<void> _handleCreateNew() async {
    if (occasionLink == null) return;
    await FormCreationHelper.showCreateOrCopyFormDialog(context,
        occasionLink: occasionLink!, onFormCreated: loadData);
  }

  Future<void> _handleCreateCopy(FormModel form) async {
    if (occasionLink == null) return;
    await FormCreationHelper.copyFormToOccasion(context, form,
        occasionLink: occasionLink!, onFormCreated: loadData);
  }

  Widget _buildFormsGrid() {
    return RefreshIndicator(
      onRefresh: loadData,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 380,
                mainAxisExtent: 125,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final form = _forms[index];
                  return FormCard(
                    form: form,
                    onTap: () => _handleCardTap(form),
                    onCreateCopy: () => _handleCreateCopy(form),
                  );
                },
                childCount: _forms.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Text(
          FormStrings.noFormsForEventPrompt(FormStrings.createNewForm),
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: Theme.of(context).hintColor),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(FormStrings.formsTitle),
        elevation: 0,
        toolbarHeight: 44.0,
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(FormStrings.createNewForm),
              onPressed: _handleCreateNew,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(StylesConfig.commonRoundness),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!),
                      TextButton(
                        onPressed: loadData,
                        child: Text(CommonStrings.retry),
                      ),
                    ],
                  ),
                )
              : _forms.isEmpty
                  ? _buildEmptyState()
                  : _buildFormsGrid(),
    );
  }
}

// NOTE: _CreateOrCopyFormDialog has been extracted to create_or_copy_dialog.dart.

class FormCard extends StatelessWidget {
  final FormModel form;
  final VoidCallback onTap;
  final VoidCallback onCreateCopy;

  const FormCard({
    super.key,
    required this.form,
    required this.onTap,
    required this.onCreateCopy,
  });

  Widget _buildStat(BuildContext context,
      {required IconData icon,
      required String value,
      required String tooltip,
      Color? color}) {
    final theme = Theme.of(context);
    final defaultColor = theme.colorScheme.onSurface.withOpacity(0.7);
    final iconColor = color ?? defaultColor;
    final statsTextStyle =
        theme.textTheme.bodySmall?.copyWith(color: defaultColor);

    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15.0, color: iconColor),
          const SizedBox(width: 4.0),
          Text(value, style: statsTextStyle),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final onSurfaceColor = theme.colorScheme.onSurface;

    final cardColor = isDarkMode ? Colors.grey[850] : theme.cardColor;
    final borderColor = isDarkMode ? Colors.grey[700]! : theme.dividerColor;

    return Card(
      elevation: 0,
      color: cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StylesConfig.commonRoundness),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PopupMenuButton<String>(
                elevation: 0,
                icon: Icon(Icons.more_vert,
                    color: onSurfaceColor.withOpacity(0.7)),
                onSelected: (value) {
                  if (value == "create_copy") {
                    onCreateCopy();
                  }
                },
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem(
                    value: "create_copy",
                    child: Text(FormStrings.createCopy),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          form.toString(),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (form.stats != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12.0,
                            runSpacing: 4.0,
                            children: [
                              _buildStat(context,
                                  icon: Icons.chat_bubble,
                                  value: form.stats!.total.toString(),
                                  tooltip: FormStrings.responses),
                              _buildStat(context,
                                  icon: Icons.check_circle_outline,
                                  value: form.stats!.paidOrSent.toString(),
                                  tooltip: OrdersStrings.gridPaidOrSent),
                              _buildStat(context,
                                  icon: Icons.shopping_cart_outlined,
                                  value: form.stats!.ordered.toString(),
                                  tooltip: OrdersStrings.gridOrdered),
                              _buildStat(context,
                                  icon: Icons.cancel_outlined,
                                  value: form.stats!.storno.toString(),
                                  tooltip: OrdersStrings.gridCancelled),
                            ],
                          )
                        ],
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          form.isOpen == true
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: form.isOpen == true
                              ? ThemeConfig.greenColor(context)
                              : ThemeConfig.redColor(context),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          form.isOpen == true
                              ? FormStrings.statusOpen
                              : FormStrings.statusClosed,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: form.isOpen == true
                                ? ThemeConfig.greenColor(context)
                                : ThemeConfig.redColor(context),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: onSurfaceColor.withOpacity(0.5)),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

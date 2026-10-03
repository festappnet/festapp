import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'package:fstapp/components/navigation/navigation_paths.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/forms/views/form_editor_content.dart';
import 'package:fstapp/components/forms/views/form_responses_content.dart';
import 'package:fstapp/components/forms/views/form_settings_content.dart';
import '../form_strings.dart';
import 'package:fstapp/components/forms/views/form_design_content.dart';
import '../db_forms.dart';

@RoutePage()
class FormDetailPage extends StatefulWidget {
  final String formLink;
  final Future<List<FormModel>> Function(String)? loadForms;
  const FormDetailPage(
      {super.key,
      @PathParam('formLink') required this.formLink,
      this.loadForms});
  @override
  State<FormDetailPage> createState() => _FormDetailPageState();
}

class _FormDetailPageState extends State<FormDetailPage> {
  bool _ready = false;
  bool _failed = false;
  int _generation = 0;
  String? _link;
  List<FormModel> _forms = [];
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final link = context.routeData.inheritedPathParams
        .getString(AppRouter.linkFormatted);
    if (_link != link) {
      _link = link;
      _load();
    }
  }

  @override
  void didUpdateWidget(FormDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.formLink != widget.formLink) {
      _ready = false;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final link = _link!;
    try {
      final objects =
          await (widget.loadForms ?? DbForms.getAllFormsByOccasionLink)(link);
      if (!mounted || generation != _generation) return;
      setState(() {
        _forms = objects;
        _ready = RightsService.currentLink == link &&
            objects.any((f) => f.link == widget.formLink);
        _failed = !_ready;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  void _back() {
    RetainedDraftGuard.instance.leaveOwner(
        context, () => context.router.replaceAll([const FormsListRoute()]));
  }

  @override
  Widget build(BuildContext context) {
    if (_failed)
      return Scaffold(
        appBar: AppBar(
            leading: IconButton(
                icon: const Icon(Icons.arrow_back), onPressed: _back)),
        body: const Center(child: Text('Not found or access denied')),
      );
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return FormRouteScope(
        identity: widget.formLink,
        onDeleted: _back,
        onUpdated: _load,
        child: Scaffold(
            appBar: AppBar(
                automaticallyImplyLeading: false,
                leading: IconButton(
                    icon: const Icon(Icons.arrow_back), onPressed: _back),
                title: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      TextButton(
                          onPressed: _back,
                          child: Text(FormStrings.formsTitle)),
                      const Icon(Icons.chevron_right),
                      PopupMenuButton<FormModel>(
                          onSelected: (form) {
                            if (form.link != widget.formLink)
                              RetainedDraftGuard.instance.leaveOwner(
                                  context,
                                  () => context.router.navigate(
                                      FormDetailRoute(formLink: form.link!)));
                          },
                          itemBuilder: (_) => _forms
                              .map((form) => PopupMenuItem(
                                  value: form, child: Text(form.toString())))
                              .toList(),
                          child: Text(_forms
                              .firstWhere(
                                  (form) => form.link == widget.formLink)
                              .toString()))
                    ]))),
            body: AutoRouter(key: ValueKey(widget.formLink))));
  }
}

class FormRouteScope extends InheritedWidget {
  final String identity;
  final VoidCallback onDeleted;
  final VoidCallback onUpdated;
  const FormRouteScope(
      {super.key,
      required this.identity,
      required this.onDeleted,
      required this.onUpdated,
      required super.child});
  static FormRouteScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FormRouteScope>()!;
  @override
  bool updateShouldNotify(FormRouteScope oldWidget) =>
      oldWidget.identity != identity;
}

@RoutePage(name: 'FormTabsRoute')
class FormTab extends StatelessWidget {
  const FormTab({super.key});
  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return RoutedTabScaffold(tabs: [
      RoutedTabDefinition(
          slug: NavigationPaths.editor,
          route: const FormEditorRoute(),
          label: FormStrings.tabForm,
          icon: Icons.data_object),
      RoutedTabDefinition(
          slug: NavigationPaths.settings,
          route: const FormSettingsRoute(),
          label: CommonStrings.settings,
          icon: Icons.settings),
      RoutedTabDefinition(
          slug: NavigationPaths.design,
          route: const FormDesignRoute(),
          label: FormStrings.tabDesign,
          icon: Icons.palette),
      RoutedTabDefinition(
          slug: NavigationPaths.responses,
          route: const FormResponsesRoute(),
          label: FormStrings.tabResponses,
          icon: Icons.list),
    ]);
  }
}

@RoutePage()
class FormEditorPage extends StatelessWidget {
  const FormEditorPage({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = FormRouteScope.of(context);
    return FormEditorContent(
        formLink: scope.identity, onDataUpdated: scope.onUpdated);
  }
}

@RoutePage()
class FormSettingsPage extends StatelessWidget {
  const FormSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = FormRouteScope.of(context);
    return FormSettingsContent(
        formLink: scope.identity,
        onActionCompleted: scope.onDeleted,
        onDataUpdated: scope.onUpdated);
  }
}

@RoutePage()
class FormDesignPage extends StatelessWidget {
  const FormDesignPage({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = FormRouteScope.of(context);
    return FormDesignContent(
        formLink: scope.identity,
        onActionCompleted: scope.onDeleted,
        onDataUpdated: scope.onUpdated);
  }
}

@RoutePage()
class FormResponsesPage extends StatelessWidget {
  const FormResponsesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = FormRouteScope.of(context);
    return FormResponsesContent(formLink: scope.identity);
  }
}

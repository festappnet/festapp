import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/forms/views/form_design_settings.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class FormDesignContent extends StatefulWidget {
  final String? formLink;
  final Future<FormEditBundle?> Function(String)? loadBundle;
  final VoidCallback? onActionCompleted;
  final VoidCallback? onDataUpdated;

  const FormDesignContent({
    super.key,
    this.formLink,
    this.loadBundle,
    this.onActionCompleted,
    this.onDataUpdated,
  });

  @override
  State<FormDesignContent> createState() => _FormDesignContentState();
}

class _FormDesignContentState extends State<FormDesignContent> {
  FormModel? _form;
  String? _formLink;
  bool _isLoading = true;
  final _snapshot = EditorSnapshot();
  Object get _draft => [
        _form?.isCardDesign,
        _form?.primaryColor,
        _form?.secondaryColor,
        _form?.fontFamily,
        _form?.countdownStyle
      ];
  bool get _hasChanges => _form != null && _snapshot.differs(_draft);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newFormLink =
        widget.formLink ?? context.routeData.params.getString("formLink");
    if (newFormLink != _formLink) {
      _formLink = newFormLink;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (_formLink == null) return;
    if (mounted && _form == null) {
      setState(() => _isLoading = true);
    }
    final bundle =
        await (widget.loadBundle ?? DbForms.getFormForEdit)(_formLink!);
    if (mounted) {
      setState(() {
        _form = bundle?.form;
        _isLoading = false;
        _snapshot.accept(_draft);
      });
    }
  }

  Future<void> _saveChanges() async {
    if (_form == null) return;
    try {
      await DbForms.updateForm(_form!);
      if (!mounted) return;
      ToastHelper.Show(context, "${CommonStrings.saved}: ${_form?.title ?? ""}",
          severity: ToastSeverity.Ok);
      widget.onDataUpdated?.call();
      setState(() => _snapshot.accept(_draft));
    } catch (e) {
      if (!mounted) return;
      ToastHelper.Show(context, e.toString().replaceFirst("Exception: ", ""),
          severity: ToastSeverity.NotOk);
    }
  }

  Future<void> _cancelEdit() => _loadData();

  @override
  Widget build(BuildContext context) => NavigationDraftBoundary(
      isDirty: () => _hasChanges, child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_form == null) {
      return const Center(child: Text("Form not found"));
    }

    return Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
            child: FormDesignSettings(
              key: ObjectKey(_form),
              form: _form!,
              onChanged: () => setState(() {}),
            )),
      ),
      bottomNavigationBar: EditorActionBar(
        hasChanges: _hasChanges,
        enabled: RightsService.canEditOccasion(),
        onSave: _saveChanges,
        onDiscard: _cancelEdit,
      ),
    );
  }
}

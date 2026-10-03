import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/forms/views/form_design_settings.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class FormDesignContent extends StatefulWidget {
  final String? formLink;
  final VoidCallback? onActionCompleted;
  final VoidCallback? onDataUpdated;

  const FormDesignContent({
    super.key,
    this.formLink,
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
  bool _hasChanges = false;

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
    if (mounted) {
      setState(() => _isLoading = true);
    }
    final bundle = await DbForms.getFormForEdit(_formLink!);
    if (mounted) {
      setState(() {
        _form = bundle?.form;
        _isLoading = false;
        _hasChanges = false;
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
      setState(() => _hasChanges = false);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.Show(context, e.toString().replaceFirst("Exception: ", ""),
          severity: ToastSeverity.NotOk);
    }
  }

  void _cancelEdit() {
    widget.onActionCompleted?.call();
  }

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
              form: _form!,
              onChanged: () => setState(() => _hasChanges = true),
            )),
      ),
      bottomNavigationBar: Container(
        color: ThemeConfig.appBarColor(),
        padding: const EdgeInsets.all(10),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancelEdit,
                child: Text(CommonStrings.storno),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: (RightsService.canEditOccasion() && _hasChanges)
                    ? _saveChanges
                    : null,
                child: Text(CommonStrings.saveChanges),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

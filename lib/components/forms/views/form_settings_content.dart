import 'form_availability_status.dart';
import 'form_bank_account_picker.dart';
import 'form_settings_section.dart';
import 'customer_self_service_settings.dart';

import 'package:festapp_core/communication_tone.dart';
import 'package:fstapp/services/decimal_input.dart';
import 'package:fstapp/components/payments/payment_connection_api.dart';
import 'package:fstapp/components/payments/payment_editor_registry.dart';

import '../payment_method_strings.dart';

import 'package:fstapp/components/payments/payment_method_cards.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';

import 'form_variable_symbol_settings.dart';
import 'payment_qr_email_setting.dart';

import 'package:flutter/foundation.dart';
import 'package:fstapp/components/bank_accounts/db_bank_accounts.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_sync_status.dart';

import '../waitlist_strings.dart';

import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/navigation/root_route_navigation.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
// ignore_for_file: deprecated_member_use

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';

import 'form_public_link.dart';

import '../form_strings.dart';

import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';

class FormSettingsContent extends StatefulWidget {
  final String? formLink;
  final List<PaymentEditorConnector>? paymentProviders;
  // Preview fixtures can override the form’s online payment policy.
  final bool? showCardPayments;
  final Future<Map<String, dynamic>?> Function(int, int)? loadPaymentRecipient;
  final ValueListenable<({int accountId, int revision})>? bankConnectionChanges;
  final Future<FormEditBundle?> Function(String)? loadBundle;
  final Future<void> Function(FormEditorDraft)? saveForm;
  final VoidCallback? onActionCompleted;
  final VoidCallback? onDataUpdated;
  final VoidCallback? onOpenEditor;
  const FormSettingsContent({
    super.key,
    this.formLink,
    this.paymentProviders,
    this.showCardPayments,
    this.loadPaymentRecipient,
    this.bankConnectionChanges,
    this.onActionCompleted,
    this.onDataUpdated,
    this.onOpenEditor,
    this.loadBundle,
    this.saveForm,
  });

  @override
  State<FormSettingsContent> createState() => _FormSettingsContentState();
}

class _FormSettingsContentState extends State<FormSettingsContent> {
  final _snapshot = EditorSnapshot();
  List<PaymentEditorConnector> get _providers =>
      widget.paymentProviders ?? paymentEditors;
  PaymentEditorConnector get _provider =>
      _providers.firstWhere((p) => p.connector.id == _providerId);
  String? _providerId;
  Map<String, dynamic> _savedPayments = {};
  int? get _paymentUnitId =>
      (_form?.paymentMethodPolicy?['unitId'] as num?)?.toInt();
  bool get _onlinePaymentsVisible =>
      _paymentUnitId != null &&
      _form?.definition.occasionId != null &&
      (widget.showCardPayments ??
          (!RightsService.isDemoReadOnly &&
              (_form?.paymentMethodPolicy?['methods']
                      as Map?)?[_providerId]?['policyEnabled'] ==
                  true));
  String _deadlineMode = 'inherit';
  bool _cashEnabled = false;
  bool _paymentSelectionChanged = false;
  final _cashInstructionsController = TextEditingController();
  Object get _draft => [
    _form?.definition.customerSelfService,
    _form?.definition.bankAccountId,
    _bankEnabled,
    _cashEnabled,
    _cashInstructionsController.text,
    _deadlineMode,
    _paymentConnectionId,
    _savedPayments,
    _providerId,
    _titleController.text,
    _measurementEnabled,
    _purchaseTiming,
    _linkController.text,
    _deadlineDaysController.text,
    _startingNumberController.text,
    _reminderMode,
    _reminderDaysController.text,
    _variableSymbolType,
    _paymentMessageType,
    _showPaymentQrInEmail,
    _communicationTone,
  ];
  void _changed() {
    if (mounted) setState(() {});
  }

  final _formKey = GlobalKey<FormState>();
  FormEditorDraft? _form;
  String? _formLink;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();
  final TextEditingController _deadlineDaysController = TextEditingController();
  final TextEditingController _startingNumberController =
      TextEditingController();
  final _publicLinkSection = ExpansibleController();
  final _paymentMethodSection = ExpansibleController();
  final _transferSection = ExpansibleController();
  final _customerEmailSection = ExpansibleController();
  Iterable<ExpansibleController> get _sections => [
    _publicLinkSection,
    _paymentMethodSection,
    _transferSection,
    _customerEmailSection,
  ];

  final _transferDetailKey = GlobalKey();
  final _paymentMethodKey = GlobalKey();
  final _linkField = GlobalKey<FormFieldState<String>>();
  final _deadlineField = GlobalKey<FormFieldState<String>>();
  final _symbolPolicyField = GlobalKey<FormFieldState<String>>();
  final _startingNumberField = GlobalKey<FormFieldState<String>>();
  final _reminderField = GlobalKey<FormFieldState<String>>();
  final _linkFocus = FocusNode();
  final _deadlineFocus = FocusNode();
  final _symbolPolicyFocus = FocusNode();
  final _startingNumberFocus = FocusNode();
  final _reminderFocus = FocusNode();
  int _formReadGeneration = 0;
  bool _saving = false;

  String _reminderMode = 'inherit';
  final _reminderDaysController = TextEditingController();
  late FormFeature _formFeature;
  String? _linkError;
  String? _savedLink;
  bool _isLoading = true;
  bool get _canManageMeasurement => RightsService.hasCapability(
    AuthorizationCapabilities.formsMeasurementWrite,
  );
  bool get _canEdit =>
      RightsService.hasCapability(AuthorizationCapabilities.formsWrite);
  bool get _hasChanges =>
      _canEdit && !_isLoading && _form != null && _snapshot.differs(_draft);

  String _variableSymbolType = 'random';
  String _paymentMessageType = 'name_surname';
  bool _showPaymentQrInEmail = true;
  String _communicationTone = 'inherit';

  bool _measurementEnabled = false;
  String _purchaseTiming = 'order';
  bool get _paidPurchaseRequired =>
      _form?.definition.measurementStatus?['purchase_timing'] == 'paid' &&
      _form?.definition.measurementStatus?['meta_purchase_enabled'] == true;

  bool _bankEnabled = false,
      _paymentRecipientFailed = false,
      _paymentRecipientLoaded = false,
      _paymentRecipientLoading = false;
  String? _paymentConnectionId;
  Map<String, dynamic>? _paymentRecipient;
  int _paymentReadGeneration = 0;

  bool get _showMeasurement {
    final status = _form?.definition.measurementStatus;
    return status?['organization_enabled'] == true;
  }

  List<String> get _measurementStatusMessages {
    final status = _form?.definition.measurementStatus;
    final reasons = status?['blocked_reasons'];
    final messages = <String>[
      if (!_measurementEnabled) FormStrings.measurementDisabled,
      if (status?['unit_enabled'] != true)
        FormStrings.measurementFormUnitBlocked,
      // One plain-language reason for both platform gates (policy, runtime).
      if (_measurementEnabled &&
          (status?['organization_allowed'] != true ||
              status?['runtime_supported'] != true))
        RightsService.hasCapability(AuthorizationCapabilities.unitSettingsWrite)
            ? FormStrings.measurementPlatformBlocked
            : FormStrings.measurementAskUnitManager,
      if (_measurementEnabled &&
          reasons is List &&
          reasons.contains('no_destination'))
        FormStrings.measurementNoDestination,
      if (_measurementEnabled &&
          reasons is List &&
          reasons.contains('no_privacy_policy'))
        FormStrings.measurementNoPrivacyPolicy,
    ];
    return messages.isEmpty &&
            status?['eligible'] == true &&
            (reasons is List && reasons.isEmpty) &&
            _form?.definition.data?['analytics']?['enabled'] ==
                _measurementEnabled
        ? [FormStrings.measurementReady]
        : messages;
  }

  Widget _measurementStatusRow(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = message == FormStrings.measurementReady
        ? (Icons.check_circle_outline, scheme.primary)
        : message == FormStrings.measurementDisabled
        ? (Icons.info_outline, scheme.onSurfaceVariant)
        : (Icons.warning_amber_rounded, scheme.error);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }

  String get _unitTone => CommunicationTone.resolve(
    RightsService.currentUnit()?.data?[Tb.units.data_communication_tone],
  );

  @override
  void initState() {
    super.initState();
    RightsService.occasionLinkModelNotifier.addListener(_changed);
    _bankChanges =
        widget.bankConnectionChanges ??
        DbBankAccounts.current.connectionChanges;
    _bankChanges.addListener(_bankConnectionChanged);
    for (final controller in [
      _titleController,
      _linkController,
      _cashInstructionsController,
      _deadlineDaysController,
      _reminderDaysController,
      _startingNumberController,
    ]) {
      controller.addListener(_changed);
    }
    _formFeature =
        FeatureService.getFeatureDetails(FeatureConstants.form) as FormFeature;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateFormIdentity();
  }

  @override
  void didUpdateWidget(covariant FormSettingsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.formLink != widget.formLink) _updateFormIdentity();
  }

  void _updateFormIdentity() {
    final link =
        widget.formLink ?? context.routeData.params.getString('formLink');
    if (link == _formLink) return;
    _formLink = link;
    _paymentReadGeneration++;
    _formReadGeneration++;
    _form = null;
    _isLoading = true;
    for (final section in _sections) {
      section.collapse();
    }
    _loadData();
  }

  @override
  void dispose() {
    RightsService.occasionLinkModelNotifier.removeListener(_changed);
    _bankChanges.removeListener(_bankConnectionChanged);
    _titleController.dispose();
    _linkController.dispose();
    _deadlineDaysController.dispose();
    _cashInstructionsController.dispose();
    _reminderDaysController.dispose();
    _startingNumberController.dispose();
    for (final section in _sections) {
      section.dispose();
    }
    for (final focus in [
      _linkFocus,
      _deadlineFocus,
      _symbolPolicyFocus,
      _startingNumberFocus,
      _reminderFocus,
    ]) {
      focus.dispose();
    }
    super.dispose();
  }

  bool _reviewingPaymentTemplates = false;
  Future<void> _reviewPaymentTemplates() async {
    final form = _form;
    final id = form?.definition.id;
    if (id == null || _reviewingPaymentTemplates) return;
    setState(() => _reviewingPaymentTemplates = true);
    try {
      final audit = await DbForms.getPaymentTemplateAudit(id);
      if (!mounted || !identical(form, _form)) return;
      final compatible = audit['compatible'] == true;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AppAlertDialog(
          title: Text(PaymentMethodStrings.text('policyTemplateReview')),
          content: Text(
            PaymentMethodStrings.text(
              compatible ? 'policyTemplateReviewHint' : 'policyTemplateRepair',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(CommonStrings.cancel),
            ),
            if (compatible && audit['canReview'] == true)
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(PaymentMethodStrings.text('policyTemplateApprove')),
              ),
          ],
        ),
      );
      if (confirmed == true && mounted && identical(form, _form))
        await DbForms.reviewPaymentTemplates(id, audit['revision'] as String);
    } catch (error) {
      if (mounted)
        ToastHelper.Show(
          context,
          PaymentMethodStrings.text('policySaveFailed'),
          severity: ToastSeverity.NotOk,
        );
    } finally {
      if (mounted) setState(() => _reviewingPaymentTemplates = false);
    }
  }

  bool _refreshingBankAccounts = false;
  late final ValueListenable<({int accountId, int revision})> _bankChanges;

  Future<void> _bankConnectionChanged() async {
    final form = _form;
    final link = _formLink;
    final id = _bankChanges.value.accountId;
    if (!mounted ||
        _refreshingBankAccounts ||
        form == null ||
        link == null ||
        !(form.availableBankAccounts?.any((account) => account.id == id) ??
            false)) {
      return;
    }
    _refreshingBankAccounts = true;
    try {
      final bundle = await (widget.loadBundle ?? DbForms.getFormForEdit)(link);
      if (mounted && identical(_form, form) && bundle != null) {
        // Refresh operational facts only; preserve the form editor's draft.
        setState(
          () => form.availableBankAccounts = bundle.availableBankAccounts,
        );
      }
    } catch (error) {
      AppLogger.error('Could not refresh form bank account cards: $error');
    } finally {
      _refreshingBankAccounts = false;
    }
  }

  Future<void> _loadData() async {
    if (_formLink == null) return;
    if (mounted && _form == null) {
      setState(() => _isLoading = true);
    }
    final requestedLink = _formLink!;
    final generation = ++_formReadGeneration;
    final bundle = await (widget.loadBundle ?? DbForms.getFormForEdit)(
      requestedLink,
    );
    if (!mounted || generation != _formReadGeneration) return;

    _acceptForm(bundle?.form);
  }

  void _acceptForm(FormEditorDraft? form) {
    _paymentSelectionChanged = false;
    if (form != null) {
      _form = form;
      final payments = _form!.definition.data?['payments'];
      _bankEnabled = payments is Map && payments['bankEnabled'] == true;
      _cashEnabled = payments is Map && payments['cashEnabled'] == true;
      _cashInstructionsController.text = payments is Map
          ? payments['cashInstructions'] as String? ?? ''
          : '';
      _deadlineMode =
          _form!.definition.data?['payment_deadline']?['mode'] as String? ??
          (_form!.definition.deadlineDurationSeconds == null
              ? 'inherit'
              : 'custom');
      _savedPayments = Map<String, dynamic>.from(
        payments is Map ? payments : {},
      );
      _providerId = _providers
          .firstWhere(
            (p) => p.connectionId(_savedPayments) != null,
            orElse: () => _providers.first,
          )
          .connector
          .id;
      _paymentConnectionId = _provider.connectionId(_savedPayments);
      _paymentReadGeneration++;
      _paymentRecipient = null;
      _paymentRecipientFailed = false;
      _paymentRecipientLoaded = false;
      _paymentRecipientLoading = false;
      _loadRecipientIfNeeded();

      final analytics = _form!.definition.data?['analytics'];
      _measurementEnabled = analytics is Map && analytics['enabled'] == true;
      _purchaseTiming =
          analytics is Map && analytics['purchase_timing'] == 'paid'
          ? 'paid'
          : 'order';
      _savedLink = _form!.definition.link;
      _titleController.text = _form!.definition.title ?? '';
      _linkController.text = _form!.definition.link ?? '';
      _linkError = null;
      final reminderOverride =
          _form!.definition.data?[FormDefinition.metaIsReminderEnabled]
              as bool?;
      _reminderMode = reminderOverride == null
          ? 'inherit'
          : (reminderOverride ? 'enabled' : 'disabled');
      final reminderSeconds =
          _form!.definition.data?[FormDefinition.metaReminderIntervalSeconds]
              as int?;
      _reminderDaysController.text = reminderSeconds == null
          ? ''
          : (reminderSeconds / 86400).toString();

      final vsData =
          _form!.definition.data?[FormDefinition.metaVariableSymbol]
              as Map<String, dynamic>?;
      _variableSymbolType =
          vsData?[FormDefinition.metaType] as String? ?? 'random';
      if (_variableSymbolType == 'sequence') {
        final startNum = vsData?[FormDefinition.metaStartingNumber];
        _startingNumberController.text = startNum?.toString() ?? '';
      } else {
        _startingNumberController.text = '';
      }

      final msgData =
          _form!.definition.data?[FormDefinition.metaPaymentMessage]
              as Map<String, dynamic>?;
      _paymentMessageType =
          msgData?[FormDefinition.metaType] as String? ?? 'name_surname';

      _showPaymentQrInEmail = FormMetadata.showPaymentQrInEmail(
        _form!.definition.data,
      );

      final savedTone =
          _form!.definition.data?[FormMetadata.metaCommunicationTone];
      _communicationTone =
          CommunicationTone.parse(savedTone) ?? CommunicationTone.inherit;

      _deadlineDaysController.text =
          (_form!.definition.effectiveDeadlineDurationSeconds(
                    occasionDefault: _formFeature.deadlineDurationSeconds,
                  ) /
                  86400)
              .round()
              .toString();
    } else {
      _form = null;
    }
    _snapshot.accept(_draft);
    setState(() => _isLoading = false);
  }

  String? _validateLink(String? value) {
    if (value == null || value.isEmpty)
      return FormStrings.validationLinkRequired;
    if (value != _savedLink && !isValidPublicSlug(value)) {
      return FormStrings.validationLinkInvalidChars;
    }
    return null;
  }

  String? _validateReminder(String? value) {
    if (value == null || value.isEmpty) return null;
    final days = DecimalInput.tryParse(value);
    return days == null || !days.isFinite || days < 0
        ? FormStrings.nonNegativeDays
        : null;
  }

  void _revealSection(ExpansibleController section, GlobalKey target) {
    section.expand();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = target.currentContext;
      if (mounted && targetContext != null) {
        Scrollable.ensureVisible(targetContext, alignment: 0.1);
      }
    });
  }

  void _revealField(
    ExpansibleController section,
    GlobalKey<FormFieldState<String>> key,
    FocusNode focus,
  ) {
    section.expand();
    final form = _form;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fieldContext = key.currentContext;
      if (!mounted || !identical(form, _form) || fieldContext == null) return;
      focus.requestFocus();
      Scrollable.ensureVisible(
        fieldContext,
        alignment: 0.25,
        duration: const Duration(milliseconds: 250),
      );
    });
  }

  Future<void> _saveChanges(BuildContext currentContext) async {
    final form = _form;
    if (!_canEdit || form == null || _saving) return;
    final invalid = _formKey.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      for (final (key, section, focus) in [
        (_linkField, _publicLinkSection, _linkFocus),
        (
          _deadlineField,
          _bankEnabled ? _transferSection : _paymentMethodSection,
          _deadlineFocus,
        ),
        (_symbolPolicyField, _transferSection, _symbolPolicyFocus),
        (_startingNumberField, _transferSection, _startingNumberFocus),
        (_reminderField, _customerEmailSection, _reminderFocus),
      ]) {
        if (invalid.contains(key.currentState)) {
          _revealField(section, key, focus);
          break;
        }
      }
      ToastHelper.Show(
        currentContext,
        FormStrings.errorFixBeforeSave,
        severity: ToastSeverity.NotOk,
      );
      return;
    }
    final reminderDays = DecimalInput.tryParse(_reminderDaysController.text);
    final originalDefinition = form.definition;
    final generation = _formReadGeneration;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);

    final trimmedTitle = _titleController.text.trim();
    _form!.definition = _form!.definition.copyWith(
      title: trimmedTitle.isEmpty ? null : trimmedTitle,
    );
    _form!.definition = _form!.definition.copyWith(link: _linkController.text);
    final metadata = <String, dynamic>{...?_form!.definition.data};
    if (_reminderMode == 'inherit') {
      metadata.remove(FormDefinition.metaIsReminderEnabled);
    } else {
      metadata[FormDefinition.metaIsReminderEnabled] =
          _reminderMode == 'enabled';
    }
    if (reminderDays == null) {
      metadata.remove(FormDefinition.metaReminderIntervalSeconds);
    } else {
      metadata[FormDefinition.metaReminderIntervalSeconds] =
          (reminderDays * 86400).round();
    }

    if (_variableSymbolType == 'sequence') {
      final startingNumber = int.tryParse(_startingNumberController.text);
      metadata[FormDefinition.metaVariableSymbol] = {
        FormDefinition.metaType: 'sequence',
        FormDefinition.metaStartingNumber: startingNumber,
      };
    } else {
      metadata[FormDefinition.metaVariableSymbol] = {
        FormDefinition.metaType: 'random',
      };
    }

    metadata[FormDefinition.metaPaymentMessage] = {
      FormDefinition.metaType: _paymentMessageType,
    };

    if (!_showPaymentQrInEmail ||
        metadata.containsKey(FormMetadata.metaShowPaymentQrInEmail)) {
      metadata[FormMetadata.metaShowPaymentQrInEmail] = _showPaymentQrInEmail;
    }

    if (metadata.containsKey('payments') ||
        !_bankEnabled ||
        _paymentConnectionId != null) {
      _capturePaymentConfiguration();
      metadata['payments'] = {
        ..._savedPayments,
        'bankEnabled': _bankEnabled,
        'cashEnabled': _cashEnabled,
        'cashInstructions': _cashInstructionsController.text,
        if (_cashEnabled) 'providerConnections': <String, String>{},
      };
    }

    if (_communicationTone == 'inherit') {
      metadata.remove(FormMetadata.metaCommunicationTone);
    } else {
      metadata[FormMetadata.metaCommunicationTone] = _communicationTone;
    }

    if (_canManageMeasurement && _showMeasurement) {
      metadata['analytics'] = {
        'enabled': _measurementEnabled,
        'purchase_timing': _paidPurchaseRequired ? 'paid' : _purchaseTiming,
      };
    }

    metadata['payment_deadline'] = {
      'mode': _cashEnabled ? 'none' : _deadlineMode,
    };
    _form!.definition = _form!.definition.copyWith(
      data: metadata,
      deadlineDurationSeconds: !_cashEnabled && _deadlineMode == 'custom'
          ? _customDeadlineSeconds ??
                (!_bankEnabled && _cardConfigured
                    ? originalDefinition.deadlineDurationSeconds
                    : null)
          : null,
    );

    try {
      var saved = form;
      if (widget.saveForm != null) {
        await widget.saveForm!(form);
      } else {
        saved = await DbForms.updateForm(
          form,
          paymentSelectionChanged: _paymentSelectionChanged,
        );
      }
      if (!mounted || generation != _formReadGeneration) return;
      _form = saved;
      _savedLink = saved.definition.link;
      ToastHelper.Show(
        currentContext,
        "${CommonStrings.saved}: ${_form?.definition.title ?? ""}",
        severity: ToastSeverity.Ok,
      );
      final renamed = _formLink != _form!.definition.link;
      if (renamed) {
        setState(() {
          _formLink = _form!.definition.link;
        });
      }
      _acceptForm(_form);
      if (renamed && mounted) {
        context.router.markUrlStateForReplace();
        await context.router.navigate(
          FormDetailRoute(
            formLink: _form!.definition.link!,
            children: [
              const FormTabsRoute(children: [FormSettingsRoute()]),
            ],
          ),
        );
      } else {
        widget.onDataUpdated?.call();
      }
    } catch (e) {
      if (!mounted || generation != _formReadGeneration) return;
      form.definition = originalDefinition;
      var errorMessage = FormStrings.saveError(e);
      if (errorMessage.endsWith('_RECIPIENT_UNAVAILABLE'))
        errorMessage = PaymentMethodStrings.reason('recipient_changed');
      final providerReason = RegExp(
        r'STRIPE_CONFIGURATION_UNSUPPORTED:\s*([a-z_]+)',
      ).firstMatch(errorMessage)?.group(1);
      if (providerReason != null)
        errorMessage = PaymentMethodStrings.reason(providerReason);
      for (final code in [
        'CAPACITY_BELOW_COMMITTED',
        'WAITLIST_HAS_ACTIVE_ENTRIES',
        'BLUEPRINT_CONFLICT',
      ]) {
        if (errorMessage.contains(code)) {
          errorMessage = WaitlistStrings.text(code);
          break;
        }
      }
      if (errorMessage.toLowerCase().contains("link")) {
        setState(() => _linkError = errorMessage);
        _revealField(_publicLinkSection, _linkField, _linkFocus);
      } else {
        ToastHelper.Show(
          currentContext,
          errorMessage,
          severity: ToastSeverity.NotOk,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelEdit() => _loadData();

  Future<void> _deleteForm(BuildContext currentContext) async {
    if (!_canEdit) return;
    try {
      await DbForms.deleteForm(
        _form!.definition.id!,
        expectedVersion: _form!.aggregateVersion,
      );
      if (!mounted) return;
      ToastHelper.Show(
        currentContext,
        "${CommonStrings.deleted}: ${_form!.definition.title ?? _form!.definition.link}",
      );
      widget.onActionCompleted?.call();
    } catch (e) {
      if (!mounted) return;
      ToastHelper.Show(
        currentContext,
        e.toString().replaceFirst("Exception: ", ""),
        severity: ToastSeverity.NotOk,
      );
    }
  }

  Future<void> _confirmDelete(BuildContext currentContext) async {
    bool? confirm = await showDialog<bool>(
      context: currentContext,
      builder: (context) => AppAlertDialog(
        onClose: () => Navigator.of(context).pop(false),
        insetPadding: const EdgeInsets.all(16.0),
        title: Text(FormStrings.deleteFormTitle),
        content: Text(FormStrings.deleteFormContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(CommonStrings.storno),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              CommonStrings.delete,
              style: TextStyle(color: ThemeConfig.redColor(context)),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      if (!mounted) return;
      await _deleteForm(currentContext);
    }
  }

  Widget _buildBankSummary(BuildContext context) {
    final form = _form!;
    final accounts = formBankTransferAccounts(
      form,
      formBankTransferCurrencies(form),
      accountId: form.definition.bankAccountId,
    );
    final currenciesByAccount = <BankAccountModel, List<String>>{};
    final missingCurrencies = <String>[];
    for (final entry in accounts.entries) {
      if (entry.value case final account?) {
        (currenciesByAccount[account] ??= []).add(entry.key);
      } else {
        missingCurrencies.add(entry.key);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (accounts.isNotEmpty && form.definition.bankAccountId == null) ...[
          Text(
            BankAccountStrings.formAccountDefaultPlain,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
        ],
        if (currenciesByAccount.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final entry in currenciesByAccount.entries)
                _buildReceivingAccountCard(context, entry.key, entry.value),
            ],
          ),
        if (missingCurrencies.isNotEmpty) ...[
          if (currenciesByAccount.isNotEmpty) const SizedBox(height: 8),
          Text(
            BankAccountStrings.missingAccountForCurrencies(
              missingCurrencies.join(', '),
            ),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(
            onPressed: () =>
                _revealSection(_transferSection, _transferDetailKey),
            child: Text(BankAccountStrings.formAccountLabel),
          ),
        ],
      ],
    );
  }

  Widget _buildReceivingAccountCard(
    BuildContext context,
    BankAccountModel account,
    List<String> currencies,
  ) => SizedBox(
    width: 300,
    child: Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: ThemeConfig.grey300(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              account.title ?? BankAccountStrings.bankAccount,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            if (account.accountNumberHumanReadable ?? account.accountNumber
                case final number?) ...[
              const SizedBox(height: 2),
              SelectableText(number, style: const TextStyle(fontSize: 13)),
            ],
            BankAccountSyncStatus(account: account),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final currency in currencies)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: ThemeConfig.grey200(context),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: Text(
                      currency,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> _bankAccountSettings(BuildContext context) {
    final form = _form!;
    final currencies = formBankTransferCurrencies(form);
    final hasMissingAccount = formBankTransferAccounts(
      form,
      currencies,
      accountId: form.definition.bankAccountId,
    ).values.any((account) => account == null);
    final unitId = RightsService.currentUnit()?.id;
    final canManage =
        unitId != null &&
        unitId == _paymentUnitId &&
        RightsService.hasCapability(
          AuthorizationCapabilities.bankAccountsUnitManage,
        );
    return [
      FormBankAccountPicker(
        key: _transferDetailKey,
        form: form,
        currencies: currencies,
        canEdit: _canEdit,
        onChanged: _changed,
      ),
      if (hasMissingAccount)
        Text(
          canManage
              ? BankAccountStrings.addAccountForPayments
              : BankAccountStrings.askManagerForPaymentAccount,
        ),
      if (canManage)
        TextButton(
          onPressed: () => pushRootPath(
            context.router.root,
            '/unit/$unitId/edit/bank-accounts',
          ),
          child: Text(BankAccountStrings.bankAccountSettingsTitle),
        ),
    ];
  }

  bool get _cardConfigured => !_cashEnabled && _paymentConnectionId != null;

  void _loadRecipientIfNeeded() {
    if (_paymentRecipientLoaded || _cashEnabled) return;
    if (_cardConfigured || _paymentMethodSection.isExpanded) {
      _loadPaymentRecipient();
    }
  }

  void _capturePaymentConfiguration() {
    final connections = Map<String, dynamic>.from(
      _savedPayments['providerConnections'] as Map? ?? {},
    );
    connections.remove(_provider.connector.id);
    final legacy = _provider.legacyConnectionField;
    if (legacy != null) _savedPayments.remove(legacy);
    if (_paymentConnectionId != null) {
      connections[_provider.connector.id] = _paymentConnectionId;
    }
    if (connections.isEmpty) {
      _savedPayments.remove('providerConnections');
    } else {
      _savedPayments['providerConnections'] = connections;
    }
  }

  void _selectPaymentProvider(String id) {
    _capturePaymentConfiguration();
    setState(() {
      _providerId = id;
      _paymentConnectionId = _provider.connectionId(_savedPayments);
      _paymentRecipient = null;
      _paymentRecipientLoaded = false;
      _paymentRecipientFailed = false;
      _paymentRecipientLoading = false;
      _paymentReadGeneration++;
    });
    _loadRecipientIfNeeded();
  }

  Future<void> _loadPaymentRecipient() async {
    final unit = _paymentUnitId;
    final occasion = _form?.definition.occasionId;
    if (!_canEdit ||
        unit == null ||
        occasion == null ||
        (!_onlinePaymentsVisible && !_cardConfigured) ||
        _paymentRecipientLoading)
      return;
    final generation = ++_paymentReadGeneration;
    setState(() => _paymentRecipientLoading = true);
    try {
      final value =
          await (widget.loadPaymentRecipient?.call(unit, occasion) ??
              SupabasePaymentConnectionApi(connector: _provider.connector)
                  .formRecipient(unit, occasion));
      if (mounted && generation == _paymentReadGeneration)
        setState(() {
          _paymentRecipient = value;
          _paymentRecipientLoaded = true;
          _paymentRecipientFailed = false;
        });
    } catch (_) {
      if (mounted && generation == _paymentReadGeneration)
        setState(() {
          _paymentRecipientFailed = true;
          _paymentRecipientLoaded = true;
        });
    } finally {
      if (mounted && generation == _paymentReadGeneration)
        setState(() => _paymentRecipientLoading = false);
    }
  }

  String? get _draftCardCompatibility {
    if (_paymentRecipient?['unsupportedReason'] is String)
      return _paymentRecipient!['unsupportedReason'];
    final products = _form!.relatedFields
        .where((field) => field.definition.isHidden != true)
        .expand(
          (field) => field.definition.productType?.products ?? <ProductModel>[],
        )
        .where((product) => product.isHidden != true)
        .toList();
    final currencies = products.map((product) => product.currencyCode).toSet();
    if (currencies.length != 1 ||
        !_provider.supportedCurrencies.contains(currencies.single))
      return 'currency_unsupported';
    if (products.any(
      (product) =>
          product.data?['deposit'] is Map &&
          (num.tryParse(product.data!['deposit']['amount'].toString()) ?? 0) >
              0,
    ))
      return 'deposit_unsupported';
    if (products.any(
      (product) =>
          product.data?['meta_surcharge'] is Map &&
          (product.data!['meta_surcharge'] as Map).isNotEmpty,
    ))
      return 'surcharge_unsupported';
    return null;
  }

  String? get _candidateConnectionId =>
      switch (_paymentRecipient?['connectionId']) {
        final String id => id,
        _ => null,
      };

  bool get _canSelectRecipient =>
      _onlinePaymentsVisible &&
      _paymentRecipient?['modelVerified'] == true &&
      {'connected', 'restricted'}.contains(_paymentRecipient?['state']) &&
      _candidateConnectionId != null &&
      _draftCardCompatibility == null;

  FormPaymentMethod? get _paymentMethod => _cashEnabled
      ? FormPaymentMethod.cash
      : _cardConfigured
      ? (_bankEnabled ? FormPaymentMethod.both : FormPaymentMethod.online)
      : (_bankEnabled ? FormPaymentMethod.bank : null);

  Widget _buildRecipientStatus(
    BuildContext context, {
    required bool configured,
  }) {
    final recipient = _paymentRecipient;
    final matches =
        configured && _candidateConnectionId == _paymentConnectionId;
    final compatibility = _draftCardCompatibility;
    final diagnostics = <String>[
      if (configured && !_onlinePaymentsVisible)
        PaymentMethodStrings.reason('payments_disabled'),
      if (_paymentRecipientFailed)
        PaymentMethodStrings.reason('unavailable')
      else if (configured && !_canEdit && _onlinePaymentsVisible)
        FormStrings.cardUnverified
      else if (_paymentRecipientLoaded && configured && !matches)
        PaymentMethodStrings.text('configuredRecipientUnavailable')
      else if (_paymentRecipientLoaded && recipient == null)
        PaymentMethodStrings.reason('not_configured'),
      if (recipient != null && (!configured || matches)) ...[
        if (recipient['modelVerified'] != true)
          PaymentMethodStrings.reason('model_unverified'),
        if (recipient['paused'] == true)
          PaymentMethodStrings.reason('paused')
        else if (recipient['chargesEnabled'] != true ||
            recipient['cardPaymentsActive'] != true ||
            recipient['state'] != 'connected')
          PaymentMethodStrings.reason(_provider.restrictedReason),
      ],
      if (compatibility != null) PaymentMethodStrings.reason(compatibility),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recipient?['name'] case final String name)
          Text(
            matches
                ? PaymentMethodStrings.recipient(name)
                : '${PaymentMethodStrings.text('availableRecipient')} · $name',
          ),
        if (_paymentRecipientLoading)
          const LinearProgressIndicator()
        else if (matches && diagnostics.isEmpty)
          Text(FormStrings.cardRecipientVerified),
        for (final diagnostic in diagnostics) Text(diagnostic),
        if (_paymentRecipientFailed)
          TextButton(
            onPressed: _paymentRecipientLoading ? null : _loadPaymentRecipient,
            child: Text(PaymentMethodStrings.text('checkAccount')),
          )
        else if (configured &&
            _canEdit &&
            diagnostics.isNotEmpty &&
            !_paymentMethodSection.isExpanded)
          TextButton(
            onPressed: () =>
                _revealSection(_paymentMethodSection, _paymentMethodKey),
            child: Text(FormStrings.resolvePaymentMethod),
          ),
      ],
    );
  }

  List<Widget> _paymentMethodSettings(BuildContext context) {
    final unit = _paymentUnitId;
    final canConnect =
        unit != null &&
        unit == RightsService.currentUnit()?.id &&
        _provider.canManage();
    final cardEnabled = _onlinePaymentsVisible && _cardConfigured;
    return [
      if (_onlinePaymentsVisible && _providers.length > 1)
        DropdownButton<String>(
          value: _providerId,
          items: [
            for (final p in _providers)
              DropdownMenuItem(
                value: p.connector.id,
                child: Text(PaymentMethodStrings.text(p.titleKey)),
              ),
          ],
          onChanged: (id) {
            if (id != null) _selectPaymentProvider(id);
          },
        ),
      PaymentMethodCards(
        showBank:
            (_form?.paymentMethodPolicy?['methods']
                as Map?)?['bank']?['policyEnabled'] ==
            true,
        showCash:
            (_form?.paymentMethodPolicy?['methods']
                as Map?)?['cash']?['policyEnabled'] ==
            true,
        showOnline: _onlinePaymentsVisible,
        value: _cashEnabled
            ? FormPaymentMethod.cash
            : cardEnabled
            ? (_bankEnabled ? FormPaymentMethod.both : FormPaymentMethod.online)
            : (_bankEnabled ? FormPaymentMethod.bank : null),
        canSelectOnline: _cardConfigured || _canSelectRecipient,
        onlineTitle: PaymentMethodStrings.text(_provider.titleKey),
        onChanged: (method) {
          final leavingCash = _cashEnabled && method != FormPaymentMethod.cash;
          setState(() {
            _paymentSelectionChanged = true;
            _cashEnabled = method == FormPaymentMethod.cash;
            _bankEnabled =
                method == FormPaymentMethod.bank ||
                method == FormPaymentMethod.both;
            if (_cashEnabled) {
              _deadlineMode = 'none';
              _savedPayments['providerConnections'] = <String, String>{};
            }
            // Keep an explicitly configured recipient, including stale ones,
            // until the editor chooses its replacement below.
            _paymentConnectionId =
                method == FormPaymentMethod.bank ||
                    method == FormPaymentMethod.cash
                ? null
                : (_paymentConnectionId ?? _candidateConnectionId);
          });
          if (leavingCash) _loadRecipientIfNeeded();
        },
      ),

      if (_cashEnabled) ...[
        const SizedBox(height: 16),
        TextFormField(
          controller: _cashInstructionsController,
          onChanged: (_) => setState(() => _paymentSelectionChanged = true),
          maxLength: 1000,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: PaymentMethodStrings.text('cashInstructions'),
            hintText: PaymentMethodStrings.text('cashInstructionsDefault'),
            floatingLabelBehavior: FloatingLabelBehavior.always,
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.all(16),
            helperText: PaymentMethodStrings.text('cashDeadlineHelp'),
            helperMaxLines: 3,
          ),
        ),
      ],
      if (!_cashEnabled && !_bankEnabled && !_cardConfigured) ...[
        const SizedBox(height: 16),
        ..._deadlineSettings(),
      ],
      if ((_onlinePaymentsVisible || _cardConfigured) && !_cashEnabled) ...[
        const SizedBox(height: 16),
        if (!_cardConfigured || formBankTransferCurrencies(_form!).isEmpty)
          _buildRecipientStatus(context, configured: _cardConfigured),
        if (_cardConfigured &&
            _candidateConnectionId != null &&
            _candidateConnectionId != _paymentConnectionId) ...[
          Text(PaymentMethodStrings.reason('recipient_changed')),
          TextButton(
            onPressed: _canSelectRecipient
                ? () => setState(() {
                    _paymentConnectionId = _candidateConnectionId;
                    _paymentSelectionChanged = true;
                  })
                : null,
            child: Text(PaymentMethodStrings.text('selectRecipient')),
          ),
        ],
        if (canConnect)
          TextButton(
            onPressed: () =>
                pushRootPath(context.router.root, _provider.settingsPath(unit)),
            child: Text(PaymentMethodStrings.text(_provider.setupKey)),
          ),
      ],
    ];
  }

  int? get _customDeadlineSeconds {
    final days = int.tryParse(_deadlineDaysController.text);
    if (days == null || days < 0) return null;
    final savedDuration = _form!.definition.deadlineDurationSeconds;
    if (savedDuration != null && (savedDuration / 86400).round() == days) {
      return savedDuration;
    }
    return days * 86400;
  }

  String get _bankDeadlineSummary {
    final customSeconds = _customDeadlineSeconds;
    if (_deadlineMode == 'none' ||
        (_deadlineMode == 'inherit' &&
            _formFeature.paymentDeadlineMode == 'none')) {
      return PaymentMethodStrings.text('deadlineNone');
    }
    if (_deadlineMode == 'custom') {
      return customSeconds == null
          ? FormStrings.invalidPaymentDeadline
          : FormStrings.customPaymentDeadline(customSeconds / 86400);
    }
    return FormStrings.inheritedPaymentDeadline(
      _form!.definition.effectiveDeadlineDurationSeconds(
            occasionDefault: _formFeature.deadlineDurationSeconds,
          ) /
          86400,
    );
  }

  Widget _buildPaymentSummary(BuildContext context) {
    final currencies = formBankTransferCurrencies(_form!);
    final hasPaidProducts = currencies.isNotEmpty;
    final providerTitle = PaymentMethodStrings.text(_provider.titleKey);
    final method = switch (_paymentMethod) {
      FormPaymentMethod.bank => PaymentMethodStrings.text('bank'),
      FormPaymentMethod.online => providerTitle,
      FormPaymentMethod.both =>
        '${PaymentMethodStrings.text('bank')} + $providerTitle',
      FormPaymentMethod.cash => PaymentMethodStrings.text('cash'),
      null =>
        hasPaidProducts ? PaymentMethodStrings.text('noMethodSelected') : null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          FormStrings.paymentDetailsTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        if (!hasPaidProducts) Text(FormStrings.noPaidProducts),
        if (method != null)
          Text(method, style: Theme.of(context).textTheme.titleMedium),
        if (_cashEnabled)
          Text(
            _cashInstructionsController.text.trim().isEmpty
                ? PaymentMethodStrings.text('cashInstructionsDefault')
                : _cashInstructionsController.text.trim(),
          ),
        if (_cashEnabled)
          Text(PaymentMethodStrings.text('cashDeadlineHelp'))
        else if (_bankEnabled)
          Text(_bankDeadlineSummary),
        if (_bankEnabled && hasPaidProducts) ...[
          if (!_methodAllowed('bank'))
            Text(FormStrings.methodDisabled(PaymentMethodStrings.text('bank'))),
          const SizedBox(height: 8),
          _buildBankSummary(context),
        ],
        if (_cashEnabled && hasPaidProducts && !_methodAllowed('cash'))
          Text(FormStrings.methodDisabled(PaymentMethodStrings.text('cash'))),
        if (_cardConfigured && hasPaidProducts) ...[
          Text(FormStrings.cardPaymentAtCheckout),
          if (_form!.definition.payments != null)
            Text(
              PaymentMethodStrings.reservation(
                FormPaymentOptions.fromJson(_form!.definition.payments)
                    .reservationSeconds,
              ),
            ),
          _buildRecipientStatus(context, configured: true),
        ],
        if (_canEdit && !_bankEnabled && _cardConfigured)
          TextButton.icon(
            onPressed: _reviewingPaymentTemplates
                ? null
                : _reviewPaymentTemplates,
            icon: const Icon(Icons.mark_email_read_outlined),
            label: Text(PaymentMethodStrings.text('policyTemplateReview')),
          ),
        if (_canEdit)
          FormSettingsSection(
            key: _paymentMethodKey,
            title: FormStrings.changePaymentMethod,
            controller: _paymentMethodSection,
            onExpansionChanged: (expanded) {
              _changed();
              if (expanded) _loadRecipientIfNeeded();
            },
            children: _paymentMethodSettings(context),
          ),
        if (_bankEnabled)
          FormSettingsSection(
            title: FormStrings.transferDetails,
            controller: _transferSection,
            children: [
              ..._bankAccountSettings(context),
              const SizedBox(height: 16),
              ..._deadlineSettings(),
              const SizedBox(height: 16),
              ..._transferReferenceSettings(),
            ],
          ),
      ],
    );
  }

  bool _methodAllowed(String id) =>
      (_form?.paymentMethodPolicy?['methods'] as Map?)?[id]?['policyEnabled'] ==
      true;

  @override
  Widget build(BuildContext context) => NavigationDraftBoundary(
    isDirty: () => _hasChanges,
    child: _buildContent(context),
  );

  Widget _buildFormIdentity(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        enabled: _canEdit,
        controller: _titleController,
        minLines: 1,
        maxLines: 2,
        textInputAction: TextInputAction.done,
        inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
        decoration: InputDecoration(
          labelText: FormStrings.labelFormTitle,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FormAvailabilityStatus(form: _form!),
          if (widget.onOpenEditor != null)
            TextButton(
              onPressed: widget.onOpenEditor,
              child: Text(FormStrings.openFormTab),
            ),
        ],
      ),
      const SizedBox(height: 12),
      PublicLink(
        link: _linkController.text,
        savedLink: _savedLink,
        showOpenAction: true,
      ),
      FormSettingsSection(
        title: FormStrings.publicLinkSettings,
        controller: _publicLinkSection,
        children: [
          if (_canEdit)
            TextFormField(
              key: _linkField,
              focusNode: _linkFocus,
              controller: _linkController,
              validator: _validateLink,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                labelText: FormStrings.labelFormLink,
                errorText: _linkError,
                helperText: FormStrings.publicLinkHistoryHelp,
                helperMaxLines: 6,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_linkError != null) setState(() => _linkError = null);
              },
            ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FormEmbedAction(
              savedLink: _savedLink,
              onOpenAppearance: _savedLink == null
                  ? null
                  : () => context.tabsRouter.navigate(const FormDesignRoute()),
            ),
          ),
        ],
      ),
    ],
  );

  List<Widget> _deadlineSettings() => [
    DropdownButtonFormField<String>(
      key: const ValueKey('form-payment-deadline-mode'),
      initialValue: _cashEnabled ? 'none' : _deadlineMode,
      isExpanded: true,
      decoration: InputDecoration(labelText: FormStrings.paymentDeadlineLabel),
      items: [
        for (final mode in ['inherit', 'custom', 'none'])
          DropdownMenuItem(
            value: mode,
            child: Text(
              PaymentMethodStrings.text(
                {
                  'inherit': 'deadlineInherit',
                  'custom': 'deadlineCustom',
                  'none': 'deadlineNone',
                }[mode]!,
              ),
            ),
          ),
      ],
      onChanged: !_canEdit || _cashEnabled
          ? null
          : (mode) => setState(() {
              _deadlineMode = mode!;
              _paymentSelectionChanged = true;
            }),
    ),
    if (!_cashEnabled && _deadlineMode == 'custom') ...[
      const SizedBox(height: 16),
      TextFormField(
        key: _deadlineField,
        focusNode: _deadlineFocus,
        enabled: _canEdit,
        controller: _deadlineDaysController,
        onChanged: (_) => setState(() => _paymentSelectionChanged = true),
        validator: (_) =>
            _deadlineMode == 'custom' && _customDeadlineSeconds == null
            ? CommonStrings.fieldCannotBeEmpty
            : null,
        decoration: InputDecoration(
          labelText: FormStrings.labelDeadlineDays,
          suffixIcon: IconButton(
            tooltip: FormStrings.inheritDays(
              (_formFeature.deadlineDurationSeconds ?? 604800) / 86400,
            ),
            icon: const Icon(Icons.restore),
            onPressed: !_canEdit
                ? null
                : () => setState(() {
                    _deadlineMode = 'inherit';
                    _paymentSelectionChanged = true;
                  }),
          ),
          border: const OutlineInputBorder(),
          helperText: FormStrings.inheritDays(
            (_formFeature.deadlineDurationSeconds ?? 604800) / 86400,
          ),
          helperMaxLines: 5,
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
    ],
  ];

  List<Widget> _transferReferenceSettings() => [
    FormVariableSymbolSettings(
      policyKey: _symbolPolicyField,
      startingNumberKey: _startingNumberField,
      policyFocus: _symbolPolicyFocus,
      startingNumberFocus: _startingNumberFocus,
      value: {
        FormDefinition.metaType: _variableSymbolType,
        FormDefinition.metaStartingNumber: int.tryParse(
          _startingNumberController.text,
        ),
      },
      enabled: _canEdit,
      onChanged: (value) => setState(() {
        _variableSymbolType = value[FormDefinition.metaType] as String;
        _startingNumberController.text =
            '${value[FormDefinition.metaStartingNumber] ?? ''}';
      }),
    ),
    const SizedBox(height: 16),
    DropdownButtonFormField<String>(
      isExpanded: true,
      value: _paymentMessageType,
      decoration: InputDecoration(
        labelText: FormStrings.labelPaymentMessage,
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem(
          value: 'name_surname',
          child: Text(FormStrings.msgTypeNameSurname),
        ),
        DropdownMenuItem(value: 'none', child: Text(FormStrings.msgTypeNone)),
        DropdownMenuItem(
          value: 'occasion_title',
          child: Text(FormStrings.msgTypeOccasionTitle),
        ),
      ],
      onChanged: _canEdit
          ? (value) {
              if (value != null) {
                setState(() {
                  _paymentMessageType = value;
                });
              }
            }
          : null,
    ),
  ];

  bool get _defaultReminders => _formFeature.reminderIsEnabled ?? true;
  bool get _remindersEnabled => _reminderMode == 'inherit'
      ? _defaultReminders
      : _reminderMode == 'enabled';

  Widget _buildCustomerEmailSettings() {
    final defaultReminders = _defaultReminders;
    final reminderSummary = !_remindersEnabled
        ? FormStrings.reminderSummaryOff
        : _reminderMode == 'inherit'
        ? FormStrings.reminderSummaryInherited
        : FormStrings.reminderSummaryOn;
    return FormSettingsSection(
      title: FormStrings.customerEmails,
      controller: _customerEmailSection,
      summary: [
        reminderSummary,
        if (_bankEnabled) FormStrings.paymentQrSummary(_showPaymentQrInEmail),
      ].join(' · '),
      children: [
        DropdownButtonFormField<String>(
          value: _reminderMode,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: FormStrings.labelEnableReminders,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: 'inherit',
              child: Text(FormStrings.inheritReminder(defaultReminders)),
            ),
            DropdownMenuItem(
              value: 'enabled',
              child: Text(FormStrings.remindersOn),
            ),
            DropdownMenuItem(
              value: 'disabled',
              child: Text(FormStrings.remindersOff),
            ),
          ],
          onChanged: _canEdit
              ? (value) => setState(() => _reminderMode = value!)
              : null,
        ),
        if (_remindersEnabled ||
            _validateReminder(_reminderDaysController.text) != null) ...[
          const SizedBox(height: 24),
          TextFormField(
            key: _reminderField,
            focusNode: _reminderFocus,
            enabled: _canEdit,
            controller: _reminderDaysController,
            decoration: InputDecoration(
              labelText: FormStrings.labelReminderInterval,
              border: const OutlineInputBorder(),
              helperText: FormStrings.inheritDays(
                (_formFeature.reminderIntervalSeconds ?? 86400) / 86400,
              ),
              helperMaxLines: 4,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: _validateReminder,
          ),
        ],

        const SizedBox(height: 16),
        Text(
          FormStrings.helperCommunicationTone,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _communicationTone,
          decoration: InputDecoration(
            labelText: FormStrings.labelCommunicationTone,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: 'inherit',
              child: Text(
                FormStrings.toneInherit(
                  _unitTone == 'informal'
                      ? FormStrings.toneInformal
                      : FormStrings.toneFormal,
                ),
              ),
            ),
            DropdownMenuItem(
              value: 'formal',
              child: Text(FormStrings.toneFormal),
            ),
            DropdownMenuItem(
              value: 'informal',
              child: Text(FormStrings.toneInformal),
            ),
          ],
          onChanged: _canEdit
              ? (value) {
                  if (value != null) {
                    setState(() {
                      _communicationTone = value;
                    });
                  }
                }
              : null,
        ),

        if (_bankEnabled) ...[
          const SizedBox(height: 16),
          PaymentQrEmailSetting(
            value: _showPaymentQrInEmail,
            onChanged: _canEdit
                ? (value) => setState(() => _showPaymentQrInEmail = value)
                : null,
          ),
        ],
      ],
    );
  }

  Widget _buildMeasurementSettings(BuildContext context) => FormSettingsSection(
    title: FormStrings.measurementTitle,
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(FormStrings.measurementEnabled),
        subtitle: Text(FormStrings.measurementFormHelp),
        value: _measurementEnabled,
        onChanged: _canEdit && _canManageMeasurement
            ? (value) => setState(() => _measurementEnabled = value)
            : null,
      ),
      DropdownButtonFormField<String>(
        initialValue: _paidPurchaseRequired ? 'paid' : _purchaseTiming,
        decoration: InputDecoration(
          labelText: FormStrings.purchaseTiming,
          helperText: _paidPurchaseRequired
              ? FormStrings.purchaseTimingCapi
              : FormStrings.purchaseTimingHelp,
          helperMaxLines: 4,
        ),
        items: [
          DropdownMenuItem(
            value: 'order',
            child: Text(FormStrings.purchaseTimingOrder),
          ),
          DropdownMenuItem(
            value: 'paid',
            child: Text(FormStrings.purchaseTimingPaid),
          ),
        ],
        onChanged: _canEdit && _canManageMeasurement && !_paidPurchaseRequired
            ? (value) => setState(() => _purchaseTiming = value ?? 'order')
            : null,
      ),
      const SizedBox(height: 16),
      Text(
        FormStrings.measurementBrowserChannel,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      for (final message in _measurementStatusMessages)
        _measurementStatusRow(context, message),
      if (_paidPurchaseRequired && _measurementEnabled)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(FormStrings.measurementMetaCapiHelp),
        ),
      const SizedBox(height: 8),
      if (RightsService.currentUnit()?.id != null &&
          RightsService.hasCapability(
            AuthorizationCapabilities.unitSettingsWrite,
          ))
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.tune, size: 18),
            label: Text(FormStrings.measurementOpenUnitSettings),
            onPressed: () => pushRootPath(
              context.router.root,
              '/unit/${RightsService.currentUnit()!.id}/edit/settings',
            ),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            FormStrings.measurementAskUnitManager,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  );

  Widget _buildContent(BuildContext context) {
    final form = _form;
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : form == null
          ? Center(child: Text(FormStrings.formNotFound))
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: StylesConfig.formMaxWidth,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: AbsorbPointer(
                    absorbing: _saving,
                    child: ExcludeFocus(
                      excluding: _saving,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          key: ObjectKey(form),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildFormIdentity(context),
                            const Divider(),
                            const SizedBox(height: 12),
                            _buildPaymentSummary(context),
                            const Divider(),
                            _buildCustomerEmailSettings(),
                            CustomerSelfServiceSettings(
                              form: form,
                              canEdit: _canEdit,
                              onChanged: _changed,
                            ),
                            if (_showMeasurement)
                              _buildMeasurementSettings(context),
                            const SizedBox(height: 24),
                            if (RightsService.hasCapability(
                              AuthorizationCapabilities.formsWrite,
                            ))
                              Center(
                                child: Tooltip(
                                  message: (_form?.definition.canDelete ?? true)
                                      ? ""
                                      : FormStrings
                                            .cannotDeleteFormWithResponses,
                                  child: TextButton(
                                    onPressed:
                                        (_form?.definition.canDelete ?? true)
                                        ? () => _confirmDelete(context)
                                        : null,
                                    child: Text(
                                      FormStrings.deleteFormTitle,
                                      style: TextStyle(
                                        color:
                                            (_form?.definition.canDelete ??
                                                true)
                                            ? ThemeConfig.redColor(context)
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: EditorActionBar(
        hasChanges: _hasChanges,
        enabled: _canEdit && !_saving,
        onDiscard: _cancelEdit,
        onSave: () => _saveChanges(context),
      ),
    );
  }
}

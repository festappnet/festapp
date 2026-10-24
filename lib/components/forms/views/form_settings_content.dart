import 'package:festapp_core/forms.dart';
import 'package:fstapp/services/decimal_input.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'waitlist_offers_dialog.dart';
import '../waitlist_strings.dart';
import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'package:fstapp/components/navigation/root_route_navigation.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/form_feature.dart';
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
import 'package:fstapp/components/stripe_payments/stripe_connection_api.dart';
import '../payment_method_strings.dart';
import 'package:fstapp/components/stripe_payments/payment_method_cards.dart';

class FormSettingsContent extends StatefulWidget {
  final String? formLink;
  final Future<FormEditBundle?> Function(String)? loadBundle;
  final Future<void> Function(FormEditorDraft)? saveForm;
  final Future<Map<String, dynamic>?> Function(int, int)? loadStripeRecipient;
  final VoidCallback? onActionCompleted;
  final VoidCallback? onDataUpdated;
  const FormSettingsContent(
      {super.key,
      this.formLink,
      this.onActionCompleted,
      this.onDataUpdated,
      this.loadBundle,
      this.loadStripeRecipient,
      this.saveForm});

  @override
  State<FormSettingsContent> createState() => _FormSettingsContentState();
}

class _FormSettingsContentState extends State<FormSettingsContent> {
  final _snapshot = EditorSnapshot();
  bool _deadlineInherited = true;
  final _bankSettingsLink = TapGestureRecognizer();
  Object get _draft => [
        _capacityController.text,
        _offerHoursController.text,
        _waitlistEnabled,
        _showRemaining,
        _titleController.text,
        _linkController.text,
        _deadlineDaysController.text,
        _deadlineInherited,
        _startingNumberController.text,
        _reminderMode,
        _reminderDaysController.text,
        _variableSymbolType,
        _paymentMessageType,
        _communicationTone,
        _bankEnabled,
        _stripeConnectionId,
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
  final ValueNotifier<String> _linkNotifier = ValueNotifier<String>("");

  final _capacityController = TextEditingController();
  final _offerHoursController = TextEditingController();
  bool _waitlistEnabled = false;
  bool _showRemaining = true;
  bool _capacityBlocked = false;
  String _reminderMode = 'inherit';
  final _reminderDaysController = TextEditingController();
  late FormFeature _formFeature;
  String? _linkError;
  String? _savedLink;
  bool _isLoading = true;
  bool get _hasChanges =>
      !_isLoading && _form != null && _snapshot.differs(_draft);

  String _variableSymbolType = 'random';
  String _paymentMessageType = 'name_surname';
  String _communicationTone = 'inherit';
  bool _bankEnabled = true,
      _stripeRecipientFailed = false,
      _stripeRecipientLoaded = false,
      _stripeRecipientLoading = false;
  String? _stripeConnectionId;
  Map<String, dynamic>? _stripeRecipient;
  int _stripeReadGeneration = 0;

  String get _unitTone =>
      RightsService.currentUnit()?.data?[Tb.units.data_communication_tone] ==
              'informal'
          ? 'informal'
          : 'formal';

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _capacityController,
      _offerHoursController,
      _titleController,
      _linkController,
      _deadlineDaysController,
      _reminderDaysController,
      _startingNumberController
    ]) {
      controller.addListener(_changed);
    }
    _formFeature =
        FeatureService.getFeatureDetails(FeatureConstants.form) as FormFeature;
  }

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

  @override
  void dispose() {
    _bankSettingsLink.dispose();
    _capacityController.dispose();
    _offerHoursController.dispose();
    _titleController.dispose();
    _linkController.removeListener(_updateLinkPreview);
    _linkController.dispose();
    _deadlineDaysController.dispose();
    _reminderDaysController.dispose();
    _startingNumberController.dispose();
    _linkNotifier.dispose();
    super.dispose();
  }

  void _updateLinkPreview() {
    _linkNotifier.value = _linkController.text;
  }

  Future<void> _loadData() async {
    if (_formLink == null) return;
    if (mounted && _form == null) {
      setState(() => _isLoading = true);
    }
    final requestedLink = _formLink!;
    final bundle =
        await (widget.loadBundle ?? DbForms.getFormForEdit)(requestedLink);
    if (!mounted || requestedLink != _formLink) return;

    if (bundle != null) {
      _form = bundle.form;
      final payments = _form!.definition.data?['payments'];
      _bankEnabled = payments is! Map || payments['bankEnabled'] != false;
      _stripeConnectionId =
          payments is Map && payments['stripeConnectionId'] is String
              ? payments['stripeConnectionId']
              : null;
      _stripeReadGeneration++;
      _stripeRecipient = null;
      _stripeRecipientFailed = false;
      _stripeRecipientLoaded = false;
      _stripeRecipientLoading = false;
      if (_stripeConnectionId != null) _loadStripeRecipient();
      _savedLink = _form!.definition.link;
      _titleController.text = _form!.definition.title ?? '';
      _linkController.text = _form!.definition.link ?? '';
      _linkNotifier.value = _linkController.text;
      _linkController.removeListener(_updateLinkPreview);
      _linkController.addListener(_updateLinkPreview);
      final reminderOverride = _form!
          .definition.data?[FormDefinition.metaIsReminderEnabled] as bool?;
      _reminderMode = reminderOverride == null
          ? 'inherit'
          : (reminderOverride ? 'enabled' : 'disabled');
      final reminderSeconds = _form!
          .definition.data?[FormDefinition.metaReminderIntervalSeconds] as int?;
      _reminderDaysController.text =
          reminderSeconds == null ? '' : (reminderSeconds / 86400).toString();

      final vsData = _form!.definition.data?[FormDefinition.metaVariableSymbol]
          as Map<String, dynamic>?;
      _variableSymbolType =
          vsData?[FormDefinition.metaType] as String? ?? 'random';
      if (_variableSymbolType == 'sequence') {
        final startNum = vsData?[FormDefinition.metaStartingNumber];
        _startingNumberController.text = startNum?.toString() ?? '';
      } else {
        _startingNumberController.text = '';
      }

      final msgData = _form!.definition.data?[FormDefinition.metaPaymentMessage]
          as Map<String, dynamic>?;
      _paymentMessageType =
          msgData?[FormDefinition.metaType] as String? ?? 'name_surname';

      final savedTone =
          _form!.definition.data?[FormMetadata.metaCommunicationTone];
      _communicationTone = savedTone == 'formal' || savedTone == 'informal'
          ? savedTone as String
          : 'inherit';

      _capacityController.text =
          _form!.definition.participantCapacity?.toString() ?? '';
      _offerHoursController.text =
          _form!.definition.waitlistOfferDurationSeconds == null
              ? ''
              : (_form!.definition.waitlistOfferDurationSeconds! / 3600)
                  .toString();
      _waitlistEnabled = _form!.definition.waitlistEnabled;
      _showRemaining = _form!.definition.showRemainingCapacity;
      _capacityBlocked = (_form!.definition.capacity?.waitingPeople ?? 0) +
              (_form!.definition.capacity?.offeredPlaces ?? 0) >
          0;
      _deadlineInherited = _form!.definition.deadlineDurationSeconds == null;
      _deadlineDaysController.text = (_form!.definition
                  .effectiveDeadlineDurationSeconds(
                      occasionDefault: _formFeature.deadlineDurationSeconds) /
              86400)
          .round()
          .toString();
    } else {
      _form = null;
    }
    _snapshot.accept(_draft);
    setState(() => _isLoading = false);
  }

  void _validateLink(String? value) {
    setState(() {
      if (value == null || value.isEmpty) {
        _linkError = FormStrings.validationLinkRequired;
      } else if (value != _savedLink && !isValidPublicSlug(value)) {
        _linkError = FormStrings.validationLinkInvalidChars;
      } else {
        _linkError = null;
      }
    });
  }

  Future<void> _saveChanges(BuildContext currentContext) async {
    _validateLink(_linkController.text);
    if (!_formKey.currentState!.validate() || _linkError != null) {
      ToastHelper.Show(currentContext, FormStrings.errorFixBeforeSave,
          severity: ToastSeverity.NotOk);
      return;
    }
    if (_form == null) return;

    final trimmedTitle = _titleController.text.trim();
    _form!.definition = _form!.definition
        .copyWith(title: trimmedTitle.isEmpty ? null : trimmedTitle);
    _form!.definition = _form!.definition.copyWith(link: _linkController.text);
    final metadata = <String, dynamic>{...?_form!.definition.data};
    if (_reminderMode == 'inherit') {
      metadata.remove(FormDefinition.metaIsReminderEnabled);
    } else {
      metadata[FormDefinition.metaIsReminderEnabled] =
          _reminderMode == 'enabled';
    }
    final reminderDays = DecimalInput.tryParse(_reminderDaysController.text);
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
    if (metadata.containsKey('payments') ||
        !_bankEnabled ||
        _stripeConnectionId != null) {
      metadata['payments'] = {
        'bankEnabled': _bankEnabled,
        if (_stripeConnectionId != null)
          'stripeConnectionId': _stripeConnectionId
      };
    }

    if (_communicationTone == 'inherit') {
      metadata.remove(FormMetadata.metaCommunicationTone);
    } else {
      metadata[FormMetadata.metaCommunicationTone] = _communicationTone;
    }

    _form!.definition = _form!.definition.copyWith(data: metadata);
    _form!.definition = _form!.definition
        .copyWith(participantCapacity: int.tryParse(_capacityController.text));
    _form!.definition =
        _form!.definition.copyWith(waitlistEnabled: _waitlistEnabled);
    _form!.definition =
        _form!.definition.copyWith(showRemainingCapacity: _showRemaining);
    _form!.definition = _form!.definition.copyWith(
        waitlistOfferDurationSeconds: _waitlistEnabled
            ? DecimalInput.positiveDurationSeconds(_offerHoursController.text,
                secondsPerUnit: 3600)
            : null);
    final days = int.tryParse(_deadlineDaysController.text);
    if (!_deadlineInherited && days != null && days >= 0) {
      _form!.definition = _form!.definition
          .copyWith(deadlineDurationSeconds: days * 24 * 60 * 60);
    } else {
      _form!.definition =
          _form!.definition.copyWith(deadlineDurationSeconds: null);
    }

    try {
      if (widget.saveForm != null) {
        await widget.saveForm!(_form!);
      } else {
        _form = await DbForms.updateForm(_form!);
      }
      _savedLink = _form!.definition.link;
      if (!mounted) return;
      ToastHelper.Show(currentContext,
          "${CommonStrings.saved}: ${_form?.definition.title ?? ""}",
          severity: ToastSeverity.Ok);
      final renamed = _formLink != _form!.definition.link;
      if (renamed) {
        setState(() {
          _formLink = _form!.definition.link;
        });
      }
      await _loadData();
      if (renamed && mounted) {
        context.router.markUrlStateForReplace();
        await context.router.navigate(
            FormDetailRoute(formLink: _form!.definition.link!, children: [
          const FormTabsRoute(children: [FormSettingsRoute()])
        ]));
      } else {
        widget.onDataUpdated?.call();
      }
    } catch (e) {
      _form?.definition = _form!.definition.copyWith(link: _savedLink);
      if (!mounted) return;
      var errorMessage = e.toString().replaceFirst("Exception: ", "");
      if (errorMessage.contains('STRIPE_RECIPIENT_UNAVAILABLE'))
        errorMessage = PaymentMethodStrings.reason('recipient_changed');
      final stripeReason =
          RegExp(r'STRIPE_CONFIGURATION_UNSUPPORTED:\s*([a-z_]+)')
              .firstMatch(errorMessage)
              ?.group(1);
      if (stripeReason != null)
        errorMessage = PaymentMethodStrings.reason(stripeReason);
      for (final code in [
        'CAPACITY_BELOW_COMMITTED',
        'WAITLIST_HAS_ACTIVE_ENTRIES',
        'BLUEPRINT_CONFLICT'
      ]) {
        if (errorMessage.contains(code)) {
          errorMessage = WaitlistStrings.text(code);
          break;
        }
      }
      if (errorMessage.toLowerCase().contains("link")) {
        setState(() => _linkError = errorMessage);
      } else {
        ToastHelper.Show(currentContext, errorMessage,
            severity: ToastSeverity.NotOk);
      }
    }
  }

  Future<void> _cancelEdit() => _loadData();

  Future<void> _deleteForm(BuildContext currentContext) async {
    try {
      await DbForms.deleteForm(_form!.definition.id!,
          expectedVersion: _form!.aggregateVersion);
      if (!mounted) return;
      ToastHelper.Show(currentContext,
          "${CommonStrings.deleted}: ${_form!.definition.title ?? _form!.definition.link}");
      widget.onActionCompleted?.call();
    } catch (e) {
      if (!mounted) return;
      ToastHelper.Show(
          currentContext, e.toString().replaceFirst("Exception: ", ""),
          severity: ToastSeverity.NotOk);
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
            child: Text(CommonStrings.delete,
                style: TextStyle(color: ThemeConfig.redColor(context))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      if (!mounted) return;
      await _deleteForm(currentContext);
    }
  }

  Set<String> _getFormCurrencies() {
    if (_form == null) return {};
    final currencies = <String>{};
    for (var field in _form!.relatedFields) {
      if (field.definition.productType != null) {
        for (var product in field.definition.productType!.products ?? []) {
          if (product.currencyCode != null &&
              product.currencyCode!.isNotEmpty) {
            currencies.add(product.currencyCode!);
          }
        }
      }
    }
    return currencies;
  }

  List<BankAccountModel> _getUsedBankAccounts() {
    if (_form == null || _form!.availableBankAccounts == null) return [];

    final usedCurrencies = _getFormCurrencies();
    if (usedCurrencies.isEmpty) return [];

    final usedAccounts = <BankAccountModel>{};

    // availableBankAccounts are sorted by priority ASC from DB
    // For each currency, pick the first account that supports it.
    for (final currency in usedCurrencies) {
      for (final account in _form!.availableBankAccounts!) {
        if (account.supportedCurrencies.contains(currency)) {
          usedAccounts.add(account);
          break;
        }
      }
    }
    return usedAccounts.toList();
  }

  Widget _buildUsedBankAccounts(BuildContext context) {
    if (_form == null) return const SizedBox.shrink();

    final usedCurrencies = _getFormCurrencies();
    if (usedCurrencies.isEmpty) return const SizedBox.shrink();

    final usedAccounts = _getUsedBankAccounts();
    final missingCurrencies = usedCurrencies
        .where((currency) => !usedAccounts
            .any((account) => account.supportedCurrencies.contains(currency)))
        .toList()
      ..sort();
    final unitId = RightsService.currentUnit()?.id;
    final canManageAccounts = unitId != null && RightsService.isUnitEditor();

    final guidance = missingCurrencies.isNotEmpty
        ? (canManageAccounts
            ? BankAccountStrings.addAccountForPayments
            : BankAccountStrings.askManagerForPaymentAccount)
        : BankAccountStrings.manageInUnitSettings;
    final settingsLabel = BankAccountStrings.organizationSettings;
    final linkStart = guidance.indexOf(settingsLabel);
    _bankSettingsLink.onTap = canManageAccounts
        ? () => pushRootPath(
            context.router.root, '/unit/$unitId/edit/bank-accounts')
        : null;

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (missingCurrencies.isNotEmpty) ...[
            Text(BankAccountStrings.missingAccountForCurrencies(
                missingCurrencies.join(', '))),
            const SizedBox(height: 4),
          ],
          Text.rich(
            TextSpan(
              children: canManageAccounts && linkStart >= 0
                  ? [
                      TextSpan(text: guidance.substring(0, linkStart)),
                      TextSpan(
                        text: settingsLabel,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                        mouseCursor: SystemMouseCursors.click,
                        recognizer: _bankSettingsLink,
                      ),
                      TextSpan(
                          text: guidance
                              .substring(linkStart + settingsLabel.length)),
                    ]
                  : [TextSpan(text: guidance)],
            ),
            style: missingCurrencies.isNotEmpty
                ? null
                : Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          if (usedAccounts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4, // Added runSpacing for better multiline layout
              children: usedAccounts.map((account) {
                return SizedBox(
                  width: 300,
                  child: Card(
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: ThemeConfig.grey300(context)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account.title ?? BankAccountStrings.bankAccount,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            account.accountNumberHumanReadable ??
                                account.accountNumber ??
                                '',
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (account.supportedCurrencies.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: account.supportedCurrencies
                                  .map((c) => Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: ThemeConfig.grey200(context),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: Colors.grey.shade400),
                                        ),
                                        child: Text(c,
                                            style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600)),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadStripeRecipient() async {
    final generation = ++_stripeReadGeneration;
    final unit = _form?.occasionModel?.unit,
        occasion = _form?.definition.occasionId;
    if (unit == null || occasion == null) return;
    setState(() => _stripeRecipientLoading = true);
    try {
      final value = await (widget.loadStripeRecipient?.call(unit, occasion) ??
          const SupabaseStripeConnectionApi().formRecipient(unit, occasion));
      if (mounted && generation == _stripeReadGeneration)
        setState(() {
          _stripeRecipient = value;
          _stripeRecipientLoaded = true;
          _stripeRecipientFailed = false;
        });
    } catch (_) {
      if (mounted && generation == _stripeReadGeneration)
        setState(() {
          _stripeRecipientFailed = true;
          _stripeRecipientLoaded = true;
        });
    } finally {
      if (mounted && generation == _stripeReadGeneration)
        setState(() => _stripeRecipientLoading = false);
    }
  }

  String? get _draftCardCompatibility {
    if (_stripeRecipient?['unsupportedReason'] is String)
      return _stripeRecipient!['unsupportedReason'];
    final products = _form!.relatedFields
        .where((field) => field.definition.isHidden != true)
        .expand((field) =>
            field.definition.productType?.products ?? <ProductModel>[])
        .where((product) => product.isHidden != true)
        .toList();
    final currencies = products.map((product) => product.currencyCode).toSet();
    if (currencies.length != 1 ||
        !{'CZK', 'EUR', 'PLN', 'USD', 'GBP'}.contains(currencies.single))
      return 'currency_unsupported';
    if (products.any((product) =>
        product.data?['deposit'] is Map &&
        (num.tryParse(product.data!['deposit']['amount'].toString()) ?? 0) > 0))
      return 'deposit_unsupported';
    if (products.any((product) =>
        product.data?['meta_surcharge'] is Map &&
        (product.data!['meta_surcharge'] as Map).isNotEmpty))
      return 'surcharge_unsupported';
    return null;
  }

  Widget _buildPaymentMethods(BuildContext context) {
    final recipient = _stripeRecipient;
    final String? candidate = recipient?['connectionId'] is String
        ? recipient!['connectionId']
        : null;
    final unit = _form?.occasionModel?.unit;
    final canConnect = unit != null &&
        unit == RightsService.currentUnit()?.id &&
        RightsService.isUnitManager();
    final cardEnabled = _stripeConnectionId != null;
    final compatibility = _draftCardCompatibility;
    final canSelect = recipient?['modelVerified'] == true &&
        {'connected', 'restricted'}.contains(recipient?['state']) &&
        candidate != null &&
        compatibility == null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(PaymentMethodStrings.text('title'),
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      PaymentMethodCards(
        value: cardEnabled
            ? (_bankEnabled ? FormPaymentMethod.both : FormPaymentMethod.stripe)
            : (_bankEnabled ? FormPaymentMethod.bank : null),
        canSelectStripe: cardEnabled || canSelect,
        onChanged: (method) => setState(() {
          _bankEnabled = method != FormPaymentMethod.stripe;
          // Keep an explicitly configured recipient, including stale ones,
          // until the editor chooses its replacement below.
          _stripeConnectionId = method == FormPaymentMethod.bank
              ? null
              : (_stripeConnectionId ?? candidate);
        }),
      ),
      const SizedBox(height: 16),
      if (!_bankEnabled && !cardEnabled)
        Text(PaymentMethodStrings.text('noMethodSelected')),
      if (_bankEnabled) ...[
        Text(PaymentMethodStrings.text('bank'),
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _buildUsedBankAccounts(context),
        const SizedBox(height: 16),
      ],
      Text(PaymentMethodStrings.text('stripe'),
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      if (_stripeRecipientLoading) const LinearProgressIndicator(),
      if (!_stripeRecipientLoaded || _stripeRecipientFailed)
        TextButton(
            onPressed: _stripeRecipientLoading ? null : _loadStripeRecipient,
            child: Text(PaymentMethodStrings.text('checkAccount'))),
      if (_stripeRecipientFailed)
        Text(PaymentMethodStrings.reason('unavailable'))
      else if (recipient == null && _stripeRecipientLoaded)
        Text(PaymentMethodStrings.reason('not_configured')),
      if (compatibility != null)
        Text(PaymentMethodStrings.reason(compatibility)),
      if (cardEnabled &&
          _stripeRecipientLoaded &&
          (recipient == null || candidate != _stripeConnectionId))
        Text(PaymentMethodStrings.text('configuredRecipientUnavailable')),
      if (recipient != null) ...[
        if (recipient['modelVerified'] != true)
          Text(PaymentMethodStrings.reason('model_unverified')),
        if (recipient['name'] is String)
          Text(!cardEnabled || candidate != _stripeConnectionId
              ? '${PaymentMethodStrings.text('availableRecipient')}: ${recipient['name']}'
              : PaymentMethodStrings.recipient(recipient['name'])),
        if (recipient['paused'] == true)
          Text(PaymentMethodStrings.reason('paused')),
        if (recipient['chargesEnabled'] != true ||
            recipient['cardPaymentsActive'] != true)
          Text(PaymentMethodStrings.reason('stripe_restricted')),
        if (cardEnabled && candidate != _stripeConnectionId) ...[
          Text(PaymentMethodStrings.reason('recipient_changed')),
          TextButton(
              onPressed: canSelect
                  ? () => setState(() => _stripeConnectionId = candidate)
                  : null,
              child: Text(PaymentMethodStrings.text('selectRecipient'))),
        ],
      ],
      if (cardEnabled) ...[
        Text(PaymentMethodStrings.text('fullAmount')),
        Text(PaymentMethodStrings.reservation(1860))
      ],
      if (canConnect)
        TextButton(
            onPressed: () => pushRootPath(
                context.router.root, '/unit/$unit/edit/card-payments'),
            child: Text(PaymentMethodStrings.text('setupStripe'))),
      const SizedBox(height: 16),
    ]);
  }

  @override
  Widget build(BuildContext context) => NavigationDraftBoundary(
      isDirty: () => _hasChanges, child: _buildContent(context));

  Widget _buildContent(BuildContext context) {
    final defaultReminders = _formFeature.reminderIsEnabled ?? true;
    final remindersEnabled = _reminderMode == 'inherit'
        ? defaultReminders
        : _reminderMode == 'enabled';

    return Scaffold(
      body: Builder(
        builder: (innerContext) {
          return _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _form == null
                  ? Center(child: Text(FormStrings.formNotFound))
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                key: ObjectKey(_form),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_form!.definition.blueprint == null ||
                                      !FeatureService.isFeatureEnabled(
                                          FeatureConstants.blueprint)) ...[
                                    Text(WaitlistStrings.settings,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _capacityController,
                                      onChanged: (value) {
                                        if (value.isEmpty && !_capacityBlocked)
                                          setState(
                                              () => _waitlistEnabled = false);
                                      },
                                      decoration: InputDecoration(
                                          labelText: WaitlistStrings.capacity,
                                          helperText:
                                              WaitlistStrings.unlimited),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                      validator: (value) {
                                        final n = int.tryParse(value ?? '');
                                        if ((value ?? '').isEmpty)
                                          return _capacityBlocked ||
                                                  _waitlistEnabled
                                              ? WaitlistStrings.activeEntries
                                              : null;
                                        if (n == null || n <= 0)
                                          return WaitlistStrings.positiveNumber;
                                        if (n <
                                            (_form!.definition.capacity
                                                        ?.occupiedPeople ??
                                                    0) +
                                                (_form!.definition.capacity
                                                        ?.offeredPlaces ??
                                                    0))
                                          return WaitlistStrings.activeEntries;
                                        return null;
                                      },
                                    ),
                                    if (_capacityController
                                        .text.isNotEmpty) ...[
                                      SwitchListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(
                                              WaitlistStrings.showRemaining),
                                          value: _showRemaining,
                                          onChanged: (v) => setState(
                                              () => _showRemaining = v)),
                                      SwitchListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(WaitlistStrings.enabled),
                                          subtitle: _capacityBlocked
                                              ? Text(
                                                  WaitlistStrings.activeEntries)
                                              : null,
                                          value: _waitlistEnabled,
                                          onChanged: _capacityBlocked
                                              ? null
                                              : (v) => setState(
                                                  () => _waitlistEnabled = v)),
                                      if (_waitlistEnabled)
                                        TextFormField(
                                          controller: _offerHoursController,
                                          decoration: InputDecoration(
                                              labelText: WaitlistStrings
                                                  .durationHours),
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          validator: (v) => DecimalInput
                                                      .positiveDurationSeconds(
                                                          v,
                                                          secondsPerUnit:
                                                              3600) !=
                                                  null
                                              ? null
                                              : WaitlistStrings.positiveNumber,
                                        ),
                                    ],
                                    if (_form!.definition.capacity
                                        case final c?)
                                      WaitlistCapacitySummary(capacity: c),
                                    const SizedBox(height: 24),
                                  ],
                                  Text(FormStrings.formSettingsTitle,
                                      style: Theme.of(innerContext)
                                          .textTheme
                                          .headlineSmall),
                                  const SizedBox(height: 24),
                                  Text(FormStrings.formPaymentDefaultsHelp),
                                  const SizedBox(height: 16),
                                  DropdownButtonFormField<String>(
                                    value: _reminderMode,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText:
                                          FormStrings.labelEnableReminders,
                                      border: const OutlineInputBorder(),
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                          value: 'inherit',
                                          child: Text(
                                              FormStrings.inheritReminder(
                                                  defaultReminders))),
                                      DropdownMenuItem(
                                          value: 'enabled',
                                          child: Text(FormStrings.remindersOn)),
                                      DropdownMenuItem(
                                          value: 'disabled',
                                          child:
                                              Text(FormStrings.remindersOff)),
                                    ],
                                    onChanged: (value) =>
                                        setState(() => _reminderMode = value!),
                                  ),
                                  if (remindersEnabled) ...[
                                    const SizedBox(height: 24),
                                    TextFormField(
                                      controller: _reminderDaysController,
                                      decoration: InputDecoration(
                                        labelText:
                                            FormStrings.labelReminderInterval,
                                        border: const OutlineInputBorder(),
                                        helperText: FormStrings.inheritDays(
                                            (_formFeature
                                                        .reminderIntervalSeconds ??
                                                    86400) /
                                                86400),
                                        helperMaxLines: 4,
                                      ),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return null;
                                        }
                                        final days =
                                            DecimalInput.tryParse(value);
                                        return days == null ||
                                                !days.isFinite ||
                                                days < 0
                                            ? FormStrings.nonNegativeDays
                                            : null;
                                      },
                                    ),
                                  ],
                                  const SizedBox(height: 24),
                                  TextFormField(
                                    controller: _titleController,
                                    decoration: InputDecoration(
                                      labelText: FormStrings.labelFormTitle,
                                      border: const OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  TextFormField(
                                    controller: _linkController,
                                    decoration: InputDecoration(
                                      labelText: FormStrings.labelFormLink,
                                      border: const OutlineInputBorder(),
                                      errorText: _linkError,
                                      helperText:
                                          FormStrings.publicLinkHistoryHelp,
                                    ),
                                    onChanged: (value) {
                                      _validateLink(value);
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  ValueListenableBuilder<String>(
                                    valueListenable: _linkNotifier,
                                    builder: (context, formLink, child) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12.0),
                                        child: FormPublicLink(
                                            link: formLink,
                                            savedLink: _savedLink),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                  TextFormField(
                                    controller: _deadlineDaysController,
                                    onChanged: (value) => setState(() =>
                                        _deadlineInherited = value.isEmpty),
                                    decoration: InputDecoration(
                                      labelText: FormStrings.labelDeadlineDays,
                                      suffixIcon: IconButton(
                                        tooltip: FormStrings.inheritDays(
                                            (_formFeature
                                                        .deadlineDurationSeconds ??
                                                    604800) /
                                                86400),
                                        icon: const Icon(Icons.restore),
                                        onPressed: () => setState(() {
                                          _deadlineInherited = true;
                                          _deadlineDaysController
                                              .text = ((_formFeature
                                                          .deadlineDurationSeconds ??
                                                      604800) /
                                                  86400)
                                              .round()
                                              .toString();
                                        }),
                                      ),
                                      border: const OutlineInputBorder(),
                                      helperText: FormStrings.inheritDays(
                                          (_formFeature
                                                      .deadlineDurationSeconds ??
                                                  604800) /
                                              86400),
                                      helperMaxLines: 5,
                                    ),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  const Divider(),
                                  const SizedBox(height: 16),
                                  Text(FormStrings.paymentDetailsTitle,
                                      style: Theme.of(innerContext)
                                          .textTheme
                                          .titleLarge),
                                  const SizedBox(height: 24),
                                  _buildPaymentMethods(innerContext),
                                  const SizedBox(height: 16),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: _variableSymbolType,
                                    decoration: InputDecoration(
                                      labelText:
                                          FormStrings.labelVariableSymbol,
                                      border: const OutlineInputBorder(),
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                          value: 'random',
                                          child:
                                              Text(FormStrings.vsTypeRandom)),
                                      DropdownMenuItem(
                                          value: 'sequence',
                                          child:
                                              Text(FormStrings.vsTypeSequence)),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() {
                                          _variableSymbolType = value;
                                        });
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  Visibility(
                                    visible: _variableSymbolType == 'sequence',
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 24.0),
                                      child: TextFormField(
                                        controller: _startingNumberController,
                                        decoration: InputDecoration(
                                          labelText:
                                              FormStrings.labelStartingNumber,
                                          border: const OutlineInputBorder(),
                                          helperText:
                                              FormStrings.helperStartingNumber,
                                          counterText: "",
                                        ),
                                        keyboardType: TextInputType.number,
                                        maxLength: 10,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(10),
                                        ],
                                      ),
                                    ),
                                  ),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: _paymentMessageType,
                                    decoration: InputDecoration(
                                      labelText:
                                          FormStrings.labelPaymentMessage,
                                      border: const OutlineInputBorder(),
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                          value: 'name_surname',
                                          child: Text(
                                              FormStrings.msgTypeNameSurname)),
                                      DropdownMenuItem(
                                          value: 'none',
                                          child: Text(FormStrings.msgTypeNone)),
                                      DropdownMenuItem(
                                          value: 'occasion_title',
                                          child: Text(FormStrings
                                              .msgTypeOccasionTitle)),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() {
                                          _paymentMessageType = value;
                                        });
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                  const Divider(),
                                  const SizedBox(height: 16),
                                  Text(FormStrings.communicationToneTitle,
                                      style: Theme.of(innerContext)
                                          .textTheme
                                          .titleLarge),
                                  const SizedBox(height: 8),
                                  Text(
                                    FormStrings.helperCommunicationTone,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 24),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: _communicationTone,
                                    decoration: InputDecoration(
                                      labelText:
                                          FormStrings.labelCommunicationTone,
                                      border: const OutlineInputBorder(),
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                          value: 'inherit',
                                          child: Text(FormStrings.toneInherit(
                                              _unitTone == 'informal'
                                                  ? FormStrings.toneInformal
                                                  : FormStrings.toneFormal))),
                                      DropdownMenuItem(
                                          value: 'formal',
                                          child: Text(FormStrings.toneFormal)),
                                      DropdownMenuItem(
                                          value: 'informal',
                                          child:
                                              Text(FormStrings.toneInformal)),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() {
                                          _communicationTone = value;
                                        });
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 48),
                                  if (RightsService.canEditOccasion())
                                    Center(
                                      child: Tooltip(
                                        message: (_form?.definition.canDelete ??
                                                true)
                                            ? ""
                                            : FormStrings
                                                .cannotDeleteFormWithResponses,
                                        child: TextButton(
                                          onPressed: (_form
                                                      ?.definition.canDelete ??
                                                  true)
                                              ? () =>
                                                  _confirmDelete(innerContext)
                                              : null,
                                          child: Text(
                                            FormStrings.deleteFormTitle,
                                            style: TextStyle(
                                                color: (_form?.definition
                                                            .canDelete ??
                                                        true)
                                                    ? ThemeConfig.redColor(
                                                        innerContext)
                                                    : Colors.grey),
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 48),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
        },
      ),
      bottomNavigationBar: EditorActionBar(
        hasChanges: !_isLoading && _form != null && _snapshot.differs(_draft),
        enabled: RightsService.canEditOccasion(),
        onDiscard: _cancelEdit,
        onSave: () => _saveChanges(context),
      ),
    );
  }
}

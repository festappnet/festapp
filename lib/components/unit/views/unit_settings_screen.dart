import 'package:festapp_core/communication_tone.dart';

import 'unit_measurement_settings.dart';

import 'package:fstapp/components/forms/email_validation.dart';
import 'package:fstapp/components/stripe_payments/stripe_feature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';

import '../verification/verification_strings.dart';

import 'package:fstapp/widgets/app_dialog.dart';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_strings.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/db_units.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/unit/unit_settings_strings.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/components/stripe_payments/stripe_connection_strings.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/router_service.dart';

class UnitSettingsScreen extends StatefulWidget {
  final UnitModel unit;
  final VoidCallback onUnitUpdated;

  const UnitSettingsScreen({
    super.key,
    required this.unit,
    required this.onUnitUpdated,
  });

  @override
  State<UnitSettingsScreen> createState() => _UnitSettingsScreenState();
}

class _UnitSettingsScreenState extends State<UnitSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _isUpdatingStripeFeature = false;
  bool _isLoading = true;
  bool _canEdit = false;
  late UnitModel _unit;

  late String? _title;
  late TextEditingController _replyToEmailController;
  String? _selectedTimezone;
  String _communicationTone = 'formal';
  bool _measurementEnabled = false;
  bool _measurementConsentBridge = false;
  String _measurementConsentLayout = 'bar';
  final _measurementConsentTitleController = TextEditingController();
  final _measurementConsentTextController = TextEditingController();
  final _measurementPrivacyUrlController = TextEditingController();
  final _measurementTileController = ExpansibleController();
  final _measurementGtmController = TextEditingController();
  final _measurementScriptsController = TextEditingController();
  bool get _organizationMeasurementEnabled =>
      RightsService.occasionLinkModel?.organization?.formMeasurementEnabled ==
      true;

  List<String> _allTimezones = [];
  String _versionInfo = "";

  // Constants for data keys
  static const String dataTimezone = "timezone";
  static const int maxTitleLength = 30;

  bool _canDeleteUnit = true;
  String? _deleteDisabledMessage;

  @override
  void initState() {
    super.initState();
    _unit = widget.unit;
    _loadUnitData();
    _loadVersionInfo();
    RightsService.occasionLinkModelNotifier.addListener(_onRightsChanged);
  }

  @override
  void dispose() {
    RightsService.occasionLinkModelNotifier.removeListener(_onRightsChanged);
    _replyToEmailController.dispose();
    _measurementGtmController.dispose();
    _measurementPrivacyUrlController.dispose();
    _measurementConsentTitleController.dispose();
    _measurementConsentTextController.dispose();
    _measurementTileController.dispose();
    _measurementScriptsController.dispose();
    super.dispose();
  }

  void _onRightsChanged() {
    if (mounted) {
      setState(
        () => _canEdit = RightsService.hasCapability(
          AuthorizationCapabilities.unitSettingsWrite,
        ),
      );
    }
    if (RightsService.currentUnit()?.id == widget.unit.id) {
      _checkDeleteConstraints();
    }
  }

  Future<void> _checkDeleteConstraints() async {
    try {
      // Check deletion limits
      bool hasOccasions = await DbUnits.hasOccasions(widget.unit.id!);
      bool isLastUnit = (RightsService.currentUser()?.units?.length ?? 0) <= 1;

      if (mounted) {
        setState(() {
          if (hasOccasions) {
            _canDeleteUnit = false;
            _deleteDisabledMessage =
                UnitSettingsStrings.cannotDeleteUnitWithOccasions;
          } else if (isLastUnit) {
            _canDeleteUnit = false;
            _deleteDisabledMessage = UnitSettingsStrings.cannotDeleteLastUnit;
          } else {
            _canDeleteUnit = true;
            _deleteDisabledMessage = null;
          }
        });
      }
    } catch (e) {
      AppLogger.error("Error checking delete constraints: $e");
    }
  }

  Future<void> _setStripeFeature(bool enabled) async {
    final unitId = _unit.id;
    if (unitId == null ||
        !StripeFeature.canActivate ||
        RightsService.currentUnit()?.id != unitId)
      return;
    setState(() => _isUpdatingStripeFeature = true);
    try {
      await Supabase.instance.client.rpc(
        'set_stripe_unit_feature',
        params: {'p_unit': unitId, 'p_enabled': enabled},
      );
      await RightsService.refreshAfterAuthorizationChange();
      if (mounted) widget.onUnitUpdated();
    } catch (_) {
      if (mounted)
        ToastHelper.Show(
          context,
          'Nastavení Stripe se nepodařilo uložit.',
          severity: ToastSeverity.NotOk,
        );
    } finally {
      if (mounted) setState(() => _isUpdatingStripeFeature = false);
    }
  }

  Future<void> _loadVersionInfo() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _versionInfo = "${packageInfo.version}+${packageInfo.buildNumber}";
      });
    }
  }

  Future<void> _loadUnitData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final freshUnit = await DbUsers.getCurrentUnit(widget.unit.id!);
      if (freshUnit != null) {
        _unit = freshUnit;
      }

      await _checkDeleteConstraints();
    } catch (e) {
      AppLogger.error("Error loading unit data: $e");
    } finally {
      if (mounted) {
        _initializeFormState();
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  // ... (existing code omitted) ...

  void _initializeFormState() {
    _title = _unit.title;
    _canEdit = RightsService.hasCapability(
      AuthorizationCapabilities.unitSettingsWrite,
    );
    _replyToEmailController = TextEditingController(
      text: _unit.data?[Tb.units.data_reply_to] as String? ?? '',
    );
    _communicationTone = CommunicationTone.resolve(
      _unit.data?[Tb.units.data_communication_tone],
    );

    _measurementEnabled = _unit.data?['measurement_enabled'] == true;
    _measurementConsentBridge = _unit.data?['measurement_consent_bridge'] == true;
    _measurementConsentLayout =
        _unit.data?['measurement_consent_layout'] == 'modal' ? 'modal' : 'bar';
    _measurementConsentTitleController.text =
        _unit.data?['measurement_consent_title'] as String? ?? '';
    _measurementConsentTextController.text =
        _unit.data?['measurement_consent_text'] as String? ?? '';
    _measurementPrivacyUrlController.text =
        _unit.data?['measurement_privacy_url'] as String? ?? '';
    _measurementGtmController.text =
        _unit.data?['measurement_gtm_container'] as String? ?? '';
    _measurementScriptsController.text =
        _unit.data?['measurement_scripts'] as String? ?? '';
    _allTimezones = TimeHelper.getAvailableTimezoneNames();
    _selectedTimezone = _unit.data?[dataTimezone] as String? ?? tz.local.name;

    if (!_allTimezones.contains(_selectedTimezone) &&
        _allTimezones.isNotEmpty) {
      _selectedTimezone = _allTimezones.contains("Europe/Prague")
          ? "Europe/Prague"
          : _allTimezones.first;
    }
  }

  Future<void> _saveSettings() async {
    if (_isSaving ||
        !RightsService.hasCapability(
          AuthorizationCapabilities.unitSettingsWrite,
        )) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      if (_organizationMeasurementEnabled) {
        _measurementTileController.expand();
      }
      return;
    }

    setState(() {
      _isSaving = true;
    });

    _formKey.currentState!.save();

    final pendingUnit = UnitModel(
      id: _unit.id,
      title: _title,
      data: Map<String, dynamic>.from(_unit.data ?? {}),
      aggregateVersion: _unit.aggregateVersion,
    );

    final trimmedEmail = _replyToEmailController.text.trim();
    if (trimmedEmail.isEmpty) {
      pendingUnit.data![Tb.units.data_reply_to] = null;
    } else {
      pendingUnit.data![Tb.units.data_reply_to] = trimmedEmail;
    }

    pendingUnit.data![dataTimezone] = _selectedTimezone;
    pendingUnit.data![Tb.units.data_communication_tone] = _communicationTone;
    if (_organizationMeasurementEnabled) {
      pendingUnit.data!['measurement_enabled'] = _measurementEnabled;
      pendingUnit.data!['measurement_consent_bridge'] = _measurementConsentBridge;
      pendingUnit.data!['measurement_consent_layout'] =
          _measurementConsentLayout;
      // Omission preserves unloaded metadata; explicit null clears an edited field.
      for (final (key, value) in [
        (
          'measurement_consent_title',
          _measurementConsentTitleController.text.trim(),
        ),
        (
          'measurement_consent_text',
          _measurementConsentTextController.text.trim(),
        ),
        (
          'measurement_privacy_url',
          _measurementPrivacyUrlController.text.trim(),
        ),
        ('measurement_gtm_container', _measurementGtmController.text.trim()),
        ('measurement_scripts', _measurementScriptsController.text),
      ]) {
        pendingUnit.data![key] = value.isEmpty ? null : value;
      }
    }

    try {
      await DbUnits.updateUnit(pendingUnit);
      _unit
        ..title = pendingUnit.title
        ..data = pendingUnit.data
        ..aggregateVersion = pendingUnit.aggregateVersion;
      widget.unit
        ..title = _unit.title
        ..data = _unit.data
        ..aggregateVersion = _unit.aggregateVersion;
      final currentUnit = RightsService.currentUnit();
      if (currentUnit?.id == _unit.id) {
        currentUnit!
          ..title = _unit.title
          ..data = _unit.data
          ..aggregateVersion = _unit.aggregateVersion;
      }
      if (!mounted) return;
      ToastHelper.Show(context, "${CommonStrings.saved}: ${_unit.title!}");
      widget.onUnitUpdated();
    } catch (e) {
      ToastHelper.Show(context, e.toString(), severity: ToastSeverity.NotOk);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteUnit() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        onClose: () => Navigator.of(context).pop(false),
        title: Text(UnitSettingsStrings.deleteUnit),
        content: Text(UnitSettingsStrings.deleteUnitConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(CommonStrings.storno),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(CommonStrings.delete),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await DbUnits.deleteUnit(_unit.id!);

      if (mounted) {
        // Filter out the deleted unit from the local list
        var allUnits = RightsService.currentUser()?.units ?? [];
        var remainingUnits = allUnits.where((u) => u.id != _unit.id).toList();

        if (remainingUnits.isNotEmpty) {
          // Switch to the first available unit
          await RouterService.navigateToUnitAdmin(
            context,
            remainingUnits.first,
          );
        } else {
          // No units left, go home
          await RouterService.navigateHome(context);
        }
      }
    } catch (e) {
      String message = e.toString();
      if (message.contains('UNIT_HAS_OCCASIONS')) {
        message = UnitSettingsStrings.cannotDeleteUnitWithOccasions;
      } else if (message.contains('CANNOT_DELETE_LAST_UNIT')) {
        message = UnitSettingsStrings.cannotDeleteLastUnit;
      }
      ToastHelper.Show(context, message, severity: ToastSeverity.NotOk);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: StylesConfig.formMaxWidth,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        TextFormField(
                          initialValue: _title,
                          enabled: _canEdit,
                          maxLength: maxTitleLength,
                          buildCounter:
                              (
                                context, {
                                required currentLength,
                                required isFocused,
                                required maxLength,
                              }) {
                                return isFocused
                                    ? Text(
                                        '$currentLength/$maxLength',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      )
                                    : null;
                              },
                          decoration: InputDecoration(
                            labelText:
                                UnitSettingsStrings.labelOrganizationName,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return OccasionSettingsStrings.titleIsRequired;
                            }
                            return null;
                          },
                          onSaved: (val) {
                            _title = val;
                          },
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _replyToEmailController,
                          enabled: _canEdit,
                          decoration: InputDecoration(
                            labelText: UnitSettingsStrings.labelReplyToEmail,
                            border: const OutlineInputBorder(),
                            helperText:
                                OccasionSettingsStrings.helperReplyToEmail,
                            helperMaxLines: 3,
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) => EmailValidation.validator(
                            checkNullOrEmpty: false,
                            errorText:
                                OccasionSettingsStrings.validationEmailInvalid,
                          )(value?.trim()),
                        ),
                        const SizedBox(height: 24),
                        DropdownButtonFormField<String>(
                          initialValue: _communicationTone,
                          decoration: InputDecoration(
                            labelText: UnitSettingsStrings
                                .labelDefaultCommunicationTone,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
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
                                    setState(() => _communicationTone = value);
                                  }
                                }
                              : null,
                        ),
                        const SizedBox(height: 24),
                        if (_allTimezones.isNotEmpty)
                          Autocomplete<String>(
                            initialValue:
                                _selectedTimezone != null &&
                                    _allTimezones.contains(_selectedTimezone)
                                ? TextEditingValue(text: _selectedTimezone!)
                                : null,
                            optionsBuilder:
                                (TextEditingValue textEditingValue) {
                                  if (textEditingValue.text.isEmpty) {
                                    return _allTimezones.take(50);
                                  }
                                  return _allTimezones.where((String option) {
                                    return option.toLowerCase().contains(
                                      textEditingValue.text.toLowerCase(),
                                    );
                                  });
                                },
                            onSelected: (String selection) {
                              setState(() {
                                _selectedTimezone = selection;
                              });
                            },
                            fieldViewBuilder:
                                (
                                  BuildContext context,
                                  TextEditingController
                                  fieldTextEditingController,
                                  FocusNode fieldFocusNode,
                                  VoidCallback onFieldSubmitted,
                                ) {
                                  return TextFormField(
                                    controller: fieldTextEditingController,
                                    focusNode: fieldFocusNode,
                                    enabled: _canEdit,
                                    decoration: InputDecoration(
                                      labelText: UnitSettingsStrings
                                          .labelDefaultTimezone,
                                      border: const OutlineInputBorder(),
                                      suffixIcon:
                                          fieldTextEditingController
                                                  .text
                                                  .isNotEmpty &&
                                              _canEdit
                                          ? IconButton(
                                              icon: const Icon(Icons.clear),
                                              onPressed: () {
                                                fieldTextEditingController
                                                    .clear();
                                                setState(() {
                                                  _selectedTimezone = null;
                                                });
                                              },
                                            )
                                          : null,
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return OccasionSettingsStrings
                                            .timezoneIsRequired;
                                      }
                                      if (!_allTimezones.contains(value)) {
                                        if (_selectedTimezone != value) {
                                          return OccasionSettingsStrings
                                              .invalidTimezone;
                                        }
                                      }
                                      if (_allTimezones.contains(value) &&
                                          _selectedTimezone != value) {
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              if (mounted) {
                                                setState(() {
                                                  _selectedTimezone = value;
                                                });
                                              }
                                            });
                                      }
                                      return null;
                                    },
                                    onFieldSubmitted: (_) => onFieldSubmitted(),
                                  );
                                },
                            optionsViewBuilder:
                                (
                                  BuildContext context,
                                  AutocompleteOnSelected<String> onSelected,
                                  Iterable<String> options,
                                ) {
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    child: Material(
                                      elevation: 4.0,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxHeight: 300,
                                          maxWidth:
                                              MediaQuery.of(context)
                                                          .size
                                                          .width -
                                                      40 >
                                                  0
                                              ? MediaQuery.of(context)
                                                        .size
                                                        .width -
                                                    40
                                              : 300,
                                        ),
                                        child: ListView.builder(
                                          padding: EdgeInsets.zero,
                                          itemCount: options.length,
                                          shrinkWrap: true,
                                          itemBuilder:
                                              (
                                                BuildContext context,
                                                int index,
                                              ) {
                                                final String option = options
                                                    .elementAt(index);
                                                return InkWell(
                                                  onTap: () {
                                                    onSelected(option);
                                                  },
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          16.0,
                                                        ),
                                                    child: Text(option),
                                                  ),
                                                );
                                              },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12.0),
                            child: Text(
                              OccasionSettingsStrings.timezonesLoading,
                            ),
                          ),
                        const SizedBox(height: 24),
                        if (_canEdit)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ElevatedButton.icon(
                                icon: _isSaving
                                    ? const SizedBox.shrink()
                                    : const Icon(Icons.save, size: 18),
                                label: _isSaving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(CommonStrings.save),
                                onPressed: _isSaving ? null : _saveSettings,
                              ),
                            ],
                          ),
                      ],
                    ],
                  ),
                  if (!_isLoading && _unit.id != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: ListTile(
                        leading: const Icon(Icons.verified_outlined),
                        title: Text(VerificationStrings.text('title')),
                        subtitle: Text(
                          VerificationStrings.text('settingsDescription'),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.router.push(const UnitLegalProfileRoute()),
                      ),
                    ),
                  if (!_isLoading) ...[
                    const SizedBox(height: 24),
                    const SizedBox(height: 24),
                    if (_canEdit)
                      ListTile(
                        leading: const Icon(Icons.account_balance),
                        title: Text(BankAccountStrings.bankAccountsTitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          context.tabsRouter.navigate(
                            const UnitBankAccountsNavigationRoute(),
                          );
                        },
                      ),
                    const SizedBox(height: 48),
                    if (_organizationMeasurementEnabled) ...[
                      UnitMeasurementSettings(
                        enabled: _measurementEnabled,
                        consentBridge: _measurementConsentBridge,
                        onConsentBridgeChanged: (value) =>
                            setState(() => _measurementConsentBridge = value),
                        consentLayout: _measurementConsentLayout,
                        consentTitleController:
                            _measurementConsentTitleController,
                        consentTextController:
                            _measurementConsentTextController,
                        onConsentLayoutChanged: (value) =>
                            setState(() => _measurementConsentLayout = value),
                        canEdit: _canEdit && !_isSaving,
                        privacyUrlController: _measurementPrivacyUrlController,
                        controller: _measurementTileController,
                        gtmController: _measurementGtmController,
                        scriptsController: _measurementScriptsController,
                        onEnabledChanged: (value) =>
                            setState(() => _measurementEnabled = value),
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (StripeFeature.canActivate &&
                        RightsService.currentUnit()?.id == _unit.id)
                      ExpansionTile(
                        title: const Text('Skryté funkce'),
                        children: [
                          SwitchListTile(
                            title: const Text('Platby kartou přes Stripe'),
                            subtitle: const Text(
                              'Zpřístupní nastavení pouze této organizaci. Ostré platby se tím nezapnou.',
                            ),
                            value: StripeFeature.visible,
                            onChanged: _isUpdatingStripeFeature
                                ? null
                                : _setStripeFeature,
                          ),
                        ],
                      ),
                    if (StripeFeature.visible && StripeFeature.canManage)
                      ListTile(
                        leading: const Icon(Icons.credit_card),
                        title: Text(StripeConnectionStrings.title),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.tabsRouter.navigate(
                          const UnitCardPaymentsRoute(),
                        ),
                      ),
                    if (_canEdit)
                      Center(
                        child: Tooltip(
                          message: _deleteDisabledMessage ?? "",
                          child: TextButton(
                            onPressed: _canDeleteUnit ? _deleteUnit : null,
                            child: Text(
                              UnitSettingsStrings.deleteUnit,
                              style: TextStyle(
                                color: _canDeleteUnit
                                    ? ThemeConfig.redColor(context)
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    if (_versionInfo.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Center(
                          child: Text(
                            "Version: $_versionInfo",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

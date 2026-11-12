import '../../payments/payment_policy_settings.dart';

import 'package:festapp_core/communication_tone.dart';

import 'unit_measurement_settings.dart';
import '../unit_measurement_approval.dart';

import 'package:fstapp/services/exception_handler.dart';

import 'package:fstapp/components/forms/email_validation.dart';
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
import 'package:fstapp/components/forms/payment_method_strings.dart';
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
  bool _isLoading = true;
  bool _canEdit = false;
  late UnitModel _unit;

  late String? _title;
  late TextEditingController _replyToEmailController;
  String? _selectedTimezone;
  String _communicationTone = 'formal';
  bool _measurementEnabled = false;
  UnitMeasurementApproval? _measurementApproval;
  bool _isLoadingMeasurementApproval = false;
  bool _measurementApprovalLoadFailed = false;
  bool _isRequestingMeasurement = false;
  bool _measurementConsentBridge = false;
  String _measurementConsentLayout = 'bar';
  final _measurementConsentTitleController = TextEditingController();
  final _measurementConsentTextController = TextEditingController();
  final _restoredConsent = <TextEditingController>{};
  String? _storedConsentTitle;
  String? _storedConsentText;
  String _initialConsentTitle = '';
  String _initialConsentText = '';
  final _measurementPrivacyUrlController = TextEditingController();
  final _measurementWebsitesController = TextEditingController();
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
    _measurementWebsitesController.dispose();
    _measurementGtmController.dispose();
    _measurementPrivacyUrlController.dispose();
    _measurementConsentTitleController.dispose();
    _measurementConsentTextController.dispose();
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
    if (mounted && _organizationMeasurementEnabled) {
      await _loadMeasurementApproval();
    }
  }

  Future<void> _loadMeasurementApproval() async {
    if (_isLoadingMeasurementApproval || _unit.id == null) return;
    setState(() {
      _isLoadingMeasurementApproval = true;
      _measurementApprovalLoadFailed = false;
    });
    try {
      final approval = await ExceptionHandler.guard(
        context,
        futureFunction: () => DbUnits.getMeasurementApproval(_unit.id!),
      );
      if (mounted) {
        setState(() {
          _measurementApproval = approval;
          _measurementApprovalLoadFailed = approval == null;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingMeasurementApproval = false);
    }
  }

  Future<void> _requestMeasurementApproval() async {
    if (!_canEdit ||
        _isSaving ||
        _isRequestingMeasurement ||
        _isLoadingMeasurementApproval ||
        _unit.id == null) {
      return;
    }
    if (_measurementApproval?.canRequest != true ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final sites = UnitMeasurementSettings.parseWebsites(
      _measurementWebsitesController.text,
    );
    final saved = _measurementApproval!.savedOrigins;
    if (sites.length != saved.length || !sites.every(saved.contains)) return;
    setState(() => _isRequestingMeasurement = true);
    try {
      final approval = await ExceptionHandler.guard(
        context,
        futureFunction: () async {
          try {
            return await DbUnits.requestMeasurementApproval(_unit.id!);
          } catch (error) {
            final detail = error.toString();
            final message = detail.contains('measurement_request_no_recipient')
                ? FormStrings.measurementRequestNoRecipient
                : detail.contains('measurement_notification_origin_missing')
                ? FormStrings.measurementNotificationOriginMissing
                : null;
            if (message != null) {
              throw AppError(
                code: 'measurement_request',
                message: message,
                rawJson: '{}',
              );
            }
            rethrow;
          }
        },
      );
      if (mounted && approval != null) {
        setState(() => _measurementApproval = approval);
      }
    } finally {
      if (mounted) setState(() => _isRequestingMeasurement = false);
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
    _measurementConsentBridge =
        _unit.data?['measurement_consent_bridge'] == true;
    _measurementConsentLayout =
        _unit.data?['measurement_consent_layout'] == 'modal' ? 'modal' : 'bar';
    // Unset title/text show the default prefilled; see _consentOverride.
    _storedConsentTitle = _unit.data?['measurement_consent_title'] as String?;
    _storedConsentText = _unit.data?['measurement_consent_text'] as String?;
    _measurementConsentTitleController.text =
        _storedConsentTitle ?? FormStrings.measurementConsentDefaultTitle;
    _measurementConsentTextController.text =
        _storedConsentText ?? FormStrings.measurementConsentDefaultText;
    _initialConsentTitle = _measurementConsentTitleController.text;
    _initialConsentText = _measurementConsentTextController.text;
    _measurementPrivacyUrlController.text =
        _unit.data?['measurement_privacy_url'] as String? ?? '';
    _measurementWebsitesController.text = List<String>.from(
      _unit.data?['measurement_websites'] ?? const [],
    ).join('\n');
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

  /// Untouched fields keep what was stored (null stays null, so visitors keep
  /// the default in their own language, independent of the editor's locale).
  /// An edit back to the default text, e.g. "Obnovit výchozí", stores null.
  String _consentOverride(
    TextEditingController controller,
    String? stored,
    String initial,
    String fallback,
  ) {
    final value = controller.text.trim();
    if (_restoredConsent.contains(controller) && value == fallback.trim()) {
      return '';
    }
    if (value == initial.trim()) return stored?.trim() ?? '';
    return value == fallback.trim() ? '' : value;
  }

  Future<void> _saveSettings() async {
    if (_isSaving ||
        _isRequestingMeasurement ||
        !RightsService.hasCapability(
          AuthorizationCapabilities.unitSettingsWrite,
        )) {
      return;
    }
    final invalidFields = _formKey.currentState?.validateGranularly();
    if (invalidFields == null) return;
    if (invalidFields.isNotEmpty) {
      // Both sections and the nested advanced fields remain registered while
      // collapsed. Reveal every invalid field's ancestors before scrolling.
      final sections = <ExpansibleController>{};
      for (final field in invalidFields) {
        field.context.visitAncestorElements((element) {
          final controller = ExpansibleController.maybeOf(element);
          if (controller != null) sections.add(controller);
          return true;
        });
      }
      for (final section in sections) {
        section.expand();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final field = invalidFields.first;
        if (field.mounted) Scrollable.ensureVisible(field.context);
      });
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
      pendingUnit.data!['measurement_websites'] =
          UnitMeasurementSettings.parseWebsites(
            _measurementWebsitesController.text,
          );
      pendingUnit.data!['measurement_enabled'] = _measurementEnabled;
      pendingUnit.data!['measurement_consent_bridge'] =
          _measurementConsentBridge;
      pendingUnit.data!['measurement_consent_layout'] =
          _measurementConsentLayout;
      // Omission preserves unloaded metadata; explicit null clears an edited field.
      for (final (key, value) in [
        (
          'measurement_consent_title',
          _consentOverride(
            _measurementConsentTitleController,
            _storedConsentTitle,
            _initialConsentTitle,
            FormStrings.measurementConsentDefaultTitle,
          ),
        ),
        (
          'measurement_consent_text',
          _consentOverride(
            _measurementConsentTextController,
            _storedConsentText,
            _initialConsentText,
            FormStrings.measurementConsentDefaultText,
          ),
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
      _storedConsentTitle =
          pendingUnit.data!['measurement_consent_title'] as String?;
      _storedConsentText =
          pendingUnit.data!['measurement_consent_text'] as String?;
      _measurementConsentTitleController.text =
          _storedConsentTitle ?? FormStrings.measurementConsentDefaultTitle;
      _measurementConsentTextController.text =
          _storedConsentText ?? FormStrings.measurementConsentDefaultText;
      _restoredConsent.clear();
      _initialConsentTitle = _measurementConsentTitleController.text;
      _initialConsentText = _measurementConsentTextController.text;
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
      if (mounted && _organizationMeasurementEnabled) {
        await _loadMeasurementApproval();
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.Show(context, e.toString(), severity: ToastSeverity.NotOk);
      }
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
                        if (_organizationMeasurementEnabled) ...[
                          const SizedBox(height: 32),
                          ExpansionTile(
                            key: const PageStorageKey(
                              'unit-measurement-settings',
                            ),
                            maintainState: true,
                            expansionAnimationStyle: AnimationStyle.noAnimation,
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(
                              top: 8,
                              bottom: 16,
                            ),
                            title: Text(FormStrings.measurementTitle),
                            subtitle: Text(
                              _measurementEnabled
                                  ? UnitSettingsStrings
                                        .measurementSummaryEnabled
                                  : UnitSettingsStrings
                                        .measurementSummaryDisabled,
                            ),
                            children: [
                              UnitMeasurementSettings(
                                consentBridge: _measurementConsentBridge,
                                onConsentBridgeChanged: (value) => setState(
                                  () => _measurementConsentBridge = value,
                                ),
                                websitesController:
                                    _measurementWebsitesController,
                                approval: _measurementApproval,
                                loadingApproval: _isLoadingMeasurementApproval,
                                approvalLoadFailed:
                                    _measurementApprovalLoadFailed,
                                onRetryApproval: _loadMeasurementApproval,
                                requestingApproval: _isRequestingMeasurement,
                                onRequestApproval: _requestMeasurementApproval,
                                enabled: _measurementEnabled,
                                consentLayout: _measurementConsentLayout,
                                hasStoredTitle: _storedConsentTitle != null,
                                hasStoredText: _storedConsentText != null,
                                onRestore: (controller) =>
                                    _restoredConsent.add(controller),
                                consentTitleController:
                                    _measurementConsentTitleController,
                                consentTextController:
                                    _measurementConsentTextController,
                                onConsentLayoutChanged: (value) => setState(
                                  () => _measurementConsentLayout = value,
                                ),
                                canEdit:
                                    _canEdit &&
                                    !_isSaving &&
                                    !_isRequestingMeasurement,
                                privacyUrlController:
                                    _measurementPrivacyUrlController,
                                gtmController: _measurementGtmController,
                                scriptsController:
                                    _measurementScriptsController,
                                onEnabledChanged: (value) =>
                                    setState(() => _measurementEnabled = value),
                              ),
                            ],
                          ),
                        ],
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
                                onPressed: _isSaving || _isRequestingMeasurement
                                    ? null
                                    : _saveSettings,
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
                    const SizedBox(height: 16),
                    if (_canEdit &&
                        _unit.id != null &&
                        _unit.organization != null)
                      ExpansionTile(
                        key: const PageStorageKey('unit-payment-settings'),
                        maintainState: true,
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 16),
                        title: Text(PaymentMethodStrings.text('policyTitle')),
                        subtitle: Text(
                          PaymentMethodStrings.text('policyUnitSummary'),
                        ),
                        children: [
                          PaymentPolicySettings(
                            organizationId: _unit.organization!,
                            unitId: _unit.id,
                            showHeading: false,
                            configureMethods: const {'bank', 'stripe'},
                            onConfigure: (method) {
                              if (method == 'bank') {
                                context.tabsRouter.navigate(
                                  const UnitBankAccountsNavigationRoute(),
                                );
                              }
                              if (method == 'stripe') {
                                context.tabsRouter.navigate(
                                  const UnitCardPaymentsRoute(),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),
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

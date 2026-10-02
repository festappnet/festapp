import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/organization/db_organizations.dart';
import 'package:fstapp/components/organization/organization_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/components/organization/organization_admin_guard.dart';
import 'package:fstapp/components/forms/logic/phone_country_codes.dart';
import 'package:select_dialog/select_dialog.dart';

import 'package:fstapp/components/_shared/app_panel_helper.dart';
import 'package:fstapp/components/_shared/admin_strings.dart';

@RoutePage()
class OrganizationEditPage extends StatefulWidget {
  static const String ROUTE = "organizationEdit";

  final int id;

  const OrganizationEditPage({super.key, @PathParam('id') required this.id});

  @override
  State<OrganizationEditPage> createState() => _OrganizationEditPageState();
}

class _OrganizationEditPageState extends State<OrganizationEditPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;
  OrganizationModel? _organization;
  int? _orgId;

  // Controllers
  final _titleController = TextEditingController();
  final _appNameController = TextEditingController();
  final _defaultUrlController = TextEditingController();
  final _defaultLanguageController = TextEditingController();
  final _defaultUnitController = TextEditingController();
  final _representativeOccasionController = TextEditingController();
  final _oneSignalAppIdController = TextEditingController();
  final _phonePrefixesController = TextEditingController();

  // Flags
  bool _isRegistrationEnabled = false;
  bool _isGoogleLoginEnabled = false;
  bool _isUnitCreationEnabled = false;
  bool _isAppSupported = false;

  // Platforms
  List<PlatformModel> _platforms = [];

  @override
  void initState() {
    super.initState();
  }

  Future<void> _loadData(int orgId) async {
    _orgId = orgId;
    try {
      final org = await DbOrganizations.getOrganizationAdmin(orgId);
      if (org != null) {
        _organization = org;
        _titleController.text = org.title ?? '';
        _appNameController.text = org.appName ?? '';
        _defaultUrlController.text = org.defaultUrl ?? '';
        _defaultLanguageController.text = org.defaultLanguage ?? '';
        _defaultUnitController.text = org.defaultUnit?.toString() ?? '';
        _representativeOccasionController.text =
            org.representativeOccasion?.toString() ?? '';
        _oneSignalAppIdController.text = org.oneSignalAppId ?? '';
        _phonePrefixesController.text = org.phonePrefixes?.join(', ') ?? '';

        _isRegistrationEnabled = org.isRegistrationEnabled ?? false;
        _isGoogleLoginEnabled = org.isGoogleLoginEnabled ?? false;
        _isUnitCreationEnabled = org.isUnitCreationEnabled ?? false;
        _isAppSupported = org.isAppSupported ?? false;

        _platforms = org.platforms?.toList() ?? [];
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.Show(context, "Failed to load organization data.",
            severity: ToastSeverity.NotOk);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_orgId == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final updatedOrg = OrganizationModel(
        title: _titleController.text,
        appName: _appNameController.text,
        defaultUrl: _defaultUrlController.text,
        defaultLanguage: _defaultLanguageController.text,
        oneSignalAppId: _oneSignalAppIdController.text,
        defaultUnit: int.tryParse(_defaultUnitController.text),
        representativeOccasion:
            int.tryParse(_representativeOccasionController.text),
        isRegistrationEnabled: _isRegistrationEnabled,
        isGoogleLoginEnabled: _isGoogleLoginEnabled,
        isUnitCreationEnabled: _isUnitCreationEnabled,
        isAppSupported: _isAppSupported,
        platforms: _platforms,
        phonePrefixes: _phonePrefixesController.text
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList(),
      );

      await DbOrganizations.updateOrganization(_orgId!, updatedOrg);
      if (mounted) {
        ToastHelper.Show(context, "Organization saved.");
      }

      // Update local state manually to reflect changes immediately
      RightsService.updateOrganizationLocally(updatedOrg);
    } catch (e) {
      if (mounted) {
        ToastHelper.Show(context, "Error saving: $e",
            severity: ToastSeverity.NotOk);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OrganizationAdminGuard(
      targetOrganizationId: widget.id,
      builder: (context, orgId) {
        if (_isLoading && _organization == null && _orgId != orgId) {
          _loadData(orgId);
        }

        return Scaffold(
          appBar: AppPanelHelper.buildAdaptiveAdminAppBar(context),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: StylesConfig.formMaxWidth),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Organization Settings",
                                style:
                                    Theme.of(context).textTheme.headlineMedium),
                            const SizedBox(height: 24),
                            _buildTextField(_titleController, "Title",
                                required: true),
                            _buildTextField(
                                _appNameController, "App Name (APP_NAME)",
                                helper: "Brand identifier"),
                            _buildTextField(_defaultUrlController,
                                "Default URL (DEFAULT_URL)"),
                            _buildTextField(_defaultLanguageController,
                                "Default Language (DEFAULT_LANGUAGE)",
                                helper: "e.g. cs, en"),
                            _buildPrefixesSelector(context),
                            const SizedBox(height: 16),
                            Text("IDs & References",
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                  child: _buildTextField(
                                      _defaultUnitController, "Default Unit ID",
                                      isNumber: true)),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: _buildTextField(
                                      _representativeOccasionController,
                                      "Rep. Occasion ID",
                                      isNumber: true)),
                            ]),
                            const SizedBox(height: 16),
                            Text("OneSignal Configuration",
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            _buildTextField(
                                _oneSignalAppIdController, "OneSignal App ID"),
                            Text(
                              AdministrationStrings
                                  .oneSignalSecretManagedServerSide,
                            ),
                            const SizedBox(height: 16),
                            Text("Feature Flags",
                                style: Theme.of(context).textTheme.titleMedium),
                            SwitchListTile(
                              title: const Text(
                                  "App Supported (IS_APP_SUPPORTED)"),
                              value: _isAppSupported,
                              onChanged: (val) =>
                                  setState(() => _isAppSupported = val),
                            ),
                            SwitchListTile(
                              title: const Text(
                                  "Registration Enabled (IS_REGISTRATION_ENABLED)"),
                              value: _isRegistrationEnabled,
                              onChanged: (val) =>
                                  setState(() => _isRegistrationEnabled = val),
                            ),
                            SwitchListTile(
                              title: Text(
                                  AdministrationStrings.googleLoginEnabled),
                              subtitle: Text(
                                  AdministrationStrings.googleLoginDescription),
                              value: _isGoogleLoginEnabled,
                              onChanged: (val) =>
                                  setState(() => _isGoogleLoginEnabled = val),
                            ),
                            SwitchListTile(
                              title: const Text(
                                  "Manual Unit Creation (IS_UNIT_CREATION_ENABLED)"),
                              value: _isUnitCreationEnabled,
                              onChanged: (val) =>
                                  setState(() => _isUnitCreationEnabled = val),
                            ),
                            const SizedBox(height: 24),
                            Text("Platforms",
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 8),
                            _buildPlatformsEditor(),
                            const SizedBox(height: 32),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ElevatedButton(
                                  onPressed: _isSaving ? null : _save,
                                  child: _isSaving
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Text("Save Changes"),
                                ),
                              ],
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildTextField(TextEditingController controller, String label,
      {bool required = false, String? helper, bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          helperText: helper,
        ),
        validator: required
            ? (val) =>
                (val == null || val.isEmpty) ? "$label is required" : null
            : null,
      ),
    );
  }

  Widget _buildPlatformsEditor() {
    return Column(
      children: [
        ..._platforms.asMap().entries.map((entry) {
          final index = entry.key;
          final platform = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: platform.platform,
                          decoration: const InputDecoration(
                              labelText: "Platform (e.g. web, ios, droid)"),
                          onChanged: (val) => platform.platform = val,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            _platforms.removeAt(index);
                          });
                        },
                      ),
                    ],
                  ),
                  TextFormField(
                    initialValue: platform.link,
                    decoration: const InputDecoration(labelText: "Link"),
                    onChanged: (val) => platform.link = val,
                  ),
                  TextFormField(
                    initialValue: platform.prompt,
                    decoration:
                        const InputDecoration(labelText: "Prompt / Version"),
                    onChanged: (val) => platform.prompt = val,
                  ),
                ],
              ),
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _platforms
                  .add(PlatformModel(platform: "web", link: "", prompt: ""));
            });
          },
          icon: const Icon(Icons.add),
          label: const Text("Add Platform"),
        ),
      ],
    );
  }

  Widget _buildPrefixesSelector(BuildContext context) {
    // Current prefixes from controller to list
    List<String> currentPrefixes = _phonePrefixesController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Phone Prefixes (PHONE_PREFIXES)",
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              // Prepare items for SelectDialog
              // Each item is the formatted string from PhoneCountryCodes.getAll()
              // e.g. "CZ +420"
              SelectDialog.showModal<String>(
                context,
                label: "Select Countries",
                multipleSelectedValues: currentPrefixes.map((p) {
                  // Reconstruct the label for the pre-selection
                  // p is just the prefix e.g. "+420"
                  // We need to find the matching entry in PhoneCountryCodes.getAll()
                  // or just construct it if we knew the ISO.
                  // Simpler: Just rely on string matching if getAll() returns "ISO +Prefix"
                  // Actually, getAll() returns "ISO +Prefix".
                  // So we need to map current prefixes to these full strings.
                  final iso = PhoneCountryCodes.getIso(p);
                  if (iso != null) {
                    return "$iso $p";
                  }
                  return p; // Fallback? But SelectDialog matches by value.
                }).toList(),
                items: PhoneCountryCodes.getAll(),
                onMultipleItemsChange: (List<String> selected) {
                  setState(() {
                    // Extract just the prefixes from the selection (e.g. "CZ +420" -> "+420")
                    final prefixes = selected.map((s) {
                      final parts = s.split(' ');
                      return parts.last; // Assuming valid format "ISO +Prefix"
                    }).toList();
                    _phonePrefixesController.text = prefixes.join(', ');
                  });
                },
                searchBoxDecoration: const InputDecoration(
                  hintText: "Search country or code",
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: currentPrefixes.isEmpty
                        ? const Text("Select prefixes...",
                            style: TextStyle(color: Colors.grey))
                        : Wrap(
                            spacing: 8.0,
                            runSpacing: 4.0,
                            children: currentPrefixes.map((p) {
                              final iso = PhoneCountryCodes.getIso(p);
                              return Chip(
                                label: Text(iso != null ? "$iso $p" : p),
                                onDeleted: () {
                                  setState(() {
                                    currentPrefixes.remove(p);
                                    _phonePrefixesController.text =
                                        currentPrefixes.join(', ');
                                  });
                                },
                              );
                            }).toList(),
                          ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text("Select supported phone prefixes for this organization.",
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

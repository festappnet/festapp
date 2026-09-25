import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/html/html_editor_page.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/components/images/image_compression_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/help_widget.dart';
import 'package:fstapp/components/images/image_area.dart';
import 'package:fstapp/components/unit/views/occasion_card.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';
import 'package:fstapp/components/images/db_images.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:timezone/timezone.dart' as tz;

import '../_shared/common_strings.dart';
import 'occasion_advanced_settings.dart';
import 'occasion_features_section.dart';
import 'occasion_save_state.dart';
import 'occasion_settings_strings.dart';

class OccasionSettingsTab extends StatefulWidget {
  const OccasionSettingsTab({super.key});

  @override
  _OccasionSettingsTabState createState() => _OccasionSettingsTabState();
}

class _OccasionSettingsTabState extends State<OccasionSettingsTab> {
  final _formKey = GlobalKey<FormState>();

  // Data
  OccasionModel? occasion;
  String? occasionLink;
  bool _isLoading = true;
  bool _isSaving = false;

  // Form fields state
  late String? _title;
  late String? _linkValue;
  DateTime? _from;
  DateTime? _to;
  late TextEditingController _linkController;
  late TextEditingController _replyToEmailController;
  String? _description;
  bool _isOpen = true;
  bool _isHidden = false;
  bool _isPromoted = false;
  String? _selectedTimezone;
  List<String> _allTimezones = [];
  bool _advancedSettingsExpanded = false;

  @override
  void initState() {
    super.initState();
    _linkController = TextEditingController();
    _replyToEmailController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (occasionLink == null && context.routeData.params.isNotEmpty) {
      occasionLink =
          context.routeData.params.getString(AppRouter.linkFormatted);
      _loadData();
    }
  }

  @override
  void dispose() {
    _linkController.dispose();
    _replyToEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (occasionLink == null) return;
    setState(() {
      _isLoading = true;
    });

    final fetchedOccasion = await DbOccasions.getOccasionByLink(occasionLink!);

    if (mounted) {
      setState(() {
        occasion = fetchedOccasion;
        _initializeFormState();
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _initializeFormState() {
    if (occasion == null) return;

    _title = occasion!.title;
    _linkValue = occasion!.link;
    _linkController.text = _linkValue ?? "";
    _from = occasion!.startTime;
    _to = occasion!.endTime;
    _description = occasion!.description ?? "";
    _isOpen = occasion!.isOpen;
    _isHidden = occasion!.isHidden;
    _isPromoted = occasion!.isPromoted;

    // Initialize reply-to email
    _replyToEmailController.text =
        occasion!.data?[Tb.occasions.data_reply_to] as String? ?? '';

    // Initialize timezone
    _allTimezones = TimeHelper.getAvailableTimezoneNames();
    _selectedTimezone =
        occasion!.data?[Tb.occasions.data_timezone] as String? ?? tz.local.name;

    if (!_allTimezones.contains(_selectedTimezone) &&
        _allTimezones.isNotEmpty) {
      _selectedTimezone = _allTimezones.contains("Europe/Prague")
          ? "Europe/Prague"
          : _allTimezones.first;
    }

    final defaultFeatures = FeatureService.getDefaultFeatures();
    for (var defaultFeature in defaultFeatures) {
      bool exists =
          occasion!.features.any((f) => f.code == defaultFeature.code);
      if (!exists) {
        occasion!.features.add(defaultFeature);
      }
    }

    occasion!.features.sort((a, b) {
      final aIndex = defaultFeatures
          .indexWhere((defaultFeature) => defaultFeature.code == a.code);
      final bIndex = defaultFeatures
          .indexWhere((defaultFeature) => defaultFeature.code == b.code);
      return aIndex.compareTo(bIndex);
    });
  }

  Future<void> _saveSettings() async {
    // 1. Validate the form. If it's not valid, do nothing.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    try {
      await runOccasionSaveAction(
        setSaving: (isSaving) {
          if (mounted) {
            setState(() {
              _isSaving = isSaving;
            });
          }
        },
        action: () async {
          // 3. Save the form fields to update the local state variables.
          _formKey.currentState!.save();

          // 4. Update the occasion model with the new values from the form.
          occasion!.title = _title;
          occasion!.link = _linkValue;
          occasion!.startTime = _from;
          occasion!.endTime = _to;
          occasion!.description = _description;
          occasion!.isOpen = _isOpen;
          occasion!.isHidden = _isHidden;
          occasion!.isPromoted = _isPromoted;

          final imageUrl = occasion!.data?[Tb.occasions.data_image];
          final bool hasImage = (imageUrl as String?)?.isNotEmpty ?? false;
          if (_isPromoted && !hasImage) {
            occasion!.isPromoted = false;
          }

          occasion!.data ??= {};

          // Save Reply-To Email
          final trimmedEmail = _replyToEmailController.text.trim();
          if (trimmedEmail.isEmpty) {
            occasion!.data!.remove(Tb.occasions.data_reply_to);
          } else {
            occasion!.data![Tb.occasions.data_reply_to] = trimmedEmail;
          }

          // Save Timezone
          occasion!.data![Tb.occasions.data_timezone] = _selectedTimezone;

          // 5. Persist the changes to the database.
          await DbOccasions.updateOccasion(occasion!);

          // 6. Check if the component is still mounted and the new link is valid.
          if (mounted && occasion!.link != null) {
            // Show a success message.
            ToastHelper.Show(
                context, "${CommonStrings.saved}: ${occasion!.title!}");

            // 7. Trigger the full page refresh.
            // This router method handles updating RightsService with the new link
            // and then navigates to the correct administration page (AdminPage or
            // ReservationsPage). This is crucial, especially if the event link
            // itself has been changed.
            await RouterService.navigateToOccasionAdministration(
              context,
              occasion: occasion!,
            );
          }
        },
      );
    } catch (error) {
      if (mounted) {
        ToastHelper.Show(context, error.toString());
      }
    }
  }

  Future<void> _deleteOccasion() async {
    final deletedOccasion = occasion!;
    final unitId = deletedOccasion.unit;
    if (unitId == null) {
      ToastHelper.Show(context, CommonStrings.unexpectedError);
      return;
    }
    try {
      await DbOccasions.deleteOccasion(deletedOccasion.id!);
    } catch (e) {
      if (mounted) ToastHelper.Show(context, e.toString());
      return;
    }
    if (!mounted) return;
    ToastHelper.Show(
        context, "${CommonStrings.deleted}: ${deletedOccasion.title!}");
    try {
      await RouterService.replaceWithUnitAdmin(context, unitId);
    } catch (e) {
      if (mounted) ToastHelper.Show(context, e.toString());
    }
  }

  Future<void> _confirmDelete() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        insetPadding: const EdgeInsets.all(16.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        title: Text(OccasionSettingsStrings.deleteEvent),
        content: Text(OccasionSettingsStrings.deleteEventConfirmation),
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
    if (confirm == true) {
      await _deleteOccasion();
    }
  }

  Future<void> _removeImage() async {
    final imageUrl = occasion!.data?[Tb.occasions.data_image];
    if (imageUrl != null) {
      final confirmation = await DialogHelper.showConfirmationDialog(
        context,
        OccasionSettingsStrings.confirmRemoval,
        OccasionSettingsStrings.deleteImageConfirmation,
      );
      if (confirmation == true) {
        try {
          await DbImages.removeImage(imageUrl);
          setState(() {
            occasion!.data ??= {};
            occasion!.data![Tb.occasions.data_image] = null;

            // <-- MODIFIED (Added) -->
            // If the image is removed, it can no longer be promoted.
            if (_isPromoted) {
              _isPromoted = false;
            }
            // <-- END MODIFICATION -->
          });
          ToastHelper.Show(
              context, OccasionSettingsStrings.imageRemovedSuccess);
        } catch (e) {
          ToastHelper.Show(context, OccasionSettingsStrings.imageRemovedFail);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final bool isEditingEnabled = RightsService.isUnitEditor();
    final imageUrl = occasion!.data?[Tb.occasions.data_image];

    // <-- MODIFIED (Added) -->
    // Check if a valid image URL exists.
    final bool hasImage = (imageUrl as String?)?.isNotEmpty ?? false;
    // Determine if the promotion switch can be changed.
    // It can be changed if:
    // 1. It's already promoted (to allow turning it OFF).
    // 2. It's not promoted, but it HAS an image (to allow turning it ON).
    final bool canChangePromotion = _isPromoted || hasImage;
    // <-- END MODIFICATION -->

    final bool hasOrders = occasion?.hasOrders ?? false;
    final bool canDelete = !hasOrders;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    initialValue: _title,
                    enabled: isEditingEnabled,
                    decoration: InputDecoration(
                      labelText: OccasionSettingsStrings.title,
                    ),
                    validator: FormBuilderValidators.compose([
                      FormBuilderValidators.required(
                          errorText: OccasionSettingsStrings.titleIsRequired),
                    ]),
                    onSaved: (val) {
                      _title = val;
                    },
                  ),
                  const SizedBox(height: 16),
                  TimeDateRangePicker(
                    start: _from,
                    end: _to,
                    enabled: isEditingEnabled,
                    onStartChanged: (dateTime) {
                      setState(() {
                        _from = dateTime;
                      });
                    },
                    onEndChanged: (dateTime) {
                      setState(() {
                        _to = dateTime;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(OccasionSettingsStrings.introImage),
                  const SizedBox(height: 8),
                  ImageArea(
                    enabled: isEditingEnabled,
                    hint: "(${OccasionSettingsStrings.imageRatioHint(
                      OccasionCard.kCardWidth.toString(),
                      OccasionCard.kCardHeight.toString(),
                    )})",
                    imageUrl: imageUrl,
                    onFileSelected: (file) async {
                      Uint8List imageData = await file.readAsBytes();
                      try {
                        var compressedImageData =
                            await ImageCompressionHelper.compress(
                                imageData, 900);
                        final publicUrl = await DbImages.uploadImage(
                            compressedImageData, occasion!.id, null);
                        setState(() {
                          occasion!.data ??= {};
                          occasion!.data![Tb.occasions.data_image] = publicUrl;
                        });
                        ToastHelper.Show(context,
                            OccasionSettingsStrings.fileUploadedSuccess);
                      } catch (e) {
                        ToastHelper.Show(context,
                            OccasionSettingsStrings.failedToUploadImage);
                      }
                      return null;
                    },
                    onRemove: _removeImage,
                  ),
                  const SizedBox(height: 16),
                  Text(OccasionSettingsStrings.description),
                  const SizedBox(height: 8),
                  ClipRect(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white, Colors.transparent],
                          stops: const [0.9, 1.0],
                        ).createShader(bounds),
                        blendMode: BlendMode.dstIn,
                        child: HtmlView(
                          html: _description ?? "",
                          isSelectable: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: ElevatedButton(
                      onPressed: isEditingEnabled
                          ? () async {
                              RouterService.navigatePageInfo(
                                context,
                                HtmlEditorRoute(content: {
                                  HtmlEditorPage.parContent: _description
                                }, occasionId: occasion!.id),
                              ).then((value) {
                                if (value != null) {
                                  setState(() {
                                    _description = value as String;
                                  });
                                }
                              });
                            }
                          : null,
                      child: Text(OccasionSettingsStrings.editContent),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (AppConfig.isAppSupported)
                    SwitchListTile(
                      title: Row(
                        children: [
                          Expanded(child: Text(OccasionSettingsStrings.public)),
                          HelpWidget(
                              title: OccasionSettingsStrings.public,
                              content: OccasionSettingsStrings.publicHelp)
                        ],
                      ),
                      value: _isOpen,
                      onChanged: isEditingEnabled
                          ? (value) {
                              setState(() {
                                _isOpen = value;
                              });
                            }
                          : null,
                    ),
                  if (AppConfig.isAppSupported) const SizedBox(height: 16),
                  SwitchListTile(
                    title: Row(
                      children: [
                        Expanded(child: Text(OccasionSettingsStrings.hide)),
                        HelpWidget(
                          title: OccasionSettingsStrings.hide,
                          content: OccasionSettingsStrings.hideHelp,
                        ),
                      ],
                    ),
                    value: _isHidden,
                    onChanged: isEditingEnabled
                        ? (value) {
                            setState(() {
                              _isHidden = value;
                            });
                          }
                        : null,
                  ),
                  const SizedBox(height: 16),

                  SwitchListTile(
                    title: Row(
                      children: [
                        Expanded(child: Text(OccasionSettingsStrings.promoted)),
                        HelpWidget(
                          title: OccasionSettingsStrings.promoted,
                          content: OccasionSettingsStrings.promotedHelp,
                        ),
                      ],
                    ),
                    value: _isPromoted,
                    // <-- MODIFIED (Updated onChanged logic) -->
                    // Only allow changing the switch if:
                    // 1. Editing is enabled AND
                    // 2. canChangePromotion is true (meaning it's already ON, or it's OFF but has an image)
                    onChanged: isEditingEnabled && canChangePromotion
                        ? (value) {
                            setState(() {
                              _isPromoted = value;
                            });
                          }
                        : null,
                    // <-- END MODIFICATION -->
                  ),

                  const SizedBox(height: 16),
                  OccasionAdvancedSettings(
                    linkController: _linkController,
                    replyToEmailController: _replyToEmailController,
                    selectedTimezone: _selectedTimezone,
                    allTimezones: _allTimezones,
                    isEditingEnabled: isEditingEnabled,
                    initiallyExpanded: _advancedSettingsExpanded,
                    onExpansionChanged: (expanded) {
                      setState(() => _advancedSettingsExpanded = expanded);
                    },
                    onTimezoneSelected: (selection) {
                      setState(() {
                        _selectedTimezone =
                            selection.isEmpty ? null : selection;
                      });
                    },
                    onLinkChanged: (fixed) {
                      setState(() {
                        _linkValue = fixed;
                      });
                    },
                    onLinkSaved: (val) {
                      _linkValue = val;
                    },
                  ),
                  const SizedBox(height: 24),
                  OccasionFeaturesSection(
                    features: occasion!.features,
                    isEditingEnabled: isEditingEnabled,
                    occasionId: occasion!.id!,
                  ),
                  const SizedBox(height: 24),
                  if (RightsService.isUnitManager())
                    Center(
                      child: Tooltip(
                        message: hasOrders
                            ? OccasionSettingsStrings.cannotDeleteWithOrders
                            : "",
                        child: TextButton(
                          onPressed: isEditingEnabled
                              ? () {
                                  if (hasOrders) {
                                    ToastHelper.Show(
                                        context,
                                        OccasionSettingsStrings
                                            .cannotDeleteWithOrders,
                                        severity: ToastSeverity.NotOk);
                                    return;
                                  }
                                  _confirmDelete();
                                }
                              : null,
                          child: Text(
                            OccasionSettingsStrings.deleteEvent,
                            style: TextStyle(
                                color: isEditingEnabled
                                    ? (canDelete
                                        ? ThemeConfig.redColor(context)
                                        : Colors.grey)
                                    : Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 80), // Padding for bottom nav bar
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: Theme.of(context).appBarTheme.backgroundColor,
        padding: const EdgeInsets.all(10),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isSaving || !isEditingEnabled ? null : _loadData,
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
                    : Text(CommonStrings.save),
                onPressed:
                    _isSaving || !isEditingEnabled ? null : _saveSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

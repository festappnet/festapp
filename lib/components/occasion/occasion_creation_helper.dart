import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_strings.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_draft.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_page.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/admin_strings.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/forms/views/form_public_link.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/mouse_detector.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';

class OccasionCreationHelper {
  static Future<OccasionModel?> createNewOccasion(BuildContext context,
      UnitModel unit, List<OccasionModel> existingOccasions,
      {OccasionModel? source, String? copyLocale}) async {
    final intentLocale = copyLocale ?? context.locale.languageCode;
    if (AppConfig.occasionSetupEnabled) {
      await _openSetup(context, unit, {
        if (source != null) ...{
          'sourceId': source.id,
          'sourceUnitId': source.unit,
          'sourceSelectionPending': true,
          'copy_locale': intentLocale,
          'copy_title_edited': false,
        }
      });
      return null;
    }
    final formKey = GlobalKey<FormState>();
    String? title = AdministrationStrings.myFestival;
    String? link = '';
    final now = DateTime.now();
    final seed = now.add(const Duration(days: 30));
    DateTime? startDate = DateTime(seed.year, seed.month, seed.day, seed.hour)
        .add(Duration(
            minutes: ((seed.minute * 60 +
                            seed.second +
                            (seed.microsecond + seed.millisecond > 0 ? 1 : 0)) /
                        1800)
                    .ceil() *
                30));
    DateTime? endDate = startDate
        .add(Duration(days: 3))
        .copyWith(minute: 0, second: 0, millisecond: 0, microsecond: 0);
    String? linkError;
    String? rejectedLink;
    bool isFormValid = true;
    bool isSaving = false;
    String? saveError;

    final TextEditingController titleController =
        TextEditingController(text: title);
    final TextEditingController linkController =
        TextEditingController(text: link);

    ValueNotifier<String> linkNotifier = ValueNotifier<String>(link);

    void validateForm() {
      linkError = link == rejectedLink
          ? FormStrings.validationLinkInUse
          : _validateLink(link ?? "");
      isFormValid = title != null &&
          title!.trim().isNotEmpty &&
          linkError == null &&
          startDate != null &&
          endDate != null &&
          !endDate!.isBefore(startDate!);
    }

    var useSetup = false;
    ModalRoute<dynamic>? dialogRoute;
    final occasion = await showDialog<OccasionModel?>(
      context: context,
      builder: (BuildContext context) {
        dialogRoute = ModalRoute.of(context);
        return MouseDetector(
          builder: (context, mouseIsConnected) {
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                void handleTitleChange(String value) {
                  setState(() {
                    title = value;
                    saveError = null;
                    validateForm();
                  });
                }

                void handleLinkChange(String value) {
                  setState(() {
                    link = value;
                    saveError = null;
                    validateForm();
                    linkNotifier.value = link ?? '';
                  });
                }

                return PopScope(
                  canPop: !isSaving,
                  child: AppAlertDialog(
                    dismissible: !isSaving,
                    title: Text(AdministrationStrings.addNewEventTitle),
                    content: Form(
                      key: formKey,
                      child: AbsorbPointer(
                        absorbing: isSaving,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (saveError != null)
                              Text(saveError!,
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error)),
                            // Title field with validation
                            TextFormField(
                              controller: titleController,
                              decoration: InputDecoration(
                                labelText: AdministrationStrings.titleLabel,
                                labelStyle: TextStyle(
                                  color:
                                      (title == null || title!.trim().isEmpty)
                                          ? ThemeConfig.redColor(context)
                                          : null,
                                ),
                              ),
                              onChanged: handleTitleChange,
                            ),
                            // Event URLs only apply to tenants with the app.
                            if (AppConfig.isAppSupported)
                              TextFormField(
                                controller: linkController,
                                decoration: InputDecoration(
                                  labelText: AdministrationStrings.linkLabel,
                                  labelStyle: TextStyle(
                                    color: linkError != null
                                        ? ThemeConfig.redColor(context)
                                        : null,
                                  ),
                                  errorText: linkError,
                                ),
                                onChanged: handleLinkChange,
                              ),
                            const SizedBox(height: 16),
                            TimeDateRangePicker(
                              start: startDate,
                              end: endDate,
                              onStartChanged: (pickedStart) {
                                setState(() {
                                  startDate = pickedStart;
                                  if (pickedStart != null &&
                                      endDate != null &&
                                      pickedStart.isAfter(endDate!)) {
                                    endDate = DateTime(
                                      pickedStart.year,
                                      pickedStart.month,
                                      pickedStart.day,
                                      endDate!.hour,
                                      endDate!.minute,
                                    );
                                  }
                                  validateForm();
                                });
                              },
                              onEndChanged: (pickedEnd) {
                                setState(() {
                                  endDate = pickedEnd;
                                  if (pickedEnd != null &&
                                      startDate != null &&
                                      pickedEnd.isBefore(startDate!)) {
                                    startDate = DateTime(
                                      pickedEnd.year,
                                      pickedEnd.month,
                                      pickedEnd.day,
                                      startDate!.hour,
                                      startDate!.minute,
                                    );
                                  }
                                  validateForm();
                                });
                              },
                              minDate: DateTime(2000),
                              maxDate: DateTime(2101),
                            ),
                            const SizedBox(height: 16),
                            if (AppConfig.isAppSupported)
                              ValueListenableBuilder<String>(
                                valueListenable: linkNotifier,
                                builder: (context, draftLink, child) {
                                  return PublicLink(
                                      link: draftLink, isForm: false);
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      PopupMenuButton<String>(
                        tooltip: CommonStrings.moreOptions,
                        icon: const Icon(Icons.more_horiz),
                        enabled: !isSaving,
                        onSelected: (_) {
                          useSetup = true;
                          Navigator.of(context).pop();
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'setup',
                            child: Text(OccasionSetupStrings.createStepByStep),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: isSaving
                            ? null
                            : () {
                                Navigator.of(context).pop(null);
                              },
                        child: Text(AdministrationStrings.cancelButton),
                      ),
                      ElevatedButton(
                        onPressed: isFormValid && !isSaving
                            ? () async {
                                if (formKey.currentState!.validate()) {
                                  final startDateTime = startDate!;
                                  final endDateTime = endDate!;

                                  OccasionModel newOccasion = OccasionModel(
                                    title: title,
                                    startTime: startDateTime,
                                    endTime: endDateTime,
                                    link: link,
                                    isOpen: true,
                                    isHidden: false,
                                    isPromoted: false,
                                    unit: unit.id,
                                    organization: AppConfig.organization,
                                    data: {
                                      Tb.occasions.data_timezone: unit.data?[
                                              Tb.occasions.data_timezone] ??
                                          TimeHelper.getSystemTimezoneName()
                                    },
                                  );

                                  setState(() {
                                    isSaving = true;
                                    saveError = null;
                                  });
                                  try {
                                    await DbOccasions.updateOccasion(
                                        newOccasion);
                                    if (context.mounted) {
                                      Navigator.of(context).pop(newOccasion);
                                    }
                                  } catch (error) {
                                    if (!context.mounted) return;
                                    setState(() {
                                      if (error is PostgrestException &&
                                          error.code == '23505' &&
                                          error.message ==
                                              'Public link is already in use') {
                                        rejectedLink = link;
                                        linkError =
                                            FormStrings.validationLinkInUse;
                                        isFormValid = false;
                                      } else {
                                        saveError =
                                            ExceptionHandler.toFriendlyMessage(
                                                error);
                                      }
                                    });
                                  } finally {
                                    if (context.mounted) {
                                      setState(() => isSaving = false);
                                    }
                                  }
                                }
                              }
                            : null,
                        child: Text(AdministrationStrings.createButton),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
    // The popped route still renders its exit transition. Release controllers
    // only after its widgets have left the tree.
    await dialogRoute?.completed;
    titleController.dispose();
    linkController.dispose();
    linkNotifier.dispose();
    if (useSetup && context.mounted) {
      await _openSetup(context, unit, {
        'title': title ?? '',
        'link': link ?? '',
        if (startDate != null) 'start': startDate!.toIso8601String(),
        if (endDate != null) 'end': endDate!.toIso8601String(),
      });
    }
    return occasion;
  }

  static Future<void> _openSetup(BuildContext context, UnitModel unit,
      Map<String, dynamic> initialData) async {
    final store = OccasionSetupDrafts(Supabase.instance.client);
    final draft =
        await ExceptionHandler.guard(context, futureFunction: () async {
      final created = await store.create(unit.id!, OccasionSetupDrafts.newId());
      return store.save(created, {...created.data, ...initialData}, 0);
    });
    if (draft != null && context.mounted) {
      await OccasionSetupPage.open(context, draft);
    }
  }

  static String? _validateLink(String link) {
    return isValidPublicSlug(link, allowEmpty: true)
        ? null
        : FormStrings.validationLinkInvalidChars;
  }
}

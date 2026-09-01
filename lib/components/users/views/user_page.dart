import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/components/users/password_reset_request.dart';
import 'package:fstapp/components/users/account_deletion_service.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/components/users/companion/db_companions.dart';
import 'package:fstapp/components/users/companion/companion_dialog.dart';
import 'package:fstapp/components/users/companion/companion_accommodation_field.dart';
import 'package:fstapp/components/users/companion/companion_visibility.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/users/profile_load_recovery.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/schedule/event_page.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/components/cleaning/cleaning_page.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';
import 'package:fstapp/components/reception/reception_page.dart';
import 'package:fstapp/components/reception/reception_strings.dart';
import 'package:fstapp/components/map/map_navigation.dart';
import 'package:fstapp/components/app_management/settings_page.dart';
import 'package:fstapp/components/occasion/admin_page.dart';
import 'package:fstapp/components/users/views/login_page.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/widgets/buttons_helper.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/person_fields_strings.dart';
import 'package:fstapp/components/timeline/schedule_timeline.dart';
import 'package:fstapp/components/users/widgets/profile_place_field.dart';
import 'package:fstapp/components/users/widgets/profile_legal_link.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';

import '../../inventory/views/user_stay_page.dart';

@RoutePage()
class UserPage extends StatefulWidget {
  static const ROUTE = "user";

  const UserPage({super.key});

  @override
  _UserPageState createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  bool _didStartLoading = false;
  bool _isPasswordResetPending = false;

  @override
  void initState() {
    super.initState();
    ClientSyncRuntime.projectionEpoch.addListener(_onProjectionChanged);
  }

  @override
  void dispose() {
    ClientSyncRuntime.projectionEpoch.removeListener(_onProjectionChanged);
    super.dispose();
  }

  void _onProjectionChanged() {
    if (mounted && _didStartLoading && ClientSyncRuntime.isV1Selected) {
      unawaited(loadData());
    }
  }

  Future<void> _requestPasswordReset(String? accountEmail) async {
    final answer = await DialogHelper.showConfirmationDialog(
      context,
      UserStrings.changePasswordInstructions,
      UserStrings.resetPasswordProceedConfirm,
      confirmButtonMessage: CommonStrings.proceed,
    );
    if (!answer || !mounted) return;

    setState(() => _isPasswordResetPending = true);
    final email = accountEmail?.trim();
    final result = await requestPasswordReset(
      email: email,
      send: (address) async {
        await AuthService.resetPasswordForEmail(address);
      },
    );
    if (!mounted) return;
    setState(() => _isPasswordResetPending = false);

    switch (result) {
      case PasswordResetRequestResult.sent:
        await ToastHelper.Show(context, UserStrings.passwordResetSent);
        if (!mounted) return;
        await DialogHelper.showInformationDialog(
          context,
          UserStrings.changePasswordInstructions,
          UserStrings.passwordResetLinkSent(email: email!),
        );
        break;
      case PasswordResetRequestResult.missingEmail:
        await ToastHelper.Show(
          context,
          UserStrings.passwordResetEmailMissing,
          severity: ToastSeverity.NotOk,
        );
        if (!mounted) return;
        await DialogHelper.showInformationDialog(
          context,
          UserStrings.changePasswordInstructions,
          UserStrings.passwordResetEmailMissing,
        );
        break;
      case PasswordResetRequestResult.failed:
        await ToastHelper.Show(
          context,
          UserStrings.passwordResetFailed,
          severity: ToastSeverity.NotOk,
        );
        if (!mounted) return;
        await DialogHelper.showInformationDialog(
          context,
          UserStrings.changePasswordInstructions,
          UserStrings.passwordResetFailed,
        );
        break;
    }
  }

  void _showFullScreenDialog(
    BuildContext context,
    String name,
    String eventName,
    String id,
  ) {
    final ScreenshotController screenshotController = ScreenshotController();

    showDialog(
      useSafeArea: false,
      context: context,
      builder: (BuildContext context) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: Colors.black,
              ),
              onPressed: () {
                RouterService.goBack(context);
              },
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(6.0),
                child: IconButton(
                  onPressed: () async {
                    final Uint8List? captured =
                        await screenshotController.capture();
                    if (captured == null) return;
                    await FileSaver.instance.saveFile(
                      name: name,
                      bytes: captured,
                      fileExtension: 'png',
                      mimeType: MimeType.png,
                    );
                  },
                  icon: Icon(
                    Icons.download,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          backgroundColor: Colors.white,
          body: Center(
            child: Screenshot(
              controller: screenshotController,
              child: Container(
                color: Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      "[$eventName]",
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    QrImageView(
                      data: id,
                      version: QrVersions.auto,
                      size: 250.0,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "[$name]",
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  UserInfoModel? userData;

  @override
  Widget build(BuildContext context) {
    List<Widget> actions = [
      IconButton(
        icon: Icon(
          Icons.settings,
          color: ThemeConfig.appBarColorNegative(),
        ),
        onPressed: () => RouterService.navigate(context, SettingsPage.ROUTE),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(UserStrings.profile,
            style: TextStyle(color: ThemeConfig.appBarColorNegative())),
        leading: BackButton(
          color: ThemeConfig.appBarColorNegative(),
          onPressed: () => RouterService.popOrHome(context),
        ),
        actions: actions,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                const SizedBox(height: 15),
                if (FeatureService.isFeatureEnabled(FeatureConstants.entryCode))
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: ButtonsHelper.buildReferenceButton(
                      context: context,
                      onPressed: () => _showFullScreenDialog(
                        context,
                        userData?.name ?? "",
                        AppConfig.appName,
                        userData?.id ?? "",
                      ),
                      icon: Icons.qr_code,
                      label: UserStrings.showMyCode,
                    ),
                  ),
                if (canShowCompanionManagement(
                  featureEnabled: FeatureService.isCompanionsEnabled(),
                  allowUserCreate: FeatureService.allowsUserCompanionCreation(),
                  hasOwnedCompanions: userData?.companions?.isNotEmpty ?? false,
                ))
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom:
                            BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: (userData?.companions?.length ?? 0) + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return ListTile(
                            title: Text(
                              UserStrings.manageCompanions,
                              style: TextStyle(
                                color: ThemeConfig.blackColor(context),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.manage_accounts_outlined),
                              onPressed: () async {
                                await showDialog(
                                  context: context,
                                  builder: (_) => CompanionManagementDialog(
                                    allowUserCreate: FeatureService
                                        .allowsUserCompanionCreation(),
                                    maxCompanions:
                                        FeatureService.getMaxCompanions(),
                                    companions:
                                        userData?.companions ?? const [],
                                    refreshData: loadData,
                                  ),
                                );
                              },
                            ),
                          );
                        }
                        final companion = userData?.companions![index - 1];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            children: [
                              const SizedBox(height: 10),
                              Container(
                                decoration: BoxDecoration(
                                  color: ThemeConfig.qrButtonColor(context),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ExpansionTile(
                                  shape: const Border(),
                                  title: Text(
                                    companion!.fullName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${companion.groupTitle.isEmpty ? UserStrings.noGroup : companion.groupTitle} · ${UserStrings.signedInEvents(count: companion.schedule?.length.toString() ?? "0")}',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                      fontSize: 13,
                                    ),
                                  ),
                                  trailing: canShowCompanionQrAction(
                                    entryCodeEnabled:
                                        FeatureService.isFeatureEnabled(
                                      FeatureConstants.entryCode,
                                    ),
                                  )
                                      ? ButtonsHelper.buildReferenceButton(
                                          context: context,
                                          onPressed: () =>
                                              _showFullScreenDialog(
                                            context,
                                            companion.name,
                                            AppConfig.appName,
                                            companion.id,
                                          ),
                                          icon: Icons.qr_code,
                                          label: UserStrings.showCode,
                                        )
                                      : null,
                                  expandedCrossAxisAlignment:
                                      CrossAxisAlignment.center,
                                  children: [
                                    if (FeatureService
                                        .isServiceAccommodationEnabled())
                                      CompanionAccommodationField(
                                        companion: companion,
                                        onOpenPlace: (placeId) =>
                                            MapNavigation.openPlace(
                                          context,
                                          placeId,
                                        ),
                                      ),
                                    const SizedBox(height: 36),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 600,
                                      ),
                                      child: ScheduleTimeline(
                                        eventGroups: TimeBlockHelper
                                            .splitTimeBlocksByDay(
                                          companion.timeBlocks,
                                          context,
                                        ),
                                        onEventPressed: (eventId) async {
                                          await RouterService.navigateOccasion(
                                            context,
                                            "${EventPage.ROUTE}/$eventId",
                                          ).then((value) => loadData());
                                          await loadData();
                                        },
                                        nodePosition: 0.3,
                                        emptyContent: Center(
                                          child: Text(
                                            UserStrings.companionEventsEmpty,
                                            style: TextStyle(
                                              color:
                                                  ThemeConfig.grey600(context),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 48),
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (companion.origin ==
                                                'self_created' &&
                                            companion.canOwnerDelete)
                                          TextButton(
                                            onPressed: () async {
                                              var answer = await DialogHelper
                                                  .showConfirmationDialog(
                                                      context,
                                                      UserStrings
                                                          .deleteCompanion,
                                                      UserStrings
                                                          .deleteCompanionConfirm);
                                              if (!answer) {
                                                return;
                                              }
                                              await DbCompanions.deleteSelf(
                                                  companion);
                                              await loadData();
                                            },
                                            child: Text(
                                                UserStrings.deleteCompanion),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 15),
                buildTextField(CommonStrings.name, userData?.name ?? ""),
                buildTextField(
                    PersonFieldsStrings.surname, userData?.surname ?? ""),
                buildTextField(
                    PersonFieldsStrings.email, userData?.email ?? ""),
                buildTextField(PersonFieldsStrings.sexLabel,
                    UserInfoModel.sexToLocale(userData?.sex)),
                if (FeatureService.isFeatureEnabled(FeatureConstants.services))
                  _buildStaySection(context),
                if (userData?.eventUserGroup != null) _buildGroupField(context),
                if (FeatureService.isFeatureEnabled(FeatureConstants.cleaning))
                  _buildCleaningSection(context),
                if (RightsService.canUseReception())
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: ListTile(
                      tileColor: ThemeConfig.qrButtonColor(context),
                      leading: Icon(Icons.how_to_reg,
                          color: Theme.of(context).colorScheme.primary),
                      title: Text(
                        ReceptionStrings.title,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        ReceptionStrings.subtitle,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      onTap: () => RouterService.navigateOccasion(
                          context, ReceptionPage.ROUTE),
                    ),
                  ),
                const SizedBox(height: 16),
                Visibility(
                  visible: RightsService.canSeeAdmin(),
                  child: ButtonsHelper.bigButton(
                    context: context,
                    onPressed: () async => _redirectToAdminPage(),
                    label: CommonStrings.eventManagement,
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Card(
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    color: ThemeConfig.qrButtonColor(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(children: [
                      ListTile(
                        leading: Icon(Icons.logout,
                            color: Theme.of(context).colorScheme.primary),
                        title: Text(
                          UserStrings.signOut,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onTap: _logout,
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: Icon(Icons.lock_reset,
                            color: Theme.of(context).colorScheme.primary),
                        title: Text(
                          UserStrings.changePassword,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        onTap: _isPasswordResetPending
                            ? null
                            : () => _requestPasswordReset(userData?.email),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: Icon(Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error),
                        title: Text(
                          UserStrings.deleteAccount,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                        onTap: _requestAccountDeletion,
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 72),
                const Divider(indent: 32, endIndent: 32),
                const SizedBox(height: 12),
                const AppLegalLinks(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didStartLoading) return;
    _didStartLoading = true;
    if (!AuthService.isLoggedIn()) {
      RouterService.navigateOccasion(context, LoginPage.ROUTE);
      return;
    }
    loadData();
  }

  Widget buildTextField(String labelText, String placeholder) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: TextField(
        readOnly: true,
        focusNode: AlwaysDisabledFocusNode(),
        decoration: InputDecoration(
            suffixIcon: null,
            contentPadding: const EdgeInsets.only(bottom: 3),
            labelText: labelText,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            hintText: placeholder,
            hintStyle: const TextStyle(
              fontSize: 17,
            )),
      ),
    );
  }

  Future<void> _logout() async {
    var trPrefix = RightsService.currentUser()?.getGenderPrefix();
    await AuthService.logout();
    ToastHelper.Show(context, ScheduleStrings.youHaveBeenSignedOut(trPrefix));
    RouterService.popOrHome(context);
  }

  Future<void> _requestAccountDeletion() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(UserStrings.deleteAccount),
            content: Text(
              '${UserStrings.deleteAccountScope}\n\n${UserStrings.deleteAccountConfirm}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(CommonStrings.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(UserStrings.deleteAccount),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      final result = await AccountDeletionService().request();
      if (!mounted) return;
      await DialogHelper.showInformationDialog(
        context,
        UserStrings.deleteAccount,
        UserStrings.accountDeletionEmailSent(result.maskedEmail),
      );
    } catch (_) {
      if (!mounted) return;
      await DialogHelper.showInformationDialog(
        context,
        UserStrings.deleteAccount,
        UserStrings.accountDeletionFailed,
      );
    }
  }

  void _redirectToAdminPage() {
    RouterService.navigateOccasion(context, AdminPage.ROUTE)
        .then((value) => loadData());
  }

  /// Chooses how to present the user's stay/accommodation.
  ///
  /// In accommodation ("stay") mode we show the user's single, stable
  /// accommodation as a direct link to its place on the map (or a
  /// "not specified" note). In capacity-groups / food modes we keep the link
  /// to the full stay page, which lists rooms, meals and program slots.
  Widget _buildStaySection(BuildContext context) {
    if (FeatureService.isServiceAccommodationEnabled()) {
      return _buildAccommodationField(context);
    }
    return _buildStayDetailsCard(context);
  }

  /// Simple accommodation field, rendered as a normal read-only profile row
  /// (label + value with an underline, matching "I am" / "E-mail"). When a
  /// place is assigned the value is a clickable link to it on the map;
  /// otherwise it shows a "not specified" note.
  Widget _buildAccommodationField(BuildContext context) {
    final place = userData?.accommodationPlace;
    return ProfilePlaceField(
      label: InventoryStrings.typeAccommodation,
      value: place?.title ?? InventoryStrings.accommodationNotSpecified,
      place: place,
      icon: Icons.place,
      onOpenPlace: (placeId) => MapNavigation.openPlace(context, placeId),
    );
  }

  Widget _buildGroupField(BuildContext context) {
    final group = userData!.eventUserGroup!;
    return ProfilePlaceField(
      label: ScheduleStrings.group,
      value: group.title,
      place: group.place,
      icon: Icons.groups_outlined,
      onOpenPlace: (placeId) => MapNavigation.openPlace(context, placeId),
    );
  }

  /// Entry point to the Cleaning service page (visible to every participant when
  /// the feature is enabled — anyone can report; Q7).
  Widget _buildCleaningSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListTile(
        tileColor: ThemeConfig.qrButtonColor(context),
        leading: Icon(Icons.cleaning_services,
            color: Theme.of(context).colorScheme.primary),
        title: Text(
          CleaningStrings.pageTitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          CleaningStrings.tapToReport,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () =>
            RouterService.navigateOccasion(context, CleaningPage.ROUTE),
      ),
    );
  }

  /// Link to the full stay page (rooms, meals, program) used by the inventory /
  /// capacity-groups system.
  Widget _buildStayDetailsCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListTile(
        tileColor: ThemeConfig.qrButtonColor(context),
        leading:
            Icon(Icons.hotel, color: Theme.of(context).colorScheme.primary),
        title: Text(InventoryStrings.userStayLinkTitle,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(InventoryStrings.userStayLinkSubtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () =>
            RouterService.navigateOccasion(context, UserStayPage.ROUTE),
      ),
    );
  }

  Future<void> loadData() async {
    final bootstrapUser = RightsService.currentUser();
    if (mounted && userData == null && bootstrapUser != null) {
      setState(() => userData = bootstrapUser);
    }
    final userInfo = ConnectivityService.isOfflineNotifier.value
        ? await loadProfileWithFallback<UserInfoModel>(
            loadFresh: () async => null,
            loadCached: OfflineDataService.getUserInfo,
            loadBootstrap: () => bootstrapUser,
          )
        : await loadProfileWithFallback<UserInfoModel>(
            loadFresh: () async {
              final fresh = await AuthService.getFullUserInfo();
              await OfflineDataService.saveUserInfo(fresh);
              return fresh;
            },
            loadCached: OfflineDataService.getUserInfo,
            loadBootstrap: () => bootstrapUser,
            onFreshError: (error, stackTrace) => AppLogger.error(
              'Profile enrichment failed; using available identity: '
              '$error\n$stackTrace',
            ),
            onCacheError: (error, stackTrace) => AppLogger.error(
              'Cached profile load failed; using bootstrap identity: '
              '$error\n$stackTrace',
            ),
          );
    await addOfflineEventsToCompanions(userInfo);
    if (!mounted) return;
    setState(() {
      userData = userInfo;
    });
  }

  Future<void> addOfflineEventsToCompanions(UserInfoModel? userInfo) async {
    var events = await OfflineDataService.getAllEvents();
    userInfo?.companions?.forEach((c) {
      c.schedule?.clear();
      c.timeBlocks.clear();
      for (var ei in c.eventIds) {
        var match = events.firstWhereOrNull((e) => e.id == ei);
        if (match != null) {
          c.schedule!.add(match);
        }
      }
      c.timeBlocks
          .addAll(c.schedule!.map((e) => TimeBlockItem.forCompanion(e)));
    });
  }
}

class AlwaysDisabledFocusNode extends FocusNode {
  @override
  bool get hasFocus => false;
}

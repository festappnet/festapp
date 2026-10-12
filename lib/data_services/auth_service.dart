import 'package:collection/collection.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/users/companion/db_companions.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/components/groups/db_groups.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/data_services/synchro_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/client_sync/client_sync_protocol.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection.dart';
import 'package:fstapp/data_services/auth_refresh_recovery.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/services/notification_helper.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../components/map/place_model.dart';
import '../components/users/logout_flow.dart';

class AuthService {
  static final _supabase = Supabase.instance.client;
  static const _secureStorage = FlutterSecureStorage();
  static const REFRESH_TOKEN_KEY = 'refresh';
  static const metaLang = 'lang';

  static Future<void> completeExternalLogin(Map<String, dynamic> result) async {
    if (result['organization'] != AppConfig.organization ||
        result['userId'] is! String) {
      throw const AuthException('account_identity_inconsistent');
    }
    final session = Map<String, dynamic>.from(result['session'] as Map);
    try {
      DbEvents.invalidateSavedProgramMutationScope();
      final auth =
          await _supabase.auth.setSession(session['refresh_token'] as String);
      if (auth.session?.user.id != result['userId']) {
        throw const AuthException('account_identity_inconsistent');
      }
      final profile = await _supabase
          .from(Tb.user_info.table)
          .select(Tb.user_info.id)
          .eq(Tb.user_info.id, result['userId'])
          .eq(Tb.user_info.organization, AppConfig.organization)
          .maybeSingle();
      if (profile == null) {
        throw const AuthException('account_identity_inconsistent');
      }
      // Bootstrap can still hold anonymous data after the OAuth round trip.
      // Load the installed identity's full context before publishing success.
      await RightsService.updateAppData(force: true, refreshOffline: false);
      if (RightsService.currentUser()?.id != result['userId']) {
        throw const AuthException('account_identity_inconsistent');
      }
      await _finalizeLogin(auth.session!);
    } catch (_) {
      await _supabase.auth.signOut(scope: SignOutScope.local);
      await _secureStorage.delete(key: REFRESH_TOKEN_KEY);
      await OfflineDataService.clearUserData();
      rethrow;
    }
  }

  static Future<void> login(String email, String password) async {
    DbEvents.invalidateSavedProgramMutationScope();
    // Invitations use expiring single-use proofs; ordinary passwords keep their flow.
    if (RegExp(r'^\d{6}$').hasMatch(password)) {
      String? refreshToken;
      try {
        final response = await _supabase.functions
            .invoke('exchange-sign-in-code', body: {
          'email': AppConfig.removeUserPrefix(email),
          'code': password,
          'organization': AppConfig.organization
        });
        refreshToken = response.data is Map
            ? response.data['refresh_token'] as String?
            : null;
      } on FunctionException {
        // Rolling deployment or transient exchange failure must not disable
        // an existing ordinary six-digit password on the legacy Auth endpoint.
      }
      if (refreshToken != null) {
        final result = await _supabase.auth.setSession(refreshToken);
        await _finalizeLogin(result.session!);
        return;
      }
    }
    var data = await _supabase.auth
        .signInWithPassword(email: email, password: password);
    await _finalizeLogin(data.session!);
  }

  static Future<void> loginWithQr(String payload) async {
    await _loginWithReceptionCredential({'payload': payload});
  }

  static Future<void> loginWithManualCode(String code) async {
    await _loginWithReceptionCredential({
      'occasion': RightsService.currentOccasionId(),
      'manualCode': code,
    });
  }

  static Future<void> _loginWithReceptionCredential(
      Map<String, dynamic> credential) async {
    DbEvents.invalidateSavedProgramMutationScope();
    final response = await _supabase.functions.invoke(
      'exchange-login-qr',
      body: credential,
    );
    final body = Map<String, dynamic>.from(response.data as Map);
    final refreshToken = body['refresh_token']?.toString();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const AuthException('Invalid QR credential');
    }
    final auth = await _supabase.auth.setSession(refreshToken);
    if (auth.session == null) throw const AuthException('Invalid QR session');
    await _finalizeLogin(auth.session!);
  }

  static Future<void> _finalizeLogin(Session session) async {
    if (!await validateCurrentOrganization()) {
      throw Exception('Account is not available for this organization.');
    }
    await _secureStorage.write(
        key: REFRESH_TOKEN_KEY, value: session.refreshToken.toString());
    try {
      if (AppConfig.isAppSupported) {
        if (ClientSyncRuntime.isV1Selected) {
          await RightsService.updateAppData(force: true, refreshOffline: false);
          await ClientSyncRuntime.identityChanged();
          await ClientSyncRuntime.refresh(SyncReason.login,
              privateConsumer: true);
          await DbEvents.synchronizeMySchedule(join: true);
        } else {
          await DbEvents.synchronizeMySchedule(join: true);
          await SynchroService.refreshOfflineData();
        }
      }
    } catch (error) {
      AppLogger.error('Post-login data refresh failed: $error');
    }
    try {
      await NotificationHelper.loginCurrentUser();
    } catch (error) {
      AppLogger.error('Post-login notification identity failed: $error');
    }
  }

  static Future<void> logout() async {
    DbEvents.invalidateSavedProgramMutationScope();
    await runLogoutFlow(
      signOutLocal: () => _supabase.auth.signOut(scope: SignOutScope.local),
      clearRefreshToken: () => _secureStorage.delete(key: REFRESH_TOKEN_KEY),
      clearPrivateData: OfflineDataService.clearUserData,
      resetIdentity: ClientSyncRuntime.identityChanged,
      clearRights: () {
        RightsService.occasionLinkModel?.occasionUser = null;
        RightsService.occasionLinkModel?.unitUser = null;
        RightsService.occasionLinkModel?.userInfo = null;
        RightsService.occasionLinkModelNotifier.value =
            RightsService.occasionLinkModel;
      },
      detachNotifications: () => NotificationHelper.logoutCurrentUser()
          .timeout(const Duration(seconds: 2)),
      onCleanupError: (step, error) =>
          AppLogger.error('Post-logout $step cleanup failed: $error'),
    );
  }

  static Future<dynamic> resetPasswordForEmail(String email) async {
    return await _supabase.functions.invoke("send-reset-password-link",
        body: {"email": email, "organization": AppConfig.organization});
  }

  static Future<bool> sendSignInCode(OccasionUserModel ou) async {
    final response =
        await _supabase.functions.invoke("send-sign-in-code", body: {
      "oc": ou.occasion,
      "usr": ou.user,
    });
    return response.data?["status"] == "sent";
  }

  static Future<bool> sendAppLinks(OccasionUserModel ou) async {
    final response = await _supabase.functions.invoke("send-app-links", body: {
      "oc": ou.occasion,
      "usr": ou.user,
    });
    return response.data?["status"] == "sent";
  }

  static Future<UserInfoModel> getFullUserInfo() async {
    if (ClientSyncRuntime.isV1Selected) {
      return await ClientSyncProjection.userInfo() ??
          RightsService.currentUser() ??
          UserInfoModel();
    }
    final participation =
        await DbUsers.getOccasionUser(AuthService.currentUserId());
    var user = (RightsService.currentUser() ?? UserInfoModel())
        .withOccasionParticipation(participation);
    if (RightsService.currentOccasionUser()?.role != null) {
      user.roleString =
          await getRoleInfo(RightsService.currentOccasionUser()!.role!);
    }
    user.userGroups = await DbGroups.getUserGroups();
    var eUserGroup = user.userGroups!.firstWhereOrNull((g) => g.type == null);
    if (eUserGroup != null) {
      user.eventUserGroup = await DbGroups.getUserGroupInfo(eUserGroup.id!);
    }
    if (FeatureService.isFeatureEnabled(FeatureConstants.companions)) {
      user.companions = await DbCompanions.getAllCompanions();
    }
    var oc = RightsService.currentOccasion()!;
    var place = oc.getReferenceToService(
        DbOccasions.serviceTypeAccommodation, user.occasionUser?.services);
    if (place != null) {
      user.accommodationPlace = PlaceModel(
          id: place.reference, title: place.title, description: "", type: "");
    }
    return user;
  }

  static Future<String> getRoleInfo(int role) async {
    var data = await _supabase
        .from(Tb.role_info.table)
        .select(Tb.role_info.title)
        .eq(Tb.role_info.id, role)
        .single();
    return data[Tb.role_info.title];
  }

  static Future<bool> refreshSession() async {
    try {
      final response = await _supabase.auth.refreshSession();
      if (response.session != null) {
        await _secureStorage.write(
          key: REFRESH_TOKEN_KEY,
          value: response.session!.refreshToken,
        );
        return true;
      }
    } catch (error) {
      if (!isTerminalAuthRefreshError(error)) rethrow;
    }
    if (await tryAuthUser()) {
      return true;
    }
    return false;
  }

  static Future<bool> tryAuthUser() async {
    if (!await _secureStorage.containsKey(key: REFRESH_TOKEN_KEY)) {
      return false;
    }
    var refresh = await _secureStorage.read(key: REFRESH_TOKEN_KEY);
    try {
      var result = await _supabase.auth.setSession(refresh.toString());
      if (result.user != null) {
        await _secureStorage.write(
            key: REFRESH_TOKEN_KEY,
            value: _supabase.auth.currentSession!.refreshToken.toString());
        return true;
      } else {
        await NotificationHelper.logoutCurrentUser();
      }
    } catch (error) {
      if (isTerminalAuthRefreshError(error)) {
        await _clearTerminalSession();
      }
    }
    return false;
  }

  static Future<void> _clearTerminalSession() async {
    try {
      await logout();
    } catch (error) {
      AppLogger.error('Terminal migrated session cleanup failed: $error');
      await _supabase.auth.signOut(scope: SignOutScope.local);
      await _secureStorage.delete(key: REFRESH_TOKEN_KEY);
      await OfflineDataService.clearUserData();
    }
  }

  /// Rejects a recovered identity that belongs to a different Festapp tenant.
  /// A network failure is not treated as proof of mismatch: the cutover has
  /// already removed private cache, so the session can be revalidated online.
  static Future<bool> validateCurrentOrganization() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return true;
    Map<String, dynamic>? profile;
    try {
      profile = await _supabase
          .from(Tb.user_info.table)
          .select(Tb.user_info.id)
          .eq(Tb.user_info.id, user.id)
          .eq(Tb.user_info.organization, AppConfig.organization)
          .maybeSingle();
    } catch (_) {
      return true;
    }
    if (profile != null) return true;
    try {
      await logout();
    } catch (_) {
      await _supabase.auth.signOut(scope: SignOutScope.local);
      await _secureStorage.delete(key: REFRESH_TOKEN_KEY);
      await OfflineDataService.clearUserData();
    }
    return false;
  }

  static bool isLoggedIn() {
    return _supabase.auth.currentSession != null;
  }

  static String currentUserId() {
    return _supabase.auth.currentUser!.id;
  }

  static void ensureUserIsLoggedIn() {
    if (!AuthService.isLoggedIn()) {
      throw Exception("User must be logged in.");
    }
  }

  static Future<void> ensureCanUpdateUsers(OccasionUserModel oum) async {
    if (!RightsService.canUpdateUsers()) {
      await AuthService.refreshSession();
      if (!RightsService.canUpdateUsers()) {
        var errorText =
            "Elevated permission is required. Changes to user ${oum.data?[Tb.occasion_users.data_email]} could not be saved.";
        throw Exception(errorText);
      }
    }
  }

  static Future<Map<String, dynamic>> register(
      Map<String, dynamic> data) async {
    data["organization"] = AppConfig.organization;
    data["signInCodeVersion"] = 2;
    var resp = await _supabase.functions.invoke("register", body: data);
    return resp.data;
  }

  static Future<void> unsafeChangeUserPassword(
      OccasionUserModel occasionUserModel, String pwd) async {
    var data = await _supabase.rpc("reset_user_password",
        params: {"p_user_id": occasionUserModel.user, "p_password": pwd});
    if (data["code"] != 200) {
      throw Exception(data["message"]);
    }
  }

  static Future<void> changeMyPassword(String pw) async {
    await _supabase.auth.updateUser(UserAttributes(
      password: pw,
    ));
  }

  static Future<dynamic> changePassword(String token, String pw) async {
    return await _supabase.rpc("set_user_password_token", params: {
      "token": token,
      "password": pw,
    });
  }

  static Future<void> recoverSession(String refreshToken) async {
    final response = await _supabase.auth.setSession(refreshToken);
    if (response.session != null) {
      await _secureStorage.write(
          key: REFRESH_TOKEN_KEY,
          value: response.session!.refreshToken.toString());
    }
  }
}

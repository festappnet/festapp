import 'dart:convert';

import 'package:crypto/crypto.dart';
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
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection.dart';
import 'package:fstapp/data_services/auth_refresh_recovery.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/services/notification_helper.dart';
import 'package:fstapp/services/account_mfa_settings_service.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:festapp_core/map.dart';

import '../components/users/logout_flow.dart';

enum InvitationDeliveryStatus { sent, queued }

class PendingAccountVerification {
  const PendingAccountVerification._(
    this._session,
    this._organization,
    this.factors, {
    this.recovery = false,
    this.canReplaceFactor = false,
    this.securityKeys = const [],
  });

  final Session _session;
  final int _organization;
  final List<Factor> factors;
  final bool recovery;
  final bool canReplaceFactor;
  final List<Factor> securityKeys;
}

class AccountVerificationRequired implements Exception {
  const AccountVerificationRequired(this.verification);

  final PendingAccountVerification verification;
}

class AuthService {
  static final _supabase = Supabase.instance.client;
  static const _secureStorage = FlutterSecureStorage();
  static const _offlineAssuranceKey = 'offline_account_assurance_v1';
  static int _assuranceEpoch = 0;
  static Session? _authorizedSession;
  static int? _authorizedOrganization;
  static Future<void> _assuranceStorageTail = Future<void>.value();

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
      RightsService.invalidateCapabilities(clearIdentity: true);
      final auth = await _supabase.auth.setSession(
        session['refresh_token'] as String,
      );
      if (auth.session?.user.id != result['userId']) {
        throw const AuthException('account_identity_inconsistent');
      }
      await _finalizeLogin(auth.session!, requireOrganizationProfile: true);
      if (RightsService.currentUser()?.id != result['userId']) {
        throw const AuthException('account_identity_inconsistent');
      }
    } on AccountVerificationRequired {
      rethrow;
    } catch (_) {
      await logout();
      rethrow;
    }
  }

  static Future<void> login(String email, String password) async {
    DbEvents.invalidateSavedProgramMutationScope();
    if (RegExp(r'^\d{6}$').hasMatch(password)) {
      final exchange = await _supabase.functions.invoke(
        'exchange-sign-in-code',
        body: {
          'email': AppConfig.removeUserPrefix(email),
          'code': password,
          'organization': AppConfig.organization,
        },
      );
      final refreshToken = exchange.data is Map
          ? exchange.data['refresh_token']
          : null;
      if (refreshToken is String && refreshToken.isNotEmpty) {
        final data = await _supabase.auth.setSession(refreshToken);
        if (data.session == null) {
          throw const AuthException('Invalid code session');
        }
        await _finalizeLogin(data.session!);
        return;
      }
    }
    final data = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    await _finalizeLogin(data.session!);
  }

  static Future<void> loginWithPasskey({required bool Function() isActive}) async {
    DbEvents.invalidateSavedProgramMutationScope();
    final service = AccountMfaSettingsService.open();
    try {
      final session = await service.signInWithPasskey(isActive: isActive);
      await _finalizeLogin(session);
    } finally {
      service.dispose();
    }
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
    Map<String, dynamic> credential,
  ) async {
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

  static Future<void> _finalizeLogin(
    Session session, {
    bool requireOrganizationProfile = false,
  }) async {
    RightsService.invalidateCapabilities(clearIdentity: true);
    final verification = await _verificationFor(session);
    if (verification != null) throw AccountVerificationRequired(verification);
    if (!await validateCurrentOrganization(requireProfile: requireOrganizationProfile)) {
      throw Exception('Account is not available for this organization.');
    }
    await _secureStorage.write(
      key: REFRESH_TOKEN_KEY,
      value: session.refreshToken.toString(),
    );
    try {
      await RightsService.updateAppData(force: true, refreshOffline: false);
      if (AppConfig.isAppSupported) {
        if (ClientSyncRuntime.isV1Selected) {
          await ClientSyncRuntime.identityChanged();
          await ClientSyncRuntime.refresh(
            SyncReason.login,
            privateConsumer: true,
          );
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

  static Future<PendingAccountVerification?>
  pendingAccountVerification() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return null;
    return _verificationFor(session);
  }

  static void _requireCurrentSession(Session session, int organization) {
    if (_supabase.auth.currentSession?.accessToken != session.accessToken ||
        AppConfig.organization != organization) {
      throw const AuthException('invalid_session');
    }
  }

  static void requireCurrentVerification(PendingAccountVerification verification) {
    _requireCurrentSession(verification._session, verification._organization);
  }

  static String? get privateCacheOwner {
    final session = _supabase.auth.currentSession;
    if (session == null ||
        _authorizedOrganization != AppConfig.organization ||
        session.accessToken != _authorizedSession?.accessToken ||
        session.expiresAt == null ||
        session.isExpired) {
      return null;
    }
    return '${AppConfig.organization}/${session.user.id}';
  }

  static String _tokenDigest(Session session, int organization) => sha256
      .convert(utf8.encode('$organization|${session.accessToken}'))
      .toString();

  static void _setAssurance(Session? session, int? organization) {
    _assuranceEpoch++;
    _authorizedSession = session;
    _authorizedOrganization = organization;
  }

  static Future<void> _persistAssurance() {
    final session = _authorizedSession;
    final organization = _authorizedOrganization;
    final digest = session != null && organization != null
        ? _tokenDigest(session, organization)
        : null;
    _assuranceStorageTail = _assuranceStorageTail.then((_) async {
      try {
        if (digest == null) {
          await _secureStorage.delete(key: _offlineAssuranceKey);
        } else {
          await _secureStorage.write(key: _offlineAssuranceKey, value: digest);
        }
      } catch (error) {
        AppLogger.error(
          'Offline account assurance storage failed: ${error.runtimeType}',
        );
      }
    });
    return _assuranceStorageTail;
  }

  static Future<void> restoreOfflineAssurance() async {
    final session = _supabase.auth.currentSession;
    final organization = AppConfig.organization;
    if (session == null || session.expiresAt == null || session.isExpired)
      return;
    final epoch = _assuranceEpoch;
    try {
      final digest = await _secureStorage.read(key: _offlineAssuranceKey);
      _requireCurrentSession(session, organization);
      if (epoch == _assuranceEpoch &&
          digest == _tokenDigest(session, organization)) {
        _setAssurance(session, organization);
      }
    } catch (error) {
      AppLogger.error(
        'Offline account assurance restore failed: ${error.runtimeType}',
      );
    }
  }

  static void monitorPrivateCacheAssurance() {
    _supabase.auth.onAuthStateChange.listen((state) async {
      if (state.event != AuthChangeEvent.tokenRefreshed) return;
      try {
        await authorizePrivateCache();
      } catch (error) {
        AppLogger.error(
          'Private cache assurance refresh failed: ${error.runtimeType}',
        );
      }
    });
  }

  /// A pending verification retains its Auth session until the login UI opens.
  static Future<bool> authorizePrivateCache() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return false;
    return await _accountDecision(session, AppConfig.organization) == 'allowed';
  }

  static Future<Object?> _accountDecision(
    Session session,
    int organization,
  ) async {
    _requireCurrentSession(session, organization);
    final decision = await _supabase.rpc(
      'get_account_assurance_v1',
      params: {'p_organization': organization},
    );
    _requireCurrentSession(session, organization);
    if (decision == 'allowed' &&
        session.expiresAt != null &&
        !session.isExpired) {
      _setAssurance(session, organization);
    } else {
      _setAssurance(null, null);
      RightsService.invalidateCapabilities(clearIdentity: true);
    }
    await _persistAssurance();
    _requireCurrentSession(session, organization);
    return decision;
  }

  static Future<PendingAccountVerification?> _verificationFor(
    Session session,
  ) async {
    final organization = AppConfig.organization;
    final decision = await _accountDecision(session, organization);
    if (decision == 'allowed') return null;
    if (decision == 'account_recovery') {
      final actor = await _supabase.rpc(
        'get_mfa_recovery_registration_actor_v1',
        params: {'p_organization': organization},
      );
      _requireCurrentSession(session, organization);
      return PendingAccountVerification._(
        session,
        organization,
        const [],
        recovery: true,
        canReplaceFactor: actor is Map && actor['decision'] == 'allowed',
      );
    }
    if (decision != 'mfa_required' && decision != 'proof_required') {
      throw const AuthException('invalid_session');
    }
    // GoTrue's Dart listFactors refreshes the session. Read the factor
    // inventory with this exact token so the pending proof stays bound.
    final verifiedUser = await _supabase.auth.getUser(session.accessToken);
    _requireCurrentSession(session, organization);
    final verified = (verifiedUser.user?.factors ?? const <Factor>[])
        .where((factor) => factor.status == FactorStatus.verified);
    final totp = verified.where((factor) => factor.factorType == FactorType.totp).toList();
    final securityKeys = AccountMfaSettingsService.supportsWebAuthnVerification
        ? verified.where((factor) => factor.factorType == FactorType.webauthn).toList()
        : const <Factor>[];
    if (totp.isEmpty && securityKeys.isEmpty) {
      throw const AuthException('mfa_factor_unavailable');
    }
    return PendingAccountVerification._(
      session,
      organization,
      List.unmodifiable(totp),
      securityKeys: List.unmodifiable(securityKeys),
    );
  }

  static Future<void> verifyAccountWebAuthn(
    PendingAccountVerification verification,
    String factorId,
  ) async {
    requireCurrentVerification(verification);
    final factor = verification.securityKeys.firstWhereOrNull((factor) => factor.id == factorId);
    if (factor == null) throw const AuthException('invalid_webauthn_challenge');
    final service = AccountMfaSettingsService.open();
    try {
      final session = await service.verifyWebAuthnFactor(factor, verification._session);
      _requireCurrentSession(session, verification._organization);
      await _finalizeLogin(session);
    } finally {
      service.dispose();
    }
  }

  static Future<void> verifyAccountLogin(
    PendingAccountVerification verification,
    String factorId,
    String code,
  ) async {
    _requireCurrentSession(verification._session, verification._organization);
    if (!RegExp(r'^\d{6}$').hasMatch(code) ||
        !verification.factors.any((factor) => factor.id == factorId)) {
      throw const AuthException('invalid_mfa_code');
    }
    final result = await _supabase.auth.mfa.challengeAndVerify(
      factorId: factorId,
      code: code,
    );
    final installed = _supabase.auth.currentSession;
    if (installed == null ||
        installed.accessToken != result.accessToken ||
        installed.user.id != verification._session.user.id ||
        AppConfig.organization != verification._organization) {
      throw const AuthException('invalid_session');
    }
    await _finalizeLogin(installed);
  }

  static Future<void> cancelAccountVerification(
    PendingAccountVerification verification,
  ) async {
    if (verification.recovery ||
        _supabase.auth.currentSession?.accessToken !=
            verification._session.accessToken ||
        AppConfig.organization != verification._organization) {
      return;
    }
    await logout();
  }

  static Future<void> logout() async {
    final owner = '${AppConfig.organization}/${_supabase.auth.currentUser?.id}';
    _setAssurance(null, null);
    final clearAssurance = _persistAssurance();
    RightsService.invalidateCapabilities(clearIdentity: true);
    DbEvents.invalidateSavedProgramMutationScope();
    await runLogoutFlow(
      signOutLocal: () => _supabase.auth.signOut(scope: SignOutScope.local),
      clearRefreshToken: () async {
        await clearAssurance;
        await _secureStorage.delete(key: REFRESH_TOKEN_KEY);
      },
      clearPrivateData: () => OfflineDataService.clearUserData(owner: owner),
      resetIdentity: ClientSyncRuntime.identityChanged,
      clearRights: () {
        RightsService.invalidateCapabilities(clearIdentity: true);
      },
      detachNotifications: () => NotificationHelper.logoutCurrentUser().timeout(
        const Duration(seconds: 2),
      ),
      onCleanupError: (step, error) =>
          AppLogger.error('Post-logout $step cleanup failed: $error'),
    );
  }

  static Future<dynamic> resetPasswordForEmail(String email) async {
    return await _supabase.functions.invoke(
      "send-reset-password-link",
      body: {"email": email, "organization": AppConfig.organization},
    );
  }

  static Future<InvitationDeliveryStatus> sendSignInCode(
    OccasionUserModel ou, {
    String? requestId,
  }) async {
    final response = await _supabase.functions.invoke(
      "send-sign-in-code",
      body: {
        "oc": ou.occasion,
        "usr": ou.user,
        if (requestId != null) "requestId": requestId,
      },
    );
    return switch (response.data?["status"]) {
      "sent" => InvitationDeliveryStatus.sent,
      "queued" => InvitationDeliveryStatus.queued,
      _ => throw StateError('Invitation delivery was not confirmed'),
    };
  }

  static Future<bool> sendAppLinks(OccasionUserModel ou) async {
    final response = await _supabase.functions.invoke(
      "send-app-links",
      body: {"oc": ou.occasion, "usr": ou.user},
    );
    return response.data?["status"] == "sent";
  }

  static Future<UserInfoModel> getFullUserInfo() async {
    if (ClientSyncRuntime.isV1Selected) {
      return await ClientSyncProjection.userInfo() ??
          RightsService.currentUser() ??
          UserInfoModel();
    }
    final participation = await DbUsers.getOccasionUser(
      AuthService.currentUserId(),
    );
    var user = (RightsService.currentUser() ?? UserInfoModel())
        .withOccasionParticipation(participation);
    if (RightsService.currentOccasionUser()?.role != null) {
      user.roleString = await getRoleInfo(
        RightsService.currentOccasionUser()!.role!,
      );
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
      DbOccasions.serviceTypeAccommodation,
      user.occasionUser?.services,
    );
    if (place != null) {
      user.accommodationPlace = PlaceModel(
        id: place.reference,
        title: place.title,
        description: "",
        type: "",
      );
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
          value: _supabase.auth.currentSession!.refreshToken.toString(),
        );
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
  static Future<bool> validateCurrentOrganization({bool requireProfile = false}) async {
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
      if (requireProfile) rethrow;
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
    Map<String, dynamic> data,
  ) async {
    data["organization"] = AppConfig.organization;
    var resp = await _supabase.functions.invoke("register", body: data);
    return resp.data;
  }

  static Future<void> unsafeChangeUserPassword(
    OccasionUserModel occasionUserModel,
    String pwd,
  ) async {
    var data = await _supabase.rpc(
      "reset_user_password",
      params: {"p_user_id": occasionUserModel.user, "p_password": pwd},
    );
    if (data["code"] != 200) {
      throw Exception(data["message"]);
    }
  }

  static Future<dynamic> changePassword(String token, String pw) async {
    return await _supabase.rpc(
      "set_user_password_token",
      params: {"token": token, "password": pw},
    );
  }

  static Future<void> recoverSession(String refreshToken) async {
    final response = await _supabase.auth.setSession(refreshToken);
    if (response.session != null) {
      await _secureStorage.write(
        key: REFRESH_TOKEN_KEY,
        value: response.session!.refreshToken.toString(),
      );
    }
  }
}

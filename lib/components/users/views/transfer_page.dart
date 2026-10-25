import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/auth_handoff_noop.dart'
    if (dart.library.html) 'package:fstapp/services/auth_handoff_web.dart'
    if (dart.library.js_interop) 'package:fstapp/services/auth_handoff_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@RoutePage()
class TransferPage extends StatefulWidget {
  static const String ROUTE = 'transfer';

  final String? access_token;
  final String? refresh_token;

  final String? redirect;

  const TransferPage({
    super.key,
    @QueryParam('access_token') this.access_token,
    @QueryParam('refresh_token') this.refresh_token,
    @QueryParam('redirect') this.redirect,
  });

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  @override
  void initState() {
    super.initState();
    _handleSession();
  }

  Future<void> _handleSession() async {
    AppLogger.debug("TransferPage: Handling Session...");

    // 1. Check if we are already logged in (Persistence)
    bool loggedIn = AuthService.isLoggedIn();
    if (!loggedIn) {
      loggedIn = await AuthService.tryAuthUser();
    }

      // 2. Try sessionStorage handoff (web auth_bridge)
    if (!loggedIn) {
      final handoff = consumeAuthHandoff();
      if (handoff != null) {
        final refreshToken = handoff['refresh_token'];
        if (refreshToken != null && refreshToken.isNotEmpty) {
          try {
            AppLogger.debug("TransferPage: Setting session from handoff...");
            if (Supabase.instance.client.auth.currentSession != null) {
              await Supabase.instance.client.auth.signOut();
            }
            await AuthService.recoverSession(refreshToken);
            await AuthService.refreshSession();
            loggedIn = true;
          } catch (e) {
            AppLogger.error("TransferPage: Handoff session error: $e");
            loggedIn = await AuthService.tryAuthUser();
          }
        }
      }
    }

      // 3. Fallback: use the token from query params (mobile deep links)
    if (!loggedIn &&
        widget.refresh_token != null &&
        widget.refresh_token!.isNotEmpty) {
      try {
        AppLogger.debug("TransferPage: Setting session from token...");
        // Ensure a clean slate before setting a new session
        if (Supabase.instance.client.auth.currentSession != null) {
          await Supabase.instance.client.auth.signOut();
        }
        await AuthService.recoverSession(widget.refresh_token!);
        // Refreshing session
        await AuthService.refreshSession();
        loggedIn = true;
      } catch (e) {
        AppLogger.error("TransferPage: Session set error: $e");
        // Final check in case it worked anyway
        loggedIn = await AuthService.tryAuthUser();
      }
    }

    if (loggedIn) {
      // 3. Logged In -> Execute Post-Login Logic (Mirrors LoginPage)
      // This centralized method handles:
      // - Updating App Data (force: true)
      // - Checking for Units (redirect to UnitAdmin)
      // - Fallback to provided path (or Home)
      if (mounted) {
        try {
          AppLogger.debug(
              "TransferPage: Session valid ($loggedIn). calling handlePostLoginNavigation");
          await RouterService.handlePostLoginNavigation(context,
              fallbackPath: widget.redirect ?? "/", useReplacement: true);
        } catch (e) {
          AppLogger.error("TransferPage: Smart nav failed. Error: $e");
          if (mounted) {
            await context.router.replacePath("/");
          }
        }
      }
    } else {
      // 4. Failed -> Login Page
      AppLogger.debug(
          "TransferPage: Session INVALID ($loggedIn). Redirecting to LoginRoute.");
      if (mounted) {
        context.router.replace(LoginRoute());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

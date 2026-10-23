import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrganizationAdminGuard extends StatefulWidget {
  final Widget Function(BuildContext context, int organizationId) builder;
  final int? targetOrganizationId;

  const OrganizationAdminGuard(
      {super.key, required this.builder, this.targetOrganizationId});

  @override
  State<OrganizationAdminGuard> createState() => _OrganizationAdminGuardState();
}

class _OrganizationAdminGuardState extends State<OrganizationAdminGuard> {
  bool _isLoading = true;
  bool _loadingContext = false;
  bool _hasAccess = false;
  int? _organizationId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    RightsService.occasionLinkModelNotifier.addListener(_checkAccess);
    _initializeAccess();
  }

  Future<void> _initializeAccess() async {
    // Direct web-client entry skips the startup occasion fetch. Load the same
    // capability projection before interpreting its absence as a denial.
    if (Supabase.instance.client.auth.currentUser != null &&
        (RightsService.occasionLinkModel == null ||
            RightsService.pendingContextUpdate != null)) {
      _loadingContext = true;
      try {
        await (RightsService.pendingContextUpdate ??
            RightsService.updateAppData(force: true, refreshOffline: false));
      } catch (error) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = error.toString();
          });
        }
        return;
      } finally {
        _loadingContext = false;
      }
    }
    if (mounted) _checkAccess();
  }

  @override
  void didUpdateWidget(covariant OrganizationAdminGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetOrganizationId != widget.targetOrganizationId) {
      _checkAccess();
    }
  }

  @override
  void dispose() {
    RightsService.occasionLinkModelNotifier.removeListener(_checkAccess);
    super.dispose();
  }

  void _checkAccess() {
    if (_loadingContext) return;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception("User not logged in.");
      }

      // Contextual Organization ID resolution
      // We still rely on some context to know WHICH organization to check.
      // Prioritize explicit target, then current unit's organization.
      int? orgId = widget.targetOrganizationId;
      if (orgId == null) {
        final currentUnit = RightsService.currentUnit();
        orgId = currentUnit?.organization ??
            RightsService.currentUser()?.units?.firstOrNull?.organization;
      }

      if (orgId == null) {
        // Fallback: Check if the user is an admin of ANY organization?
        // Or just fail. The page implies editing the "current" organization.
        throw Exception("Could not determine context organization.");
      }

      final isAdmin = AppConfig.organization == orgId &&
          RightsService.hasCapability(
              AuthorizationCapabilities.organizationSettingsWrite);

      if (isAdmin == true) {
        if (mounted) {
          setState(() {
            _hasAccess = true;
            _errorMessage = null;
            _organizationId = orgId;
            _isLoading = false;
          });
        }
      } else {
        throw Exception(
            "Access Denied. User is not an admin of organization $orgId.");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasAccess = false;
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasAccess || _organizationId == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Access Denied",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SelectableText(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Go Back"),
              )
            ],
          ),
        ),
      );
    }

    return widget.builder(context, _organizationId!);
  }
}

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/organization/db_organizations.dart';

@RoutePage()
class OrganizationEditRedirectPage extends StatefulWidget {
  static const String ROUTE = "organizationEdit";

  const OrganizationEditRedirectPage({super.key});

  @override
  State<OrganizationEditRedirectPage> createState() =>
      _OrganizationEditRedirectPageState();
}

class _OrganizationEditRedirectPageState
    extends State<OrganizationEditRedirectPage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    try {
      final orgId = await DbOrganizations.getMyAdminOrganizationId();
      if (orgId != null) {
        if (mounted) {
          context.router.replace(OrganizationEditRoute(id: orgId));
        }
      } else {
        setState(() {
          _error = "You are not an admin of any organization.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Error checking organization permissions: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Access Denied")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.router.replacePath("/"),
                  child: const Text("Go Home"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

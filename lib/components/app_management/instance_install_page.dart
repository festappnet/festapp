import 'dart:convert';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@RoutePage()
class InstanceInstallPage extends StatefulWidget {
  static const ROUTE = "instanceInstall";

  const InstanceInstallPage({super.key});
  @override
  _InstanceInstallPageState createState() => _InstanceInstallPageState();
}

class _InstanceInstallPageState extends State<InstanceInstallPage> {
  // Declare controllers as `late final` to initialize them in `initState`.
  late final TextEditingController _projectUrlController;
  late final TextEditingController _dbController;

  final TextEditingController _repoController =
      TextEditingController(text: 'festappnet/festapp');

  @override
  void initState() {
    super.initState();

    // Initialize the project URL controller from AppConfig.
    _projectUrlController = TextEditingController(
      text: AppConfig.supabaseUrl,
    );

    // Now, derive the database connection string from the first controller's text.
    final projectUrl = _projectUrlController.text;
    String dbHost;
    try {
      final uri = Uri.parse(projectUrl);
      dbHost = 'db.${uri.host}';
    } catch (_) {
      // Provide a fallback in case the URL is somehow invalid.
      dbHost = 'invalid-supabase-host';
    }
    _dbController = TextEditingController(
      text: 'postgresql://postgres:YOUR_PASSWORD@$dbHost:5432/postgres',
    );
  }

  @override
  void dispose() {
    // Dispose of the controllers when the state is disposed.
    _projectUrlController.dispose();
    _dbController.dispose();
    _repoController.dispose();
    super.dispose();
  }

  // Define the list of operations for the Initial section.
  final List<OperationSectionData> _initialOperations = [
    OperationSectionData(title: "1. Tables", fixedDirectory: "database/tables"),
    OperationSectionData(
        title: "2. Functions", fixedDirectory: "database/functions"),
    OperationSectionData(
        title: "3. Policies", fixedDirectory: "database/policies"),
    OperationSectionData(title: "4. Seed", fixedDirectory: "database/seed"),
  ];

  /// Helper getter that extracts the project ref from the project URL.
  /// For example, from "https://kjdpmixlnhntmxjedpxh.supabase.co" it returns "kjdpmixlnhntmxjedpxh".
  String get _projectRef {
    final url = _projectUrlController.text.trim();
    try {
      final uri = Uri.parse(url);
      if (uri.host.endsWith(".supabase.co")) {
        return uri.host.split('.').first;
      }
    } catch (_) {
      // If URL parsing fails, fall back to the raw text.
    }
    return url;
  }

  /// Generates the deploy commands using the extracted project ref.
  String get _deployCommands {
    final ref = _projectRef;
    return '''
supabase functions deploy notify --no-verify-jwt --project-ref $ref
supabase functions deploy register --no-verify-jwt --project-ref $ref
supabase functions deploy send-email --no-verify-jwt --project-ref $ref
supabase functions deploy send-custom-email --no-verify-jwt --project-ref $ref
supabase functions deploy send-sign-in-code --no-verify-jwt --project-ref $ref
supabase functions deploy send-app-links --no-verify-jwt --project-ref $ref
supabase functions deploy send-reset-password-link --no-verify-jwt --project-ref $ref
supabase functions deploy send-ticket-order --no-verify-jwt --project-ref $ref
supabase functions deploy send-tickets --no-verify-jwt --project-ref $ref
supabase functions deploy fetch-transactions --no-verify-jwt --project-ref $ref
supabase functions deploy instance-install --no-verify-jwt --project-ref $ref
supabase functions deploy fetch-http-data --no-verify-jwt --project-ref $ref
supabase functions deploy download-ticket --no-verify-jwt --project-ref $ref
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Instance Installation')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Common fields: Supabase Project URL, Database Connection String, and Repo.
            TextField(
              controller: _projectUrlController,
              decoration: const InputDecoration(
                labelText: 'Supabase Project URL',
                hintText: 'Enter your Supabase project URL',
              ),
              onChanged: (_) {
                // Rebuild to update the deploy commands when project URL changes.
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _dbController,
              decoration: const InputDecoration(
                labelText: 'Database Connection String',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _repoController,
              decoration: const InputDecoration(
                labelText: 'GitHub Repository with scripts',
              ),
            ),
            const SizedBox(height: 20),
            // Card with deploy commands (selectable and copyable)
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Supabase Function Deploy Commands:',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: _deployCommands));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Copied to clipboard"),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _deployCommands,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Initial Section
            const Text(
              "Initial",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            Column(
              children: _initialOperations.map((op) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: OperationSectionWidget(
                    title: op.title,
                    fixedDirectory: op.fixedDirectory,
                    customDirectory: false,
                    dbController: _dbController,
                    repoController: _repoController,
                    projectUrlController: _projectUrlController,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            // Migrations Section
            const Text(
              "Migrations",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            OperationSectionWidget(
              title: "Migrations",
              // For migrations, let the user type the directory.
              customDirectory: true,
              initialDirectory: "migrations",
              dbController: _dbController,
              repoController: _repoController,
              projectUrlController: _projectUrlController,
            ),
          ],
        ),
      ),
    );
  }
}

class OperationSectionData {
  final String title;
  final String fixedDirectory;

  OperationSectionData({required this.title, required this.fixedDirectory});
}

class OperationSectionWidget extends StatefulWidget {
  final String title;
  final String? fixedDirectory;
  final bool customDirectory;
  final String? initialDirectory;
  final TextEditingController dbController;
  final TextEditingController repoController;
  final TextEditingController projectUrlController;

  const OperationSectionWidget({
    super.key,
    required this.title,
    required this.dbController,
    required this.repoController,
    required this.projectUrlController,
    this.fixedDirectory,
    this.customDirectory = false,
    this.initialDirectory,
  });

  @override
  _OperationSectionWidgetState createState() => _OperationSectionWidgetState();
}

class _OperationSectionWidgetState extends State<OperationSectionWidget> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _customDirController = TextEditingController();
  bool _isLoading = false;
  String _statusMessage = '';
  bool? _wasSuccess; // null: not run, true: success, false: error

  // Only used when running the seed scripts.
  TextEditingController? _adminEmailController;
  TextEditingController? _adminPasswordController;

  // Determines if this operation is the Seed operation.
  bool get _isSeed => widget.fixedDirectory == "database/seed";

  @override
  void initState() {
    super.initState();
    if (widget.customDirectory) {
      _customDirController.text = widget.initialDirectory ?? '';
    }
    // For seed, initialize admin-specific controllers.
    if (_isSeed) {
      _adminEmailController = TextEditingController();
      _adminPasswordController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _customDirController.dispose();
    _adminEmailController?.dispose();
    _adminPasswordController?.dispose();
    super.dispose();
  }

  Future<void> _triggerOperation() async {
    // Get common values from parent controllers.
    final dbConnectionString = widget.dbController.text;
    final repo = widget.repoController.text;
    // Get directory: either a fixed value or the text entered by the user.
    final directory = widget.customDirectory
        ? _customDirController.text
        : widget.fixedDirectory ?? '';

    // Build the JSON payload.
    final Map<String, dynamic> bodyMap = {
      "dbConnectionString": dbConnectionString,
      "repo": repo,
      "directory": directory,
    };

    // For seed, optionally add admin credentials if provided.
    if (_isSeed) {
      final adminEmail = _adminEmailController!.text.trim();
      final adminPassword = _adminPasswordController!.text.trim();
      // Include the project URL regardless.
      bodyMap["project_url"] = widget.projectUrlController.text.trim();
      if (adminEmail.isNotEmpty && adminPassword.isNotEmpty) {
        bodyMap.addAll({
          "admin_email": adminEmail,
          "admin_password": adminPassword,
        });
      }
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "${widget.title} operation is running...";
      _wasSuccess = null;
    });

    try {
      final response = await _supabase.functions.invoke(
        "instance-install",
        body: bodyMap.isNotEmpty ? jsonEncode(bodyMap) : null,
      );

      if (response.status != 200) {
        setState(() {
          _statusMessage = "Error: ${response.data}";
          _wasSuccess = false;
          _isLoading = false;
        });
      } else {
        setState(() {
          _statusMessage = "${widget.title} operation completed successfully.";
          _wasSuccess = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Unexpected error: $e";
        _wasSuccess = false;
        _isLoading = false;
      });
    }
  }

  Widget _buildStatusIndicator() {
    if (_wasSuccess == null) return const SizedBox();
    return _wasSuccess == true
        ? Icon(Icons.check_circle, color: ThemeConfig.greenColor(context))
        : Icon(Icons.error, color: ThemeConfig.redColor(context));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row with a status icon if already run.
            Row(
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusIndicator(),
              ],
            ),
            const SizedBox(height: 10),
            // If this section uses a custom directory, show a TextField.
            // Otherwise, show the fixed directory text (which is not editable).
            widget.customDirectory
                ? TextField(
                    controller: _customDirController,
                    decoration: const InputDecoration(labelText: 'Directory'),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text("Directory: ${widget.fixedDirectory}"),
                  ),
            // If this is the seed section, show a note and extra fields.
            if (_isSeed) ...[
              const Divider(),
              const Text(
                "Before running seed, please ensure that you have enabled:\n"
                " - Webhooks in Supabase Dashboard (Database > Webhooks)\n"
                " - moddatetime extension (Database > Extensions)\n"
                " - unaccent extension (Database > Extensions)\n"
                " - pg_cron extension (Database > Extensions)",
                style: TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 8),
              const Text(
                "Admin Email and Password are optional. If left blank, no new admin user will be inserted.",
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _adminEmailController,
                decoration: const InputDecoration(labelText: 'Admin Email'),
              ),
              TextField(
                controller: _adminPasswordController,
                decoration: const InputDecoration(labelText: 'Admin Password'),
                obscureText: true,
              ),
              // Show the common Supabase Project URL as read-only in the seed section.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  "Supabase Project URL: ${widget.projectUrlController.text}",
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            ],
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isLoading ? null : _triggerOperation,
              child: const Text('Run Scripts'),
            ),
            const SizedBox(height: 8),
            // Show a progress indicator if running, or display the status message.
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _statusMessage.isNotEmpty
                    ? SelectableText(
                        _statusMessage,
                        style: const TextStyle(fontSize: 16),
                      )
                    : const SizedBox(),
          ],
        ),
      ),
    );
  }
}

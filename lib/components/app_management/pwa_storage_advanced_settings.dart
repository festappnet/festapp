import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/app_management/app_management_strings.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/pwa_storage/pwa_storage.dart';

class PwaStorageAdvancedSettings extends StatefulWidget {
  const PwaStorageAdvancedSettings({super.key, this.storage});

  final PwaStoragePort? storage;

  @override
  State<PwaStorageAdvancedSettings> createState() =>
      _PwaStorageAdvancedSettingsState();
}

class _PwaStorageAdvancedSettingsState
    extends State<PwaStorageAdvancedSettings> {
  late final PwaStoragePort _storage = widget.storage ?? createPwaStoragePort();
  PwaStorageReport? _report;
  bool _busy = false;

  Future<void> _inspect() async {
    setState(() => _busy = true);
    final report = await ExceptionHandler.guard<PwaStorageReport>(
      context,
      futureFunction: _storage.inspect,
    );
    if (!mounted) return;
    setState(() {
      if (report != null) _report = report;
      _busy = false;
    });
  }

  Future<void> _prune() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppManagementStrings.pruneShells),
        content: Text(AppManagementStrings.pruneShellsConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppManagementStrings.pruneShells),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final pruned = await ExceptionHandler.guard<PwaShellReport>(
      context,
      futureFunction: _storage.pruneUnusedShells,
    );
    if (!mounted) return;
    PwaStorageReport? report;
    if (pruned != null && pruned.blocker == null) {
      report = await ExceptionHandler.guard<PwaStorageReport>(
        context,
        futureFunction: _storage.inspect,
      );
      if (!mounted) return;
    } else if (pruned != null) {
      report = PwaStorageReport(
        estimate: _report?.estimate ?? const PwaStorageEstimate(),
        shells: pruned,
      );
    }
    setState(() {
      if (report != null) _report = report;
      _busy = false;
    });
  }

  String _mib(int? bytes) =>
      bytes == null ? '—' : (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(CommonStrings.advancedSettings),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppManagementStrings.storageTitle,
              style: const TextStyle(fontSize: 18),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _inspect,
                child: Text(AppManagementStrings.inspectStorage),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _prune,
                child: Text(AppManagementStrings.pruneShells),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_report case final report?) ...[
            const SizedBox(height: 8),
            Text(AppManagementStrings.storageUsage(
              usage: _mib(report.estimate.usageBytes),
              quota: _mib(report.estimate.quotaBytes),
            )),
            Text(report.shells.blocker != null
                ? AppManagementStrings.storageBlocked
                : AppManagementStrings.storageReady(
                    retained: report.shells.retained.length.toString(),
                    deletable: report.shells.deletable.length.toString(),
                  )),
          ],
          const SizedBox(height: 8),
        ],
      );
}

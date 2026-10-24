import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/widgets/app_dialog.dart';

/// Each task succeeds only when its callback completes. Failed tasks remain
/// visible and can be retried without repeating successful side effects.
enum BatchTaskOutcome { completed, deferred }

class BatchTask {
  final String label;
  final Future<BatchTaskOutcome> Function() run;
  const BatchTask({required this.label, required this.run});
}

class BatchProgressDialog extends StatefulWidget {
  final String title;
  final List<BatchTask> tasks;
  final String successLabel;
  final String failureLabel;
  final String retryLabel;
  final String deferredLabel;

  const BatchProgressDialog(
      {super.key,
      required this.title,
      required this.tasks,
      required this.successLabel,
      required this.failureLabel,
      required this.retryLabel,
      required this.deferredLabel});

  @override
  State<BatchProgressDialog> createState() => _BatchProgressDialogState();
}

class _BatchProgressDialogState extends State<BatchProgressDialog> {
  final Set<int> _succeeded = {};
  final Set<int> _failed = {};
  final Set<int> _deferred = {};
  bool _running = true;
  int? _current;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _run(List.generate(widget.tasks.length, (i) => i)));
  }

  Future<void> _run(List<int> indices) async {
    setState(() => _running = true);
    for (final index in indices) {
      if (!mounted) return;
      setState(() {
        _current = index;
        _failed.remove(index);
        _deferred.remove(index);
      });
      try {
        final result = await widget.tasks[index].run();
        if (result == BatchTaskOutcome.completed) {
          _succeeded.add(index);
        } else {
          _deferred.add(index);
        }
      } catch (_) {
        _failed.add(index);
      }
      if (!mounted) return;
      setState(() {});
    }
    if (mounted) {
      setState(() {
        _running = false;
        _current = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_running,
        child: AppAlertDialog(
          title: Text(widget.title),
          dismissible: !_running,
          onClose: _running ? null : () => Navigator.of(context).pop(),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_running) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                  '${widget.successLabel}: ${_succeeded.length}/${widget.tasks.length}\n'
                  '${widget.deferredLabel}: ${_deferred.length}\n'
                  '${widget.failureLabel}: ${_failed.length}'),
              const SizedBox(height: 12),
              Flexible(
                  child: SingleChildScrollView(
                      child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(
                    widget.tasks.length,
                    (index) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                              '${widget.tasks[index].label}: ${_succeeded.contains(index) ? widget.successLabel : _failed.contains(index) ? widget.failureLabel : _deferred.contains(index) ? widget.deferredLabel : _current == index ? CommonStrings.processing : CommonStrings.loading}'),
                        )),
              ))),
              if (!_running) ...[
                const SizedBox(height: 12),
                Text(_failed.isNotEmpty
                    ? CommonStrings.processingFailed
                    : _deferred.isNotEmpty
                        ? widget.deferredLabel
                        : CommonStrings.processingCompleted),
              ],
            ]),
          ),
          actions: [
            if (_failed.isNotEmpty || _deferred.isNotEmpty)
              TextButton(
                  onPressed: _running
                      ? null
                      : () => _run({..._failed, ..._deferred}.toList()..sort()),
                  child: Text(widget.retryLabel)),
            TextButton(
                onPressed: _running ? null : () => Navigator.of(context).pop(),
                child: Text(CommonStrings.ok)),
          ],
        ),
      );
}

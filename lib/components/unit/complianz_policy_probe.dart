import 'dart:async';

enum ComplianzProbeStatus { idle, loading, detected, unavailable }

/// Owns optional detection only, never the editor's draft or persisted pin.
/// Cancellation invalidates requests and disposes deadlines without requiring
/// the transport to complete. Callers own rebuilding after synchronous cancel.
class ComplianzPolicyProbe {
  ComplianzPolicyProbe({required this.onChanged});

  final void Function() onChanged;
  ComplianzProbeStatus _status = ComplianzProbeStatus.idle;
  String? _policyId;
  ComplianzProbeStatus get status => _status;
  String? get policyId => _policyId;
  int _generation = 0;
  Timer? _deadline;
  Completer<void>? _completion;

  void cancel() {
    ++_generation;
    _completion?.complete();
    _completion = null;
    _deadline?.cancel();
    _deadline = null;
    _status = ComplianzProbeStatus.idle;
    _policyId = null;
  }

  Future<void> detect(String origin, Future<String> Function(String) load) {
    cancel();
    final generation = _generation;
    final completion = Completer<void>();
    _completion = completion;
    _status = ComplianzProbeStatus.loading;
    onChanged();
    void complete(String? result) {
      if (generation != _generation) return;
      ++_generation;
      _deadline?.cancel();
      _deadline = null;
      _completion = null;
      completion.complete();
      _policyId = result;
      _status = result == null
          ? ComplianzProbeStatus.unavailable
          : ComplianzProbeStatus.detected;
      onChanged();
    }

    _deadline = Timer(const Duration(seconds: 20), () => complete(null));
    // The caller awaits the bounded lifecycle, never the unbounded transport.
    unawaited(() async {
      try {
        final result = await load(origin);
        complete(
          RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(result) ? result : null,
        );
      } catch (_) {
        // Optional probing has a local recovery path and no global error dialog.
        complete(null);
      }
    }());
    return completion.future;
  }
}

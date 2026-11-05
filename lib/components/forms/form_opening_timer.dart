import 'dart:async';

/// A distant opening must never overflow the browser's 32-bit timer delay.
/// Intermediate wakes only re-arm the alarm; they never reload the form.
class FormOpeningTimer {
  FormOpeningTimer(this.target, this.onOpened, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _arm();
  }
  final DateTime target;
  final void Function() onOpened;
  final DateTime Function() _now;
  Timer? _timer;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
  }

  void _arm() {
    if (_cancelled) return;
    final remaining = target.difference(_now());
    final delay = remaining > const Duration(days: 1)
        ? const Duration(days: 1)
        : remaining.isNegative
        ? Duration.zero
        : remaining;
    _timer = Timer(delay, () {
      if (_cancelled) return;
      if (target.isAfter(_now())) {
        _arm();
      } else {
        _cancelled = true;
        onOpened();
      }
    });
  }
}

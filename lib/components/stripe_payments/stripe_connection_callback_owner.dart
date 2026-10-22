/// Owns an OAuth callback across login's route replacement, only for this process.
/// URL/bootstrap capture is consumed once; login never receives the code or state.
class StripeConnectionCallbackOwner {
  static final instance = StripeConnectionCallbackOwner();
  Map<String, String>? _pending;

  Map<String, String>? retain(Map<String, String>? callback) {
    if (callback != null && callback.isNotEmpty) {
      _pending = Map.unmodifiable(callback);
    }
    return _pending;
  }

  /// A late completion must not discard a newer authorization callback.
  void complete(Map<String, String> callback) {
    if (identical(callback, _pending)) _pending = null;
  }
}

class ClientSyncProjectionTracker {
  bool _initialized = false;
  String? _publicScope;
  String? _catalogPointer;
  String? _livePointer;
  String? _privateScope;
  String? _privatePointer;

  void reset() {
    _initialized = false;
    _publicScope = null;
    _catalogPointer = null;
    _livePointer = null;
    _privateScope = null;
    _privatePointer = null;
  }

  void acknowledgeCatalog({required String scope, required String pointer}) {
    if (_initialized && _publicScope == scope) _catalogPointer = pointer;
  }

  void acknowledgeLive({required String scope, required String pointer}) {
    if (_initialized && _publicScope == scope) _livePointer = pointer;
  }

  void acknowledgePrivate({required String scope, required String pointer}) {
    if (_initialized && _privateScope == scope) _privatePointer = pointer;
  }

  bool observe({
    required String publicScope,
    required String? catalogPointer,
    required String? livePointer,
    required String? privateScope,
    required String? privatePointer,
  }) {
    final changed =
        !_initialized ||
        _publicScope != publicScope ||
        _catalogPointer != catalogPointer ||
        _livePointer != livePointer ||
        _privateScope != privateScope ||
        _privatePointer != privatePointer;
    _initialized = true;
    _publicScope = publicScope;
    _catalogPointer = catalogPointer;
    _livePointer = livePointer;
    _privateScope = privateScope;
    _privatePointer = privatePointer;
    return changed;
  }
}

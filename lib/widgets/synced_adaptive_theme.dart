import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:material_ui/material_ui.dart';

import '../services/theme_preference/theme_preference_store.dart';
import '../services/theme_preference/theme_preference_stub.dart'
    if (dart.library.js_interop) '../services/theme_preference/theme_preference_web.dart';

AdaptiveThemeMode? _decode(String? mode) => switch (mode) {
  'light' => AdaptiveThemeMode.light,
  'dark' => AdaptiveThemeMode.dark,
  'auto' => AdaptiveThemeMode.system,
  _ => null,
};

/// One browser preference across public pages and every admin theme selector.
class SyncedAdaptiveTheme extends StatefulWidget {
  const SyncedAdaptiveTheme({
    super.key,
    required this.light,
    required this.dark,
    required this.initial,
    required this.builder,
    this.store,
  });
  final ThemeData light, dark;
  final AdaptiveThemeMode initial;
  final Widget Function(ThemeData, ThemeData) builder;
  final ThemePreferenceStore? store;
  @override
  State<SyncedAdaptiveTheme> createState() => _SyncedAdaptiveThemeState();
}

class _SyncedAdaptiveThemeState extends State<SyncedAdaptiveTheme> {
  late final store = widget.store ?? createThemePreferenceStore();
  // Keep the startup override stable. AdaptiveTheme asynchronously restores its
  // private cache; that cache must never replace a newer shared browser choice.
  late final overrideMode = store.enabled
      ? _decode(store.read()) ?? _decode(store.readLegacy()) ?? widget.initial
      : null;
  @override
  Widget build(BuildContext context) => AdaptiveTheme(
    light: widget.light,
    dark: widget.dark,
    initial: widget.initial,
    overrideMode: overrideMode,
    builder: (light, dark) =>
        _PreferenceBinding(store: store, child: widget.builder(light, dark)),
  );
}

class _PreferenceBinding extends StatefulWidget {
  const _PreferenceBinding({required this.store, required this.child});
  final ThemePreferenceStore store;
  final Widget child;
  @override
  State<_PreferenceBinding> createState() => _PreferenceBindingState();
}

class _PreferenceBindingState extends State<_PreferenceBinding> {
  AdaptiveThemeManager<ThemeData>? manager;
  VoidCallback? cancel;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AdaptiveTheme.of(context);
    if (!widget.store.enabled) return;
    if (identical(manager, next)) {
      // AdaptiveTheme restores its private cache asynchronously. Reconcile with
      // the shared value again after that rebuild, including an early tab event.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _receive();
      });
      return;
    }
    manager?.modeChangeNotifier.removeListener(_publish);
    cancel?.call();
    manager = next;
    next.modeChangeNotifier.addListener(_publish);
    cancel = widget.store.listen(_receive);
    _publish();
  }

  void _publish() {
    final mode = manager!.mode;
    widget.store.write(mode == AdaptiveThemeMode.system ? 'auto' : mode.name);
  }

  void _receive() {
    final mode = _decode(widget.store.read()) ?? AdaptiveThemeMode.system;
    if (manager!.mode != mode) manager!.setThemeMode(mode);
  }

  @override
  void dispose() {
    cancel?.call();
    manager?.modeChangeNotifier.removeListener(_publish);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

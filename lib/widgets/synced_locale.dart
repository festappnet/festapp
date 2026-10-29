import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';

import '../services/locale_preference/locale_preference_store.dart';
import '../services/locale_preference/locale_preference_stub.dart'
    if (dart.library.js_interop) '../services/locale_preference/locale_preference_web.dart';

/// EasyLocalization publishes every selection through SharedPreferences.
/// This binding also receives selections made in another browser document.
class SyncedLocale extends StatefulWidget {
  const SyncedLocale({super.key, required this.child, this.store});
  final Widget child;
  final LocalePreferenceStore? store;
  @override
  State<SyncedLocale> createState() => _SyncedLocaleState();
}

class _SyncedLocaleState extends State<SyncedLocale> {
  late final store = widget.store ?? createLocalePreferenceStore();
  VoidCallback? cancel;
  bool receiving = false;
  String? desiredLanguage;
  @override
  void initState() {
    super.initState();
    if (store.enabled) {
      cancel = store.listen(_receive);
      WidgetsBinding.instance.addPostFrameCallback((_) => _receive());
    }
  }

  Future<void> _receive() async {
    if (!mounted) return;
    desiredLanguage = store.read()?.toLowerCase().split(RegExp('[_-]')).first;
    if (receiving) return;
    receiving = true;
    try {
      while (true) {
        if (!mounted) break;
        final supported = context.supportedLocales.where(
          (locale) => locale.languageCode == desiredLanguage,
        );
        if (supported.isEmpty || context.locale == supported.first) break;
        await context.setLocale(supported.first);
        // A new event can replace the desired choice while translations load.
      }
    } finally {
      receiving = false;
    }
  }

  @override
  void dispose() {
    cancel?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

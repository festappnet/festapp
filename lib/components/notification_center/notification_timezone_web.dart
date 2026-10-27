import 'dart:js_interop';
import 'dart:js_interop_unsafe';

String? browserTimezone() {
  try {
    final intl = globalContext.getProperty<JSObject>('Intl'.toJS);
    final formatter = intl.callMethodVarArgs<JSObject>(
      'DateTimeFormat'.toJS,
      const [],
    );
    final options = formatter.callMethodVarArgs<JSObject>(
      'resolvedOptions'.toJS,
      const [],
    );
    return options.getProperty<JSString>('timeZone'.toJS).toDart;
  } catch (_) {
    return null;
  }
}

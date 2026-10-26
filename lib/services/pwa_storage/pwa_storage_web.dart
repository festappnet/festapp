import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'pwa_storage_codec.dart';
import 'pwa_storage_port.dart';

PwaStoragePort createPwaStoragePort() => const WebPwaStoragePort();

class WebPwaStoragePort implements PwaStoragePort {
  const WebPwaStoragePort();

  Future<Map<String, dynamic>> _call(String method) {
    final completer = Completer<Map<String, dynamic>>();
    void success(JSAny? value) {
      final result = value.dartify();
      completer.complete(pwaStringMap(result));
    }

    void failure(JSAny? value) {
      completer.completeError(Exception(value.dartify()?.toString() ?? method));
    }

    globalContext.callMethodVarArgs<JSAny?>(
      method.toJS,
      [success.toJS, failure.toJS],
    );
    return completer.future;
  }

  @override
  Future<PwaStorageReport> inspect() async {
    final value = await _call('festappInspectPwaStorage');
    return decodePwaStorageReport(value);
  }

  @override
  Future<PwaShellReport> pruneUnusedShells() async =>
      decodePwaShellReport(await _call('festappPruneUnusedShells'));
}

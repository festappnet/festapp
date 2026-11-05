import 'dart:convert';
import 'dart:js_interop';

@JS('venueLayoutTextReady')
external JSPromise<JSAny?> get _ready;
@JS('venueLayoutPrepareText')
external JSPromise<JSString> _prepare(JSString value);

Future<Map<String, dynamic>> prepareTextBatch(
  Map<String, dynamic> batch,
) async {
  await _ready.toDart;
  return Map<String, dynamic>.from(
    jsonDecode((await _prepare(jsonEncode(batch).toJS).toDart).toDart) as Map,
  );
}

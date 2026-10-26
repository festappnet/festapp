import 'dart:js_interop';
import 'feature.dart' deferred as feature;
@JS('loadAuditFeature')
external set loadAuditFeature(JSFunction value);
void main() {
  loadAuditFeature = (() => feature.loadLibrary().then((_) => feature.Feature().render().toJS).toJS).toJS;
}

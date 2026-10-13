import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void configureUrlStrategy() {
  setUrlStrategy(_PersonalFormPathUrlStrategy());
}

// Keep the existing path strategy and history handling. Only personal form
// capabilities must survive the initial route; ordinary anchors and auth
// fragments retain PathUrlStrategy's existing behavior.
class _PersonalFormPathUrlStrategy extends PathUrlStrategy {
  _PersonalFormPathUrlStrategy() : super(_location);

  static const _location = BrowserPlatformLocation();

  @override
  String getPath() {
    final path = super.getPath();
    final fragment = _location.hash;
    if (Uri.parse(path).path.startsWith('/form/') &&
        fragment.startsWith('#waitlist?')) {
      return '$path$fragment';
    }
    return path;
  }
}

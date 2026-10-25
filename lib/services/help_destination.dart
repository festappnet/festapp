import 'package:fstapp/components/navigation/navigation_paths.dart';

/// Stable public help intents contain no tenant resource IDs. They only select
/// a destination; the ordinary administration boundary still checks access.
abstract final class HelpDestination {
  static const prefix = '/help-action/';
  static const scannerSettings = 'scanner-settings';

  static bool isWebClient(String intent) => intent == scannerSettings;
  static const sections = <String, String>{
    'forms': NavigationPaths.forms,
    'seating': NavigationPaths.blueprint,
    'tickets': NavigationPaths.tickets,
    'products': NavigationPaths.products,
    'orders': '${NavigationPaths.orders}/${NavigationPaths.current}',
    'report': NavigationPaths.report,
    'settings': NavigationPaths.settings,
  };

  static String? parse(String? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.startsWith(prefix)) {
      return null;
    }
    final intent = uri.path.substring(prefix.length);
    return sections.containsKey(intent) || isWebClient(intent) ? intent : null;
  }

  static String? path(String intent, String? link, {int? occasionId}) {
    final section = sections[intent];
    if ((section == null && !isWebClient(intent)) ||
        link == null ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(link)) {
      return null;
    }
    if (isWebClient(intent)) {
      if (occasionId == null || occasionId <= 0) return null;
      return Uri(path: '/scan/settings', queryParameters: {
        'occasion': '$occasionId',
        'returnTo': '/$link/reservations/${NavigationPaths.tickets}',
      }).toString();
    }
    return '/$link/reservations/$section';
  }
}

import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/launch_url_service.dart';

/// Opens the public web form with the current same-origin administrator session.
/// The route contains an offer ID, never a participant capability or auth token.
class AdminOfferFormLink {
  static Uri url({required String formLink, required String offerId}) {
    if (formLink.trim().isEmpty ||
        !RegExp(r'^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$')
            .hasMatch(offerId)) {
      throw ArgumentError('Invalid administrator offer form link');
    }
    final query =
        Uri(queryParameters: {'offer_id': offerId, 'admin': '1'}).query;
    return Uri.parse(AppConfig.webLink)
        .replace(pathSegments: ['form', formLink], fragment: 'waitlist?$query');
  }

  static Future<bool> open(
      {required String? formLink, required String offerId}) {
    if (formLink == null || formLink.trim().isEmpty) return Future.value(false);
    return LaunchUrlService.openExternalUrl(
        url(formLink: formLink, offerId: offerId).toString());
  }
}

import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/launch_url_service.dart';

/// Opens the public web form with the current same-origin administrator session.
/// The route contains an offer ID, never a participant capability or auth token.
class AdminOfferFormLink {
  static Uri url({required String offerId}) {
    if (!RegExp(r'^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$')
        .hasMatch(offerId)) {
      throw ArgumentError('Invalid administrator offer form link');
    }
    return Uri.parse(AppConfig.webLink).replace(
      path: '/order',
      queryParameters: {'offer_id': offerId, 'admin': '1', 'waitlist': '1'},
      fragment: '',
    );
  }

  static Future<bool> open({required String offerId}) {
    return LaunchUrlService.openExternalUrl(url(offerId: offerId).toString());
  }
}

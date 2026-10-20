import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';

typedef CopyOccasionImage = Future<String> Function(
    String imageUrl, int? occasionId, int? unitId);

/// Copies each distinct media source once and reports whether URLs changed.
Future<bool> copyOccasionMedia(
    OccasionModel occasion, CopyOccasionImage copyImage) async {
  final occasionId = occasion.id!;
  var changed = false;
  final copies = <String, Future<String>>{};
  Future<String> copy(String source) async {
    final result = await copies.putIfAbsent(
        source, () => copyImage(source, occasionId, null));
    changed = changed || result != source;
    return result;
  }

  final ticketDetails = FeatureService.getFeatureDetails(
      FeatureConstants.ticket,
      features: occasion.features);
  if (ticketDetails is TicketFeature &&
      ticketDetails.ticketBackground != null &&
      ticketDetails.ticketBackground!.isNotEmpty) {
    ticketDetails.ticketBackground =
        await copy(ticketDetails.ticketBackground!);
  }

  final image = occasion.data?['image'];
  if (image is String && image.isNotEmpty) {
    occasion.data!['image'] = await copy(image);
  }
  return changed;
}

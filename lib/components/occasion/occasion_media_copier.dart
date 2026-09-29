import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';

typedef CopyOccasionImage = Future<String> Function(
    String imageUrl, int? occasionId, int? unitId);

/// Copies the media referenced by a newly duplicated occasion.
Future<void> copyOccasionMedia(
    OccasionModel occasion, CopyOccasionImage copyImage) async {
  final occasionId = occasion.id!;
  final ticketDetails = FeatureService.getFeatureDetails(
      FeatureConstants.ticket,
      features: occasion.features);
  if (ticketDetails is TicketFeature &&
      ticketDetails.ticketBackground != null &&
      ticketDetails.ticketBackground!.isNotEmpty) {
    ticketDetails.ticketBackground =
        await copyImage(ticketDetails.ticketBackground!, occasionId, null);
  }

  final image = occasion.data?['image'];
  if (image is String && image.isNotEmpty) {
    occasion.data!['image'] = await copyImage(image, occasionId, null);
  }
}

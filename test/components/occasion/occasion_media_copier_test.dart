import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/occasion/occasion_media_copier.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';

void main() {
  test('duplicated occasion images are uploaded with one owner', () async {
    final ticket = TicketFeature(
      code: FeatureConstants.ticket,
      ticketBackground: 'https://img.festapp.net/images/ticket.jpg',
    );
    final occasion = OccasionModel(
      id: 42,
      unit: 7,
      isOpen: false,
      isHidden: true,
      isPromoted: false,
      features: [ticket],
      data: {'image': 'https://img.festapp.net/images/event.jpg'},
    );
    final owners = <(int?, int?)>[];

    await copyOccasionMedia(occasion, (url, occasionId, unitId) async {
      owners.add((occasionId, unitId));
      return '$url-copy';
    });

    expect(owners, [(42, null), (42, null)]);
    expect(ticket.ticketBackground, endsWith('-copy'));
    expect(occasion.data!['image'], endsWith('-copy'));
  });
}

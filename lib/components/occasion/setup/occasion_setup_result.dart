import '../occasion_model.dart';

class OccasionSetupResult {
  final int occasionId, unit;
  final String link, title, saleMode;
  final String? formLink;
  final bool hasTickets;
  const OccasionSetupResult(
      {required this.occasionId,
      required this.unit,
      required this.link,
      required this.title,
      this.formLink,
      this.saleMode = 'preparation',
      this.hasTickets = true});
  OccasionModel get occasion => OccasionModel(
      id: occasionId,
      unit: unit,
      link: link,
      title: title,
      isOpen: false,
      isHidden: true,
      isPromoted: false);
}

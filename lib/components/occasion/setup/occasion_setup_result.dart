import '../occasion_model.dart';

class OccasionSetupResult {
  final int occasionId, unit;
  final String link, title, saleMode;
  final String? formLink;
  final bool hasTickets, isOpen, isHidden, isPromoted;
  const OccasionSetupResult({
    required this.occasionId,
    required this.unit,
    required this.link,
    required this.title,
    this.formLink,
    this.saleMode = 'preparation',
    this.hasTickets = true,
    this.isOpen = false,
    this.isHidden = true,
    this.isPromoted = false,
  });
  bool get isPublished => isOpen && !isHidden;

  OccasionModel get occasion => OccasionModel(
    id: occasionId,
    unit: unit,
    link: link,
    title: title,
    isOpen: isOpen,
    isHidden: isHidden,
    isPromoted: isPromoted,
  );
}

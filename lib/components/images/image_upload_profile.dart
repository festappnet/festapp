/// Purpose identifiers only. Dimensions, quality and output budgets live in
/// the image Worker's upload policy, never in individual widgets.
enum ImageUploadProfile {
  standard('standard'),
  ticketBackground('ticket-background'),
  blueprintBackground('blueprint-background'),
  portrait('portrait'),
  thumbnail('thumbnail'),
  banner('banner');

  const ImageUploadProfile(this.wireName);
  final String wireName;
}

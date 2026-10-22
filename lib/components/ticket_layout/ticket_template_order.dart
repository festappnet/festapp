// Shared presentation order for setup and the ticket editor's template picker.
const _ticketTemplateOrder = [
  'ball_silk',
  'silk_dark',
  'silk_light',
  'festival_poster',
  'club_panorama',
  'festival_badge',
  'sports_arena',
  'cinema_strip',
  'boarding_pass',
  'gala_invitation',
  'theatre_program',
  'concert_stub',
  'workshop_card',
  'gallery_square',
  'portrait',
  'portrait_compact',
  'portrait_event',
  'classic',
  'compact',
  'event',
];

int compareTicketTemplateKeys(String a, String b) {
  int rank(String key) {
    final index = _ticketTemplateOrder.indexOf(key);
    return index < 0 ? _ticketTemplateOrder.length : index;
  }

  final order = rank(a).compareTo(rank(b));
  return order == 0 ? a.compareTo(b) : order;
}

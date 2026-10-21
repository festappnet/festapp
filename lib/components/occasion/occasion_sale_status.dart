/// A safe catalogue projection, never a checkout/reservation decision.
class OccasionSaleForm {
  final int id;
  final bool isOpen;
  final bool hasTickets;
  final DateTime? start, end;
  final bool countdown, hasAvailability, isPreparation;
  final String mode;
  const OccasionSaleForm(
      {required this.id,
      required this.isOpen,
      this.hasTickets = true,
      this.start,
      this.end,
      this.countdown = false,
      this.hasAvailability = false,
      this.mode = 'closed',
      this.isPreparation = false});

  factory OccasionSaleForm.fromJson(Map<String, dynamic> json) =>
      OccasionSaleForm(
          id: json['id'] as int,
          isOpen: json['is_open'] == true,
          hasTickets: json['has_tickets'] != false,
          start:
              DateTime.tryParse(json['start_time'] as String? ?? '')?.toUtc(),
          end: DateTime.tryParse(json['end_time'] as String? ?? '')?.toUtc(),
          countdown: json['enable_countdown'] == true,
          isPreparation: json['is_preparation'] == true,
          hasAvailability: json['has_availability'] == true,
          mode: json['registration_mode'] as String? ?? 'closed');

  Map<String, dynamic> toJson() => {
        'id': id,
        'is_open': isOpen,
        'has_tickets': hasTickets,
        'start_time': start?.toIso8601String(),
        'end_time': end?.toIso8601String(),
        'enable_countdown': countdown,
        'has_availability': hasAvailability,
        'registration_mode': mode,
        'is_preparation': isPreparation
      };

  OccasionSaleState stateAt(DateTime now) {
    if (end != null && !now.isBefore(end!)) return OccasionSaleState.ended;
    if (start != null && now.isBefore(start!))
      return OccasionSaleState.scheduled;
    if (!isOpen)
      return isPreparation
          ? OccasionSaleState.preparation
          : OccasionSaleState.paused;
    if (mode == 'waitlist') return OccasionSaleState.waitlist;
    if (hasAvailability) return OccasionSaleState.selling;
    return OccasionSaleState.soldOut;
  }
}

enum OccasionSaleState {
  preparation,
  scheduled,
  selling,
  waitlist,
  soldOut,
  paused,
  ended,
  finished
}

class OccasionSaleStatus {
  final OccasionSaleState state;
  final int active, total, selling, waitlists;
  final DateTime? deadline;
  final bool countdown, starts;
  const OccasionSaleStatus(
      {required this.state,
      required this.active,
      required this.total,
      this.selling = 0,
      this.waitlists = 0,
      this.deadline,
      this.countdown = false,
      this.starts = false});

  static OccasionSaleStatus? resolve(List<OccasionSaleForm>? forms,
      {required DateTime now, DateTime? occasionEnd}) {
    if (forms == null || forms.isEmpty) return null;
    if (occasionEnd != null && !now.isBefore(occasionEnd)) {
      return OccasionSaleStatus(
          state: OccasionSaleState.finished, active: 0, total: forms.length);
    }
    final selling = forms
        .where((f) => f.stateAt(now) == OccasionSaleState.selling)
        .toList();
    final waiting = forms
        .where((f) => f.stateAt(now) == OccasionSaleState.waitlist)
        .toList();
    if (selling.isNotEmpty || waiting.isNotEmpty) {
      final active = [...selling, ...waiting];
      final ends = active.where((f) => f.end != null).toList()
        ..sort((a, b) => a.end!.compareTo(b.end!));
      // The overall active sale only ends at this term if every open form does.
      final end = ends.length == active.length ? ends.last.end : null;
      final deadline = occasionEnd == null
          ? end
          : end == null || occasionEnd.isBefore(end)
              ? occasionEnd
              : end;
      return OccasionSaleStatus(
          state: selling.isNotEmpty
              ? OccasionSaleState.selling
              : OccasionSaleState.waitlist,
          active: active.length,
          total: forms.length,
          selling: selling.length,
          waitlists: waiting.length,
          deadline: deadline,
          countdown: active.every((f) => f.countdown));
    }
    final future = forms
        .where((f) => f.stateAt(now) == OccasionSaleState.scheduled)
        .toList()
      ..sort((a, b) => a.start!.compareTo(b.start!));
    // A manually closed, previously opened form is paused. Old closed forms
    // without explicit intent stay in preparation rather than guessing from orders.
    if (forms.any((f) => f.stateAt(now) == OccasionSaleState.paused)) {
      return OccasionSaleStatus(
          state: OccasionSaleState.paused, active: 0, total: forms.length);
    }
    if (future.isNotEmpty) {
      final first = future.first;
      return OccasionSaleStatus(
          state: OccasionSaleState.scheduled,
          active: 0,
          total: forms.length,
          deadline: first.start,
          countdown: first.countdown,
          starts: true);
    }
    final state = forms.any((f) => f.stateAt(now) == OccasionSaleState.soldOut)
        ? OccasionSaleState.soldOut
        : forms.any((f) => f.stateAt(now) == OccasionSaleState.preparation)
            ? OccasionSaleState.preparation
            : OccasionSaleState.ended;
    return OccasionSaleStatus(state: state, active: 0, total: forms.length);
  }
}

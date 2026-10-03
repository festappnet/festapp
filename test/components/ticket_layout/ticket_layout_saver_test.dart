import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_saver.dart';

void main() {
  test('direct save persists only artwork and updates the parent version',
      () async {
    final oldLayout = <String, dynamic>{'schemaVersion': 1, 'templates': {}};
    final savedTicket = TicketFeature.fromJson(
        {'code': 'ticket', 'layout': oldLayout, 'show_hidden_note': false});
    final fresh = OccasionModel(
        isOpen: false,
        isHidden: false,
        isPromoted: false,
        id: 7,
        link: 'event',
        title: 'Saved title',
        aggregateVersion: 4,
        features: [savedTicket]);
    final current = OccasionModel(
        isOpen: false,
        isHidden: false,
        isPromoted: false,
        id: 7,
        link: 'event',
        title: 'Unsaved title',
        aggregateVersion: 4);
    final draft = TicketFeature(
        code: 'ticket',
        ticketBackground: 'new.png',
        ticketType: 'wide',
        showHiddenNote: true)
      ..layout = {'schemaVersion': 2, 'templates': {}};
    var calls = 0;
    final saver = TicketLayoutSaver(
        load: (_) async => fresh,
        persist: (value) async {
          calls++;
          expect(value.title, 'Saved title');
          final ticket = value.features.whereType<TicketFeature>().single;
          expect(ticket.ticketBackground, 'new.png');
          expect(ticket.showHiddenNote, false);
          expect(ticket.layoutChange,
              {'expected': oldLayout, 'next': draft.layout});
          value.aggregateVersion = 5;
        });
    await saver.save(current, draft);
    expect(calls, 1);
    expect(current.aggregateVersion, 5);
    expect(current.title, 'Unsaved title');
  });

  test('conflict or failed persistence never advances the parent version',
      () async {
    final current = OccasionModel(
        isOpen: false,
        isHidden: false,
        isPromoted: false,
        id: 7,
        link: 'event',
        aggregateVersion: 4);
    final draft = TicketFeature(code: 'ticket');
    var calls = 0;
    final fresh = OccasionModel(
        isOpen: false,
        isHidden: false,
        isPromoted: false,
        id: 7,
        link: 'event',
        aggregateVersion: 5);
    final saver = TicketLayoutSaver(
        load: (_) async => fresh,
        persist: (_) async {
          calls++;
          throw StateError('offline');
        });
    await expectLater(saver.save(current, draft), throwsStateError);
    expect(calls, 0);
    fresh.aggregateVersion = 4;
    await expectLater(saver.save(current, draft), throwsStateError);
    expect(calls, 1);
    expect(current.aggregateVersion, 4);
  });
}

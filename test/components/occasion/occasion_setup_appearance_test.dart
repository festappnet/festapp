import 'setup_email_preview_coordinator_cases.dart' as preview_reliability;
import 'setup_payment_configuration_cases.dart' as payment_configuration;
import 'package:fstapp/components/occasion/setup/occasion_setup_form_preview.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/app_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'dart:io';
import 'package:fstapp/components/occasion/setup/occasion_setup_draft.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_story.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance.dart';
import 'package:fstapp/components/ticket_layout/models/ticket_layout.dart';

void main() {
  group('preview reliability', preview_reliability.main);
  group('payment configuration', payment_configuration.main);
  Map<String, dynamic> draft(
          {bool tickets = true, bool formEnabled = true, num price = 0}) =>
      {
        'formEnabled': formEnabled,
        'formDraft': {
          'title': 'Akce',
          'data': {},
          'fields': [
            if (tickets) {'type': 'ticket'},
            {
              'type': 'product',
              'product_type_data': {
                'products': [
                  {'price': price}
                ]
              }
            }
          ]
        },
      };
  test('ten shared font choices preserve the event palette and reach the PDF',
      () {
    final catalog = jsonDecode(
        File('supabase/functions/_shared/ticket-assets/font-catalog.json')
            .readAsStringSync());
    final ids = {for (final face in catalog['fonts']) face['id']};
    expect(OccasionSetupAppearance.fonts.length, 10);
    for (final entry in OccasionSetupAppearance.fonts.entries) {
      expect(ids, contains(entry.value));
      final appearance = {
        ...OccasionSetupAppearance.presets[1],
        'id': 'custom',
        'fontFamily': entry.key
      };
      final data = draft();
      OccasionSetupAppearance.apply(data, appearance);
      expect(data['formDraft']['data']['design']['font_family'], entry.key);
      expect(data['ticketDraft']['layout']['templates']['wide']['fontId'],
          entry.value);
      expect(
          OccasionSetupAppearance.ticketBackground('concert_stub', appearance),
          contains('palette-14284B-A87F28-concert_stub'));
    }
    expect(
        OccasionSetupAppearance.presets
            .where(
                (p) => p['gradient'] == true && p['primary'] != p['secondary'])
            .length,
        greaterThanOrEqualTo(4));
  });
  for (final app in [false, true]) {
    for (final tickets in [false, true]) {
      test(
          'independent tickets=$tickets app=$app: active questions have no event kind',
          () {
        final data = draft(tickets: tickets);
        final questions = OccasionSetupStory.questions(app, data: data);
        expect(questions.take(3).map((q) => q.key),
            ['name', 'dates', 'appearance']);
        expect(questions.any((q) => q.key == 'kind'), false);
        expect(questions.any((q) => q.key == 'blueprint'), true);
        expect(questions.any((q) => q.key == 'ticket'), true);
        expect(OccasionSetupStory.hasTickets(data), tickets);
        for (var i = 0; i < questions.length; i++) {
          expect(
              OccasionSetupStory.index({
                ...data,
                'step': questions[i].step,
                'storyQuestion': questions[i].key
              }, app),
              i);
        }
        expect(
            OccasionSetupStory.questions(app,
                    data: draft(tickets: tickets, price: 100))
                .any((q) => q.key == 'payments'),
            true);
      });
    }
  }
  test('retired kind resumes at appearance without changing independent work',
      () {
    final data = <String, dynamic>{
      ...draft(),
      'title': 'Akce',
      'eventKind': 'regular',
      'eventKindNeedsConfirmation': true,
      'storyQuestion': 'kind',
      'step': 1,
      'blueprintMode': 'copy',
      'blueprintLayoutDraft': {
        'layout': {'nodes': []}
      }
    };
    OccasionSetupStory.normalize(data, false);
    expect(data.containsKey('eventKind'), false);
    expect(data.containsKey('eventKindNeedsConfirmation'), false);
    expect(data['storyQuestion'], 'appearance');
    expect(data['step'], 2);
    expect(data['blueprintMode'], 'copy');
    expect(data['blueprintLayoutDraft'], isNotEmpty);
    expect(OccasionSetupStory.hasTickets(data), true);
    expect((data['formDraft'] as Map)['title'], 'Akce');
  });
  test(
      'source is an optional unnumbered introduction and never an inferred permission',
      () {
    expect(OccasionSetupStory.questions(false).any((q) => q.key == 'source'),
        false);
    expect(
        OccasionSetupStory.questions(false, includeSource: true).first.optional,
        true);
  });
  test('unreviewed draft cannot report 100 percent', () {
    final d = draft();
    d['completedQuestions'] =
        OccasionSetupStory.questions(AppConfig.isAppSupported, data: d)
            .map((q) => q.key)
            .toList();
    final model = OccasionSetupDraft.fromJson({
      'id': 'draft',
      'unit': 1,
      'revision': 1,
      'current_step': 5,
      'data': d
    });
    expect(model.progress, lessThan(100));
    model.data['reviewed'] = true;
    model.data['reviewConfirmed'] = true;
    expect(model.progress, 100);
  });
  test(
      'real public builders accept unsaved fields without assigning database IDs',
      () {
    final data = <String, dynamic>{
      'formDraft': {
        'title': 'Přihláška',
        'fields': [
          {'type': 'email', 'is_required': true}
        ]
      }
    };
    final definition = occasionSetupPreviewDefinition(data);
    final holder = FormHolder.fromDefinition(definition);
    expect(holder.fields.single.id, -1);
    expect(
        ((data['formDraft'] as Map)['fields'] as List).single.containsKey('id'),
        false);
  });
  test(
      'shared appearance preserves custom geometry, clears per-element fonts and round-trips gradient',
      () {
    final d = draft();
    OccasionSetupAppearance.apply(
        d, Map.of(OccasionSetupAppearance.presets[1]));
    final layout =
        Map<String, dynamic>.from((d['ticketDraft'] as Map)['layout']);
    validateTicketLayout(layout);
    final raw = (layout['templates'] as Map)['wide'] as Map;
    final template = TicketTemplate.fromJson(raw);
    expect(template.toJson()['canvasGradient'], ['14284B', 'A87F28']);
    final box = Map.of((raw['elements'] as List).first['box']);
    OccasionSetupAppearance.apply(
        d, {...OccasionSetupAppearance.presets[2], 'id': 'custom'});
    final updated = (((d['ticketDraft'] as Map)['layout'] as Map)['templates']
        as Map)['wide'] as Map;
    expect((updated['elements'] as List).first['box'], box);
    expect(
        (((d['formDraft'] as Map)['data'] as Map)['design']
            as Map)['font_family'],
        'Russo One');
    expect(updated['fontId'], contains('russo-one'));
  });
  test(
      'ticket choice toggles only admission visibility, preserving products and seating',
      () {
    final data = draft(tickets: false);
    data['blueprintMode'] = 'copy';
    OccasionSetupStory.setTicketsEnabled(data, true);
    expect(OccasionSetupStory.hasTickets(data), true);
    final fields = (data['formDraft'] as Map)['fields'] as List;
    final ticket =
        fields.whereType<Map>().singleWhere((f) => f['type'] == 'ticket');
    ticket['title'] = 'My ticket';
    OccasionSetupStory.setTicketsEnabled(data, false);
    expect(OccasionSetupStory.hasTickets(data), false);
    expect(data['blueprintMode'], 'copy');
    OccasionSetupStory.setTicketsEnabled(data, true);
    expect(
        fields.whereType<Map>().where((f) => f['type'] == 'ticket').length, 1);
    expect(ticket['title'], 'My ticket');
  });
  test('light ticket palettes use dark text without moving geometry', () {
    final data = draft();
    OccasionSetupAppearance.apply(data, {
      ...OccasionSetupAppearance.presets.first,
      'primary': 'FFFFFF',
      'secondary': 'EEEEEE'
    });
    final template =
        (data['ticketDraft'] as Map)['layout']['templates']['wide'];
    expect(
        (template['elements'] as List)
            .where((e) => e['binding'] != 'qr')
            .every((e) => e['style']['color'] == '000000'),
        true);
  });
}

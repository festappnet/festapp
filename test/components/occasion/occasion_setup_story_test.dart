import 'package:fstapp/components/occasion/setup/occasion_setup_form_preview.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/app_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_draft.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_story.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance.dart';
import 'package:fstapp/components/ticket_layout/models/ticket_layout.dart';

void main() {
  Map<String, dynamic> draft(String kind, {num price = 0}) => {
        'eventKind': kind,
        'formDraft': {
          'title': 'Akce',
          'data': {},
          'fields': [
            {
              'product_type_data': {
                'products': [
                  {'price': price}
                ]
              }
            }
          ]
        }
      };
  for (final app in [false, true]) {
    for (final kind in OccasionSetupStory.kinds) {
      test('$kind app=$app: one active path drives positions and prerequisites',
          () {
        final d = draft(kind);
        final questions = OccasionSetupStory.questions(app, data: d);
        expect(questions.take(4).map((q) => q.key),
            ['name', 'dates', 'kind', 'appearance']);
        expect(questions.any((q) => q.key == 'blueprint'), kind == 'ball');
        expect(questions.any((q) => q.key == 'ticket'), false);
        expect(questions.any((q) => q.key == 'payments'), false);
        for (var i = 0; i < questions.length; i++) {
          expect(
              OccasionSetupStory.index({
                ...d,
                'step': questions[i].step,
                'storyQuestion': questions[i].key
              }, app),
              i);
        }
        expect(
            OccasionSetupStory.questions(app, data: draft(kind, price: 100))
                .any((q) => q.key == 'payments'),
            true);
      });
    }
  }
  test(
      'legacy resume and type changes retain inactive work and invalidate review',
      () {
    final d = <String, dynamic>{
      'title': 'Ples',
      'step': 6,
      'storyQuestion': 'blueprint',
      'blueprintObjects': [
        {'type': 'spot'}
      ],
      'reviewed': true
    };
    OccasionSetupStory.normalize(d, false);
    expect(d['eventKind'], 'ball');
    expect(d['eventKindNeedsConfirmation'], true);
    expect(d['reviewed'], false);
    d['eventKind'] = 'concert';
    OccasionSetupStory.normalize(d, false);
    expect(d['storyQuestion'], 'kind');
    expect(d['blueprintObjects'], isNotEmpty);
    d['eventKind'] = 'ball';
    expect(OccasionSetupStory.seats(d), true);
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
    final d = draft('regular');
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
  test('real public builders accept unsaved fields without assigning database IDs', () {
    final data=<String,dynamic>{'formDraft':{'title':'Přihláška','fields':[{'type':'email','is_required':true}]}};
    final definition=occasionSetupPreviewDefinition(data);
    final holder=FormHolder.fromDefinition(definition);
    expect(holder.fields.single.id,-1);
    expect(((data['formDraft'] as Map)['fields'] as List).single.containsKey('id'),false);
  });
  test(
      'shared appearance preserves custom geometry, clears per-element fonts and round-trips gradient',
      () {
    final d = draft('ball');
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
}

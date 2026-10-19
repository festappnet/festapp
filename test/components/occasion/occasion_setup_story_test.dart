import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_draft.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_story.dart';

void main() {
  for (final appSupported in [true, false]) {
    group('story appSupported=$appSupported', () {
      test('basics ask name, start and end separately; app link is conditional',
          () {
        final basics = OccasionSetupStory.questions(appSupported)
            .where((q) => q.step == 1)
            .map((q) => q.key);
        expect(
            basics,
            appSupported
                ? ['name', 'start', 'end', 'link']
                : ['name', 'start', 'end']);
      });
      test('every question resumes at its saved position', () {
        final pages = OccasionSetupStory.questions(appSupported);
        for (var i = 0; i < pages.length; i++) {
          expect(
              OccasionSetupStory.index({
                'step': pages[i].step,
                'storyQuestion': pages[i].key,
              }, appSupported),
              i);
        }
      });
      test(
          'legacy review resumes at review and stale question uses target step',
          () {
        final pages = OccasionSetupStory.questions(appSupported);
        expect(OccasionSetupStory.index({'step': 5}, appSupported),
            pages.length - 1);
        expect(
            pages[OccasionSetupStory.index({
              'step': 1,
              'storyQuestion': 'review',
            }, appSupported)]
                .key,
            'name');
      });
      test('optional verification does not introduce a required persisted step',
          () {
        final pages = OccasionSetupStory.questions(appSupported);
        expect(pages.where((q) => q.optional).single.key, 'verification');
        expect(pages.last.key, 'review');
        expect(pages.where((q) => !q.optional).map((q) => q.step).toSet(),
            appSupported ? {0, 1, 2, 3, 4, 5} : {0, 1, 2, 3, 4, 5, 6});
      });
    });
  }
  test('completed required steps reach 100% without organization verification',
      () {
    final draft = OccasionSetupDraft.fromJson({
      'id': 'draft',
      'unit': 1,
      'revision': 1,
      'current_step': 5,
      'data': {'title': 'Ples', 'completed': OccasionSetupDraft.supportedSteps},
    });
    expect(draft.progress, 100);
  });
}

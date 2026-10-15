import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/setup/occasion_form_draft.dart';

void main() {
  test('default draft uses an independent copy of canonical configuration', () {
    final configuration = <String, dynamic>{
      'forms': [
        {
          'title': 'Canonical title',
          'link': 'canonical-link',
          'deadline_duration_seconds': 259200,
          'fields': [
            {'type': 'email', 'is_required': true, 'order': 0}
          ],
        }
      ],
    };
    final form = defaultDraftForm(configuration);
    form.title = 'Edited';
    form.relatedFields.first.title = 'Contact';
    final restored = draftFormBundle(serializeDraftForm(form)).form;
    expect(restored.title, 'Edited');
    expect(restored.relatedFields.first.title, 'Contact');
    expect(restored.relatedFields.first.isRequired, true);
    expect(restored.deadlineDurationSeconds, 259200);
    expect(defaultDraftForm(configuration).title, 'Canonical title');
    expect(defaultDraftForm(configuration).relatedFields.first.title, isNull);
  });
}

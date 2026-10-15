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
    form.definition = form.definition.copyWith(title: 'Edited');
    form.relatedFields.first.definition =
        form.relatedFields.first.definition.copyWith(title: 'Contact');
    final restored = draftFormBundle(serializeDraftForm(form)).form;
    expect(restored.definition.title, 'Edited');
    expect(restored.relatedFields.first.definition.title, 'Contact');
    expect(restored.relatedFields.first.definition.isRequired, true);
    expect(restored.definition.deadlineDurationSeconds, 259200);
    expect(defaultDraftForm(configuration).definition.title, 'Canonical title');
    expect(defaultDraftForm(configuration).relatedFields.first.definition.title,
        isNull);
  });
}

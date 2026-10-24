import 'dart:convert';
import 'package:festapp_core/forms.dart';
import 'package:test/test.dart';

void main() {
  test('effective deadline distinguishes inherited null, zero and explicit values', () {
    final inherited = FormDefinition();
    expect(inherited.effectiveDeadlineDurationSeconds(occasionDefault: 259200),259200);
    expect(inherited.effectiveDeadlineDurationSeconds(),604800);
    expect(inherited.copyWith(deadlineDurationSeconds: 0).effectiveDeadlineDurationSeconds(occasionDefault: 259200),0);
    expect(inherited.copyWith(deadlineDurationSeconds: 86400).effectiveDeadlineDurationSeconds(),86400);
    expect(inherited.toJson()['deadline_duration_seconds'],isNull);
  });
  test('pre-start presentation round trips and retains its draft when hidden', () {
    final original = FormDefinition(data: {
      'schedule': {'custom': 9, 'enable_countdown': true},
    });
    expect(original.showBeforeStartMessage, isFalse);
    expect(original.beforeStartMessage, isNull);
    final edited = original
        .withBeforeStartMessage('<p>Informace</p><img src="https://example.test/hall.png">')
        .withShowBeforeStartMessage(true);
    final restored = FormDefinition.fromJson(jsonDecode(jsonEncode(edited)));
    expect(restored.showBeforeStartMessage, isTrue);
    expect(restored.beforeStartMessage, edited.beforeStartMessage);
    expect(restored.data!['schedule']['custom'], 9);
    expect(restored.enableCountdown, isTrue);
    expect(original.beforeStartMessage, isNull);
    final hidden = restored.withShowBeforeStartMessage(false);
    expect(hidden.showBeforeStartMessage, isFalse);
    expect(hidden.beforeStartMessage, restored.beforeStartMessage);
    expect(hidden.withBeforeStartMessage(null).beforeStartMessage, isNull);
  });

  test('form definition owns nested wire values and field options', () {
    final data = <String, dynamic>{
      'unknown': [
        {'retained': false},
      ],
    };
    final option = FormOptionDefinition(
      'first',
      'First',
      description: '<p>Info</p>',
    );
    final field = FormFieldDefinition(
      id: 7,
      type: FormMetadata.fieldTypeSelectOne,
      data: {'custom': data},
      options: [option],
      isHidden: false,
    );
    final form = FormDefinition(id: 1, data: data, relatedFields: [field]);
    (data['unknown'] as List).clear();
    expect(form.data!['unknown'], [
      {'retained': false},
    ]);
    expect(() => form.relatedFields.clear(), throwsUnsupportedError);
    expect(
      () => field.data['custom']['unknown'].clear(),
      throwsUnsupportedError,
    );
    expect(field.toJson()['data']['options'], [
      {'value': 'First', 'description': '<p>Info</p>'},
    ]);
    final wire = jsonDecode(jsonEncode(form));
    expect(wire['fields'].single['data']['custom']['unknown'], [
      {'retained': false},
    ]);
    expect(form.copyWith(title: null).title, isNull);
    expect(field.copyWith(description: null).description, isNull);
    expect(option.copyWith(description: null).description, isNull);
  });

  test(
    'definition read codecs preserve missing null empty and server capacity',
    () {
      for (final value in <Map<String, dynamic>>[
        {},
        {'data': null},
        {'data': {}},
      ]) {
        final form = FormDefinition.fromJson(value);
        expect(form.title, isNull);
        expect(form.waitlistEnabled, isFalse);
        expect(form.showRemainingCapacity, isTrue);
        expect(form.relatedFields, isEmpty);
        expect(form.withPrimaryColor(null).data, form.data);
        expect(form.withStartTimeUtc(null).data, form.data);
      }
      final form = FormDefinition.fromJson({
        'occasion': {'id': 59, 'unused': 'context'},
        'bank_account': 4,
        'registrationMode': 'waitlist',
        'capacity': {
          'remainingPublic': 2,
          'unknown': [1],
        },
        'participant_capacity': 0,
      });
      expect(form.occasionId, 59);
      expect(form.toJson()['occasion'], 59);
      expect(form.toJson()['bank_account'], 4);
      expect(form.isWaitlist, isTrue);
      expect(form.capacity!.remainingPublic, 2);
      expect(form.participantCapacity, 0);
      expect(
        () => (form.capacity!.data['unknown'] as List).clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('metadata transformations preserve sibling and unknown keys', () {
    final original = FormDefinition(
      data: {
        'design': {'unknown': false},
        'schedule': {'custom': 9},
        'unknown': null,
      },
    );
    final start = DateTime.utc(2026, 8, 8, 22, 30);
    final updated = original
        .withPrimaryColor(0xff123456)
        .withStartTimeUtc(start)
        .withCountdownTitle('Start');
    expect(updated.startTimeUtc, start);
    expect(updated.data!['schedule']['start_time'], '2026-08-08T22:30:00.000Z');
    expect(updated.data!['schedule']['custom'], 9);
    expect(updated.data!['design']['unknown'], false);
    expect(updated.data!.containsKey('unknown'), isTrue);
    expect(original.primaryColor, isNull);
    expect(updated.withCountdownTitle(null).countdownTitle, isNull);
    expect(updated.withStartTimeUtc(null).startTimeUtc, isNull);
  });
}

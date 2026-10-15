import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/speakers/db_speakers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('recognizes PostgREST missing-function responses', () {
    expect(
      isMissingSpeakersRpc(
        const PostgrestException(message: 'function not found', code: 'PGRST202'),
      ),
      isTrue,
    );
    expect(
      isMissingSpeakersRpc(
        const PostgrestException(message: 'permission denied', code: '42501'),
      ),
      isFalse,
    );
  });
}

import 'package:supabase_flutter/supabase_flutter.dart';

/// Compatibility with the pre-PT409 wizard backend only. A real PostgreSQL
/// serialization failure is not proof that the organizer's draft changed.
bool isSetupDraftConflict(Object error) =>
    error is PostgrestException &&
    (error.code == 'PT409' ||
        error.code == '40001' &&
            const {
              'Draft revision conflict',
              'Draft changed in another session',
              'Bank account details changed; select again',
            }.contains(error.message));

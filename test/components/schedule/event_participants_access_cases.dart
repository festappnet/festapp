import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/schedule/event_participants_access.dart';

void main() {
  group('event participants access', () {
    test('online editor-view, editors and admins load participants', () {
      expect(
        EventParticipantsAccess.shouldLoad(
          isOffline: false,
          isEditorView: true,
          isEditor: false,
          isAdmin: false,
        ),
        isTrue,
      );
      expect(
        EventParticipantsAccess.shouldLoad(
          isOffline: false,
          isEditorView: false,
          isEditor: true,
          isAdmin: false,
        ),
        isTrue,
      );
      expect(
        EventParticipantsAccess.shouldLoad(
          isOffline: false,
          isEditorView: false,
          isEditor: false,
          isAdmin: true,
        ),
        isTrue,
      );
    });

    test('users without view, editor or admin rights cannot see participants',
        () {
      expect(
        EventParticipantsAccess.canView(
          isEditorView: false,
          isEditor: false,
          isAdmin: false,
        ),
        isFalse,
      );
    });

    test('participants are not loaded while offline', () {
      expect(
        EventParticipantsAccess.shouldLoad(
          isOffline: true,
          isEditorView: true,
          isEditor: true,
          isAdmin: false,
        ),
        isFalse,
      );
    });
  });
}

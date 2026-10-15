class EventParticipantsAccess {
  static bool canView({
    required bool isEditorView,
    required bool isEditor,
    required bool isAdmin,
  }) => isEditorView || isEditor || isAdmin;

  static bool shouldLoad({
    required bool isOffline,
    required bool isEditorView,
    required bool isEditor,
    required bool isAdmin,
  }) =>
      !isOffline &&
      canView(isEditorView: isEditorView, isEditor: isEditor, isAdmin: isAdmin);
}

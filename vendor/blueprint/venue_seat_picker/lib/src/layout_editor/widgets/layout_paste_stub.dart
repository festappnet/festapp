/// Native platforms use Flutter's Clipboard API from the keyboard shortcut.
const usesNativePasteEvents = false;

void Function() listenForLayoutPaste(bool Function(String) accept) => () {};

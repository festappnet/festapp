import 'dart:async';
import 'support/native_drop_test_bootstrap_stub.dart'
    if (dart.library.io) 'support/editor_file_drop.dart' as drop;

Future<void> testExecutable(FutureOr<void> Function() main) async {
  // Unit-test engines do not link the OS drag-and-drop FFI library. Install
  // only its native transport fixture; browser tests retain the real DOM plugin.
  drop.registerEditorFileDrops();
  await main();
}

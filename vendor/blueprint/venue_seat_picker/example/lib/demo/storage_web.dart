import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'locations.dart';

const _key = 'venue-layout-demo:v1:local';
Future<String?> readDraft() async {
  final stored = await _readStoredDraft(_key);
  if (stored != null) return stored;
  // Preserve drafts from older demos. IndexedDB is authoritative once migrated.
  String? legacy;
  try {
    legacy = web.window.localStorage.getItem(_key);
  } catch (_) {
    // Browser policy can block localStorage independently of IndexedDB.
  }
  if (legacy != null) await writeDraft(legacy);
  return legacy;
}

Future<void> _pendingWrite = Future<void>.value();
Future<void> writeDraft(String value) {
  // Serialize autosaves and explicit saves so an older draft cannot win a race.
  final write = _pendingWrite.then((_) => _writeStoredDraft(_key, value));
  _pendingWrite = write.then<void>(
    (_) {},
    onError: (Object _, StackTrace _) {},
  );
  return write;
}

Future<void> _writeStoredDraft(String key, String value) async {
  final database = await _previewDatabase();
  try {
    final complete = Completer<void>();
    final transaction = database.transaction('drafts'.toJS, 'readwrite');
    transaction.oncomplete = ((web.Event _) => complete.complete()).toJS;
    transaction.onabort = ((web.Event _) {
      complete.completeError(StateError('Draft could not be saved'));
    }).toJS;
    transaction.objectStore('drafts').put(value.toJS, key.toJS);
    await complete.future;
  } finally {
    database.close();
  }
  if (key == _key) {
    try {
      web.window.localStorage.removeItem(_key);
    } catch (_) {
      // A committed IndexedDB save does not depend on legacy storage access.
    }
  }
}

Future<String?> _readStoredDraft(String key) async {
  final database = await _previewDatabase();
  try {
    final complete = Completer<String?>();
    final transaction = database.transaction('drafts'.toJS);
    final request = transaction.objectStore('drafts').get(key.toJS);
    transaction.oncomplete = ((web.Event _) {
      complete.complete((request.result as JSString?)?.toDart);
    }).toJS;
    transaction.onabort = ((web.Event _) {
      complete.completeError(StateError('Draft could not be restored'));
    }).toJS;
    return await complete.future;
  } finally {
    database.close();
  }
}

Future<web.IDBDatabase> _previewDatabase() {
  final result = Completer<web.IDBDatabase>();
  final request = web.window.indexedDB.open('venue-layout-preview', 1);
  request.onupgradeneeded = ((web.Event _) {
    (request.result as web.IDBDatabase).createObjectStore('drafts');
  }).toJS;
  request.onsuccess = ((web.Event _) {
    if (!result.isCompleted) {
      result.complete(request.result as web.IDBDatabase);
    } else {
      (request.result as web.IDBDatabase).close();
    }
  }).toJS;
  request.onerror = ((web.Event _) {
    if (!result.isCompleted) {
      result.completeError(StateError('Preview storage unavailable'));
    }
  }).toJS;
  request.onblocked = ((web.Event _) {
    if (!result.isCompleted) {
      result.completeError(StateError('Preview storage is blocked'));
    }
  }).toJS;
  return result.future;
}

/// A committed IndexedDB transaction carries the complete portable document.
/// Navigation happens only after persistence, including embedded resources.
Future<void> openWebPreview(String value) async {
  const sessionKey = 'venue-layout-preview:tab';
  final token =
      web.window.sessionStorage.getItem(sessionKey) ??
      web.window.crypto.randomUUID();
  web.window.sessionStorage.setItem(sessionKey, token);
  final editor = Uri.base.replace(
    queryParameters: {...Uri.base.queryParameters}..remove('fromPreview'),
  );
  web.window.sessionStorage.setItem(
    'venue-layout-preview:editor:$token',
    editor.toString(),
  );
  await _writeStoredDraft(token, value);
  web.window.location.assign(
    previewLocation(
      editor,
    ).replace(queryParameters: {'editor': token}).toString(),
  );
}

Future<String?> readPreviewDraft() async {
  final token = Uri.base.queryParameters['fromPreview'];
  if (token == null || !RegExp(r'^[a-f0-9-]{36}$').hasMatch(token)) return null;
  final value = await _readStoredDraft(token);
  final clean = Uri.base.replace(
    queryParameters: {...Uri.base.queryParameters}..remove('fromPreview'),
  );
  web.window.history.replaceState(null, '', clean.toString());
  return value;
}

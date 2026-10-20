import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

const _key = 'venue-layout-demo:v1:local';
String? readDraft() => web.window.localStorage.getItem(_key);
void writeDraft(String value) => web.window.localStorage.setItem(_key, value);

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
  final database = await _previewDatabase();
  try {
    final complete = Completer<void>();
    final transaction = database.transaction('drafts'.toJS, 'readwrite');
    transaction.oncomplete = ((web.Event _) => complete.complete()).toJS;
    transaction.onabort = ((web.Event _) {
      if (!complete.isCompleted) {
        complete.completeError(StateError('Preview could not be saved'));
      }
    }).toJS;
    transaction.objectStore('drafts').put(value.toJS, token.toJS);
    await complete.future;
  } finally {
    database.close();
  }
  web.window.location.assign('/js/demo/?editor=$token');
}

Future<String?> readPreviewDraft() async {
  final token = Uri.base.queryParameters['fromPreview'];
  if (token == null || !RegExp(r'^[a-f0-9-]{36}$').hasMatch(token)) return null;
  final database = await _previewDatabase();
  try {
    final complete = Completer<String?>();
    final request = database
        .transaction('drafts'.toJS)
        .objectStore('drafts')
        .get(token.toJS);
    request.onsuccess = ((web.Event _) {
      complete.complete((request.result as JSString?)?.toDart);
    }).toJS;
    request.onerror = ((web.Event _) {
      complete.completeError(StateError('Saved preview could not be restored'));
    }).toJS;
    final value = await complete.future;
    web.window.history.replaceState(null, '', '/flutter/');
    return value;
  } finally {
    database.close();
  }
}

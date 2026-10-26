import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:sembast/sembast.dart';
import 'package:sembast_web/sembast_web.dart';
import 'package:fstapp/services/bounded_database_opener.dart';

final opener = BoundedDatabaseOpener(open: databaseFactoryWeb.openDatabase);
final databases = <String, Database>{};

Future<JSString> openFixture(JSString jsPath) async {
  final path = jsPath.toDart;
  final Database db;
  try {
    db = await opener.get(path);
  } on StorageOpenTimeoutException {
    return jsonEncode({'status': 'open-timeout'}).toJS;
  }
  databases[path] = db;
  final store = StoreRef<String, String>('fixture');
  final existing = await store.record('preserved').get(db);
  await store.record('preserved').put(db, existing ?? 'value-kept');
  return jsonEncode({'status': 'opened', 'value': await store.record('preserved').get(db)}).toJS;
}

void main() {
  globalContext.setProperty('openSembastFixture'.toJS,
      ((JSString path) => openFixture(path).toJS).toJS);
  globalContext.setProperty('closeSembastFixture'.toJS,
      ((JSString path) => databases[path.toDart]!.close().toJS).toJS);
  globalContext.setProperty('fixtureReady'.toJS, true.toJS);
}

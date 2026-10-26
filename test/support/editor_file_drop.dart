import 'dart:async';

import 'package:cross_file_io/cross_file_io.dart';
import 'package:desktop_drop/desktop_drop_testing.dart';
import 'package:fstapp/services/import_file.dart';
import 'package:fstapp/components/images/image_upload_limits.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> droppedFile(
  String name,
  List<int> bytes, {
  bool directory = false,
}) => {
  'uri': '/test/$name',
  'name': name,
  'type': directory ? 'directory' : 'application/octet-stream',
  'size': bytes.length,
  'lastModified': 0,
  'data': Uint8List.fromList(bytes),
  'children': <Object>[],
};

// Exercise the real plugin coordinator and provider reader through its native
// testing transport. Every drop owns a source session until its async reply.
final _transport = NativeTransport.testing();
final _sources = <String, Map<String, Object?>>{};
final _children = <String, List<Map<String, Object?>>>{};
final _streams = <int, (Uint8List, int)>{};
final _readHolds = <int, Future<void>>{};
var _session = 0;
var _stream = 0;
bool _registered = false;
void registerEditorFileDrops() {
  if (_registered) return;
  _registered = true;
  CrossFileIO.registerWith();
  NativeTransport.debugOverride = _transport;
  _transport.invokeHandler = (call) async {
    if (call.method != 'readSource') return {'view': 0, 'generation': 7};
    final args = call.arguments as Map;
    final source = _sources['${args['session']}/${args['source']}'];
    if (source == null) throw PlatformException(code: 'source_expired');
    final bytes = source['data'] as Uint8List;
    switch (args['op']) {
      case 'list':
        return _children['${args['session']}/${args['source']}'] ??
            <Map<String, Object?>>[];
      case 'stat':
        return {'length': bytes.length};
      case 'open':
        final id = ++_stream;
        _streams[id] = (bytes, args['start'] as int? ?? 0);
        return id;
      case 'read':
        await _readHolds[args['session']];
        final id = args['stream'] as int;
        final (data, offset) = _streams[id]!;
        final end = (offset + (args['count'] as int)).clamp(0, data.length);
        _streams[id] = (data, end);
        return Uint8List.sublistView(data, offset, end);
      case 'close':
        _streams.remove(args['stream']);
        return null;
    }
    throw StateError('Unexpected source read ${args['op']}');
  };
}

Future<void> pluginDrop(
  WidgetTester tester,
  Offset position,
  List<Map<String, Object?>> files, {
  Future<void>? beforeRead,
}) async {
  final session = ++_session;
  if (beforeRead != null) _readHolds[session] = beforeRead;
  var nextSource = 0;
  Map<String, Object?> reference(Map<String, Object?> file) {
    final id = nextSource++;
    _sources['$session/$id'] = file;
    _children['$session/$id'] = [
      for (final child
          in (file['children'] as List? ?? const [])
              .cast<Map<String, Object?>>())
        reference(child),
    ];
    return {
      'name': file['name'],
      'mimeType': file['type'],
      'isDirectory': file['type'] == 'directory',
      'source': id,
    };
  }

  final offer = {
    'allowedOperations': ['copy'],
    'isComplete': true,
    'files': [for (final file in files) reference(file)],
  };
  void release() {
    _readHolds.remove(session);
    _sources.removeWhere((key, _) => key.startsWith('$session/'));
    _children.removeWhere((key, _) => key.startsWith('$session/'));
  }

  Map<String, Object?> event([int target = 0]) => {
    'view': 0,
    'generation': 7,
    'session': session,
    'request': session * 1000,
    'phase': 1,
    'target': target,
    'operation': 1,
    'x': position.dx,
    'y': position.dy,
    'offer': offer,
  };
  final query = await _transport.onEvent!(MethodCall('query', event())) as Map;
  final target = query['target'] as int;
  if (target == 0) {
    release();
    return;
  }
  expect(
    query['operation'],
    1,
    reason: 'Imports must copy, never move source files',
  );
  await _transport.onEvent!(MethodCall('feedback', event(target)));
  unawaited(
    _transport.onEvent!(MethodCall('drop', event(target))).whenComplete(
      release,
    ),
  );
  await tester.pump();
}

class OversizedEditorImage extends ImportFile {
  OversizedEditorImage()
    : super(
        name: 'too-large.png',
        readBytes: () async =>
            throw StateError('Oversized input must never be read'),
      );
  bool read = false;
  @override
  Future<int> length() async => ImageUploadLimits.maxInputBytes + 1;
  @override
  Future<Uint8List> readAsBytes() async {
    read = true;
    throw StateError('Oversized input must never be read');
  }
}

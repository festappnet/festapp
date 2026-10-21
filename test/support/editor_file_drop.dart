import 'package:cross_file/cross_file.dart';
import 'package:fstapp/components/images/image_upload_limits.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> droppedFile(String name, List<int> bytes,
        {bool directory = false}) =>
    {
      'uri': '/test/$name',
      'name': name,
      'type': directory ? 'directory' : 'application/octet-stream',
      'size': bytes.length,
      'lastModified': 0,
      'data': Uint8List.fromList(bytes),
      'children': <Object>[],
    };

/// Deliver the actual plugin channel events, exercising all mounted targets.
Future<void> pluginDrop(WidgetTester tester, Offset position,
    List<Map<String, Object?>> files) async {
  const codec = StandardMethodCodec();
  final messenger = tester.binding.defaultBinaryMessenger;
  await messenger.handlePlatformMessage(
      'desktop_drop',
      codec.encodeMethodCall(MethodCall('entered', [position.dx, position.dy])),
      (_) {});
  await messenger.handlePlatformMessage(
      'desktop_drop',
      codec.encodeMethodCall(MethodCall('performOperation_web', files)),
      (_) {});
  await tester.pump();
}

class OversizedEditorImage extends XFile {
  OversizedEditorImage() : super('too-large.png');
  bool read = false;
  @override
  Future<int> length() async => ImageUploadLimits.maxInputBytes + 1;
  @override
  Future<Uint8List> readAsBytes() async {
    read = true;
    throw StateError('Oversized input must never be read');
  }
}

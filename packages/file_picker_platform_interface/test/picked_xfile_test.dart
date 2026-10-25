import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cross_file_io/cross_file_io.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(CrossFileIO.registerWith);
  test(
    'cached bytes retain Unicode names, content and independent range streams',
    () async {
      final original = Uint8List.fromList(utf8.encode('Žluťoučký kůň'));
      final data = Uint8List.fromList(original);
      final file = pickedXFile(
        Uri.parse('memory:picked'),
        name: 'Příloha #1.csv',
        bytes: data,
      );
      data.fillRange(0, data.length, 0);
      expect(await file.name(), 'Příloha #1.csv');
      expect(await file.readAsBytes(), original);
      expect(await file.readAsString(), 'Žluťoučký kůň');
      expect(await file.length(), original.length);
      expect(await file.exists(), isTrue);
      for (var i = 0; i < 2; i++) {
        expect(
          await file.openRead(1, 4).expand((b) => b).toList(),
          original.sublist(1, 4),
        );
      }
      expect(await file.openRead(0, 999).expand((b) => b).toList(), original);
    },
  );
  test(
    'empty preloaded files remain readable without a backing file',
    () async {
      final file = pickedXFile(
        Uri.parse('memory:empty'),
        name: 'empty.csv',
        bytes: Uint8List(0),
      );
      expect(await file.length(), 0);
      expect(await file.readAsString(), '');
      expect(await file.exists(), isTrue);
    },
  );
  test(
    'filesystem URI encoding and picker display name survive lazy reads',
    () async {
      final directory = await Directory.systemTemp.createTemp('picker-port-');
      addTearDown(() => directory.delete(recursive: true));
      final source = File('${directory.path}/Žluťoučký #1 %.csv');
      await source.writeAsString('Jméno;příjmení\nJan;Novák');
      final file = pickedXFile(source.uri, name: 'Příloha.csv');
      expect(await file.name(), 'Příloha.csv');
      expect(await file.readAsString(), await source.readAsString());
      expect(await file.readAsBytes(), await source.readAsBytes());
      expect(await file.length(), await source.length());
      expect(
        await file.openRead(2, 8).expand((b) => b).toList(),
        (await source.readAsBytes()).sublist(2, 8),
      );
      await source.delete();
      expect(file.readAsBytes(), throwsA(isA<FileSystemException>()));
    },
  );
}

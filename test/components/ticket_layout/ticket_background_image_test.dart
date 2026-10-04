import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:fstapp/components/ticket_layout/ticket_background_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('suitable JPEG and transparent PNG retain original bytes', () async {
    final image=img.Image(width:40,height:20,numChannels:4);
    img.fill(image,color:img.ColorRgba8(20,100,200,100));
    for(final bytes in [img.encodeJpg(image,quality:75),img.encodePng(image)]) {
      expect(await TicketBackgroundImage.prepare(Uint8List.fromList(bytes)),bytes);
    }
  });
  test('large landscape and portrait artwork scale down by the longer edge', () async {
    for(final size in [(4320,80),(80,4320)]) {
      final image=img.Image(width:size.$1,height:size.$2,numChannels:4);
      img.fill(image,color:img.ColorRgba8(25,120,200,80));
      final result=await TicketBackgroundImage.prepare(Uint8List.fromList(img.encodePng(image)));
      final decoded=img.decodePng(result)!;
      expect((decoded.width,decoded.height),size.$1>size.$2?(1080,20):(20,1080));
      expect(decoded.getPixel(0,0).a,80);
      expect(result.length,lessThanOrEqualTo(TicketBackgroundImage.maxBytes));
    }
  });
  test('large JPEG is resized without upscaling its short edge', () async {
    final image=img.Image(width:4000,height:100);
    final bytes=await TicketBackgroundImage.prepare(Uint8List.fromList(img.encodeJpg(image,quality:98)));
    final decoded=img.decodeJpg(bytes)!;
    expect((decoded.width,decoded.height),(1080,27));
  });
  test('invalid image fails before upload', () async {
    await expectLater(TicketBackgroundImage.prepare(Uint8List.fromList([1,2,3])),throwsFormatException);
  });
}

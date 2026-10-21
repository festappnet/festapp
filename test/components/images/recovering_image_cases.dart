import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/images/recovering_image.dart';

class _PreviewProvider extends ImageProvider<_PreviewProvider> {
  _PreviewProvider({required this.image, this.failures = 1});
  final ui.Image image;
  final int failures;
  int calls = 0;
  @override
  Future<_PreviewProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(
      _PreviewProvider key, ImageDecoderCallback decode) {
    calls++;
    return OneFrameImageStreamCompleter(calls <= failures
        ? Future<ImageInfo>.error(StateError('Temporary preview failure'))
        : SynchronousFuture(ImageInfo(image: image)));
  }
}

void main() {
  testWidgets('a transient image failure recovers without reloading the grid',
      (tester) async {
    final provider = _PreviewProvider(
        image: (await tester
            .runAsync(() => createTestImage(width: 200, height: 300)))!);
    await tester
        .pumpWidget(MaterialApp(home: RecoveringImage(image: provider)));
    await tester.pump();
    expect(find.byIcon(Icons.broken_image), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(provider.calls, 2);
    expect(find.byIcon(Icons.broken_image), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
  });
  testWidgets('a permanently missing image stops retrying', (tester) async {
    final provider = _PreviewProvider(
        image: (await tester
            .runAsync(() => createTestImage(width: 200, height: 300)))!,
        failures: 100);
    await tester
        .pumpWidget(MaterialApp(home: RecoveringImage(image: provider)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(provider.calls, 3);
    expect(find.byIcon(Icons.broken_image), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(provider.calls, 3);
  });
  testWidgets(
      'changing the image cancels a pending retry of the previous preview',
      (tester) async {
    final old = _PreviewProvider(
        image: (await tester
            .runAsync(() => createTestImage(width: 200, height: 300)))!,
        failures: 100);
    final current = _PreviewProvider(
        image: (await tester
            .runAsync(() => createTestImage(width: 200, height: 300)))!,
        failures: 0);
    await tester.pumpWidget(MaterialApp(home: RecoveringImage(image: old)));
    await tester.pump();
    await tester.pumpWidget(MaterialApp(home: RecoveringImage(image: current)));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(old.calls, 1);
    expect(current.calls, 1);
    expect(find.byIcon(Icons.broken_image), findsNothing);
  });
  testWidgets('leaving the grid cancels its pending image retry',
      (tester) async {
    final provider = _PreviewProvider(
        image: (await tester
            .runAsync(() => createTestImage(width: 200, height: 300)))!,
        failures: 100);
    await tester
        .pumpWidget(MaterialApp(home: RecoveringImage(image: provider)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    expect(provider.calls, 1);
    expect(tester.takeException(), isNull);
  });
}

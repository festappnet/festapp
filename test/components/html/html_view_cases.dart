import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

void main() {
  testWidgets(
      'HTML links launch directly without an asynchronous capability probe',
      (tester) async {
    const url = 'https://docs.google.com/spreadsheets/d/carpool/edit';
    final calls = <MethodCall>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: HtmlView(
        html: '<a href="$url">Tabulka spolujízdy</a>',
        offlineOverride: false,
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tabulka spolujízdy', findRichText: true));
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method), ['launch']);
    expect(calls.single.arguments['url'], url);
    expect(calls.single.arguments['useWebView'], isFalse);
  });

  testWidgets('plain contacts are clickable in existing displayed HTML',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: HtmlView(
      html: '<p>or call 731140198, info@example.org, www.example.org</p>',
      offlineOverride: false,
    ))));
    final rendered = tester
        .widget<HtmlWithAppLinksWidget>(find.byType(HtmlWithAppLinksWidget));
    expect(rendered.html, contains('href="tel:731140198"'));
    expect(rendered.html, contains('href="mailto:info@example.org"'));
    expect(rendered.html, contains('href="https://www.example.org"'));
  });

  testWidgets('public HTML images use the stable web byte renderer',
      (tester) async {
    const imageUrl =
        'https://a.img.festapp.net/images/643/information-image.png';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HtmlView(
          html: '<img src="$imageUrl">',
          offlineOverride: false,
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(CachedNetworkImage), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image as CachedNetworkImageProvider;
    expect(provider.url, imageUrl);
    expect(
      provider.imageRenderMethodForWeb,
      ImageRenderMethodForWeb.HttpGet,
    );
  });

  test('recognizes common YouTube URL variants', () {
    const id = 'dQw4w9WgXcQ';
    expect(youtubeVideoIdFromUrl('https://youtu.be/$id?si=abc'), id);
    expect(youtubeVideoIdFromUrl('https://youtube.com/shorts/$id'), id);
    expect(youtubeVideoIdFromUrl('https://youtube.com/embed/$id'), id);
    expect(
      youtubeVideoIdFromUrl('https://youtube.com/watch?si=abc&v=$id'),
      id,
    );
  });

  testWidgets('offline YouTube anchor becomes a disabled external link',
      (tester) async {
    const url = 'https://youtu.be/dQw4w9WgXcQ';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: HtmlView(
          html: '<a href="$url">Video</a>',
          offlineOverride: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(YoutubePlayer), findsNothing);
    expect(find.text(url), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
  });
}
